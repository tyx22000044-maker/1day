import Foundation
import SwiftData
import UIKit
import UserNotifications

final class PlanNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.configureCategories()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == NotificationService.completeActionIdentifier else {
            completionHandler()
            return
        }
        guard
            let idString = response.notification.request.content.userInfo["planItemId"] as? String,
            let itemID = UUID(uuidString: idString)
        else {
            completionHandler()
            return
        }

        Task {
            await completeTask(itemID: itemID)
            completionHandler()
        }
    }

    @MainActor
    private func completeTask(itemID: UUID) {
        do {
            // 复用 App 主容器，避免在同一个 store 上并存第二个容器。
            let container = AppContainer.current
            var descriptor = FetchDescriptor<PlanItem>(
                predicate: #Predicate { item in
                    item.id == itemID
                }
            )
            descriptor.fetchLimit = 1

            guard let item = try container.mainContext.fetch(descriptor).first else {
                AppLogger.warning("Notification task not found: \(itemID)")
                return
            }

            PlanItemService.setCompletion(item, isCompleted: true)
            try container.mainContext.save()
        } catch {
            AppLogger.dataError("Failed to complete task from notification: \(error.localizedDescription)")
        }
    }
}

/// 一次提醒所需的值拷贝。
///
/// 必须是纯值：旧实现把 `PlanItem` 带进 `Task { }`，跨并发边界访问 @Model，
/// 任务可能在对象已被删除或改完之后才去读它的 title/notes。
struct ReminderRequest: Equatable, Sendable {
    let itemID: UUID
    let title: String
    let body: String
    let triggerDate: Date

    var notificationIdentifier: String { Self.identifier(for: itemID) }

    static func identifier(for itemID: UUID) -> String {
        "plan-task-\(itemID.uuidString)"
    }
}

/// 通知中心的可替换出口，便于单测注入。
protocol NotificationDelivering: Sendable {
    func waitForAuthorization() async -> Bool
    func removePending(identifier: String) async
    func add(_ request: ReminderRequest) async throws
}

struct UserNotificationDelivery: NotificationDelivering {
    func waitForAuthorization() async -> Bool {
        await NotificationService.requestAuthorizationIfNeeded()
    }

    func removePending(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func add(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.categoryIdentifier = NotificationService.taskCategoryIdentifier
        content.userInfo = ["planItemId": request.itemID.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: request.notificationIdentifier, content: content, trigger: trigger)
        )
    }
}

/// 按任务 id 串行化的提醒调度器。
///
/// 旧实现每次 `scheduleTaskReminder` 都裸开一个 Task，remove 和 add 分别在不同
/// 异步流里完成：连续快速改日期 / 完成 / 撤销时，旧请求可能后完成，把已经排好的
/// 新提醒删掉，通知中心留下指向旧日期的条目。
///
/// 现在同一个 itemID 的操作串成一条链：后一次一定等前一次彻底结束才开始，
/// 因此「最后一次提交」必然也是「最后一次落地」。代次用于让已被取代的操作整段跳过。
actor NotificationScheduler {
    static let shared = NotificationScheduler(delivery: UserNotificationDelivery())

    private let delivery: NotificationDelivering
    private var generations: [UUID: Int] = [:]
    private var tails: [UUID: Task<Void, Never>] = [:]
    private var chainSerials: [UUID: Int] = [:]

    init(delivery: NotificationDelivering) {
        self.delivery = delivery
    }

    func schedule(_ request: ReminderRequest) async {
        let generation = bump(request.itemID)
        await chain(request.itemID) { [delivery] in
            await self.perform(request, generation: generation, delivery: delivery)
        }
    }

    func cancel(itemID: UUID) async {
        let generation = bump(itemID)
        await chain(itemID) { [delivery] in
            guard await self.isCurrent(itemID, generation) else { return }
            await delivery.removePending(identifier: ReminderRequest.identifier(for: itemID))
            AppLogger.data("Cancelled task reminder: \(itemID)")
        }
    }

    func cancelAll(itemIDs: [UUID]) async {
        for id in itemIDs {
            await cancel(itemID: id)
        }
    }

    private func perform(
        _ request: ReminderRequest,
        generation: Int,
        delivery: NotificationDelivering
    ) async {
        guard isCurrent(request.itemID, generation) else {
            AppLogger.data("跳过已被取代的提醒调度: \(request.itemID)")
            return
        }
        guard await delivery.waitForAuthorization() else {
            AppLogger.warning("Notification permission not granted for \(request.itemID)")
            return
        }
        guard isCurrent(request.itemID, generation) else {
            AppLogger.data("跳过已被取代的提醒调度: \(request.itemID)")
            return
        }
        await delivery.removePending(identifier: request.notificationIdentifier)
        do {
            try await delivery.add(request)
            AppLogger.data("Scheduled task reminder: \(request.itemID)")
        } catch {
            AppLogger.dataError("Failed to schedule task reminder: \(error.localizedDescription)")
        }
    }

    /// 把新操作接到该任务已有链路末尾，并等它跑完。
    private func chain(_ itemID: UUID, _ work: @escaping @Sendable () async -> Void) async {
        let serial = (chainSerials[itemID] ?? 0) + 1
        chainSerials[itemID] = serial
        let previous = tails[itemID]
        let current = Task {
            await previous?.value
            await work()
        }
        tails[itemID] = current
        await current.value

        // 只有在我执行期间没有更新的操作排队时，才释放链尾，避免字典无界增长。
        if chainSerials[itemID] == serial {
            tails[itemID] = nil
            chainSerials[itemID] = nil
        }
    }

    private func bump(_ itemID: UUID) -> Int {
        let generation = (generations[itemID] ?? 0) + 1
        generations[itemID] = generation
        return generation
    }

    private func isCurrent(_ itemID: UUID, _ generation: Int) -> Bool {
        generations[itemID] == generation
    }
}

enum NotificationService {
    static let completeActionIdentifier = "COMPLETE_TASK"
    static let taskCategoryIdentifier = "TASK_REMINDER"

    private static let defaultReminderHourKey = "1plan.defaultReminderHour"
    private static let defaultReminderMinuteKey = "1plan.defaultReminderMinute"

    private static var defaultReminderHour: Int {
        UserDefaults.standard.object(forKey: defaultReminderHourKey) != nil
            ? UserDefaults.standard.integer(forKey: defaultReminderHourKey)
            : 9
    }

    private static var defaultReminderMinute: Int {
        UserDefaults.standard.integer(forKey: defaultReminderMinuteKey)
    }

    static func syncDefaultReminderTime(hour: Int, minute: Int) {
        UserDefaults.standard.set(hour, forKey: defaultReminderHourKey)
        UserDefaults.standard.set(minute, forKey: defaultReminderMinuteKey)
    }

    static func configureCategories() {
        let completeAction = UNNotificationAction(
            identifier: completeActionIdentifier,
            title: "标记完成",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: taskCategoryIdentifier,
            actions: [completeAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async -> Bool {
        await requestAuthorizationIfNeeded()
    }

    /// 当前授权状态；`notDetermined` 时不弹系统弹窗（用于失败反馈，见 F-13）。
    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                AppLogger.dataError("Failed to request notification authorization: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    static func scheduleTaskReminder(for item: PlanItem) {
        guard let request = reminderRequest(for: item) else {
            cancelTaskReminder(for: item)
            return
        }
        // 需要读 model 的部分已经同步取完，跨并发边界的只有值拷贝。
        Task { await NotificationScheduler.shared.schedule(request) }
    }

    /// 从任务同步读出通知快照。已完成 / 没有日期 / 触发时间已过，一律归为「不该有提醒」。
    static func reminderRequest(for item: PlanItem) -> ReminderRequest? {
        guard !item.isCompleted, let dueDate = item.dueDate else { return nil }
        let triggerDate = reminderDate(for: dueDate, reminderTime: item.reminderTime)
        guard triggerDate > Date() else { return nil }
        return ReminderRequest(
            itemID: item.id,
            title: item.title,
            body: notificationBody(for: item, triggerDate: triggerDate),
            triggerDate: triggerDate
        )
    }

    static func cancelTaskReminder(for item: PlanItem) {
        cancelTaskReminder(itemID: item.id)
    }

    static func cancelTaskReminder(itemID: UUID) {
        Task { await NotificationScheduler.shared.cancel(itemID: itemID) }
    }

    static func notificationIdentifier(for itemID: UUID) -> String {
        ReminderRequest.identifier(for: itemID)
    }

    private static func notificationBody(for item: PlanItem, triggerDate: Date) -> String {
        let cal = Calendar.current
        let dueDate = item.dueDate ?? triggerDate
        let isHigh = item.priority == .high
        let isToday = cal.isDateInToday(dueDate)
        let isTomorrow = cal.isDateInTomorrow(dueDate)

        if !item.notes.isEmpty {
            let prefix = isHigh ? "重要：" : ""
            return prefix + item.notes
        }

        if isToday {
            return isHigh ? "今天必须完成，重要任务" : "今天的待办，别忘了"
        }
        if isTomorrow {
            return isHigh ? "明天的重要任务，提前提醒" : "明天到期，提前提醒你"
        }
        let weekday = dueDate.formatted(.dateTime.weekday(.wide))
        return isHigh ? "\(weekday)到期，重要任务" : "\(weekday)到期，记得处理"
    }

    private static func reminderDate(for dueDate: Date, reminderTime: Date?) -> Date {
        let calendar = Calendar.current
        let timeSource = reminderTime ?? calendar.date(
            bySettingHour: defaultReminderHour,
            minute: defaultReminderMinute,
            second: 0,
            of: Date()
        ) ?? Date()
        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeSource)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? defaultReminderHour,
            minute: timeComponents.minute ?? defaultReminderMinute,
            second: 0,
            of: dueDate
        ) ?? dueDate
    }
}
