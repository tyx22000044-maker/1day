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
        do {
            return try await requestAuthorizationIfNeeded()
        } catch {
            AppLogger.dataError("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    static func scheduleTaskReminder(for item: PlanItem) {
        guard !item.isCompleted, let dueDate = item.dueDate else {
            cancelTaskReminder(for: item)
            return
        }

        let identifier = notificationIdentifier(for: item.id)
        let triggerDate = reminderDate(for: dueDate, reminderTime: item.reminderTime)

        guard triggerDate > Date() else {
            cancelTaskReminder(for: item)
            return
        }

        Task {
            do {
                let granted = try await requestAuthorizationIfNeeded()
                guard granted else {
                    AppLogger.warning("Notification permission not granted")
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = notificationBody(for: item, triggerDate: triggerDate)
                content.sound = .default
                content.categoryIdentifier = taskCategoryIdentifier
                content.userInfo = ["planItemId": item.id.uuidString]

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: triggerDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
                try await UNUserNotificationCenter.current().add(request)
                AppLogger.data("Scheduled task reminder: \(item.id)")
            } catch {
                AppLogger.dataError("Failed to schedule task reminder: \(error.localizedDescription)")
            }
        }
    }

    static func cancelTaskReminder(for item: PlanItem) {
        cancelTaskReminder(itemID: item.id)
    }

    static func cancelTaskReminder(itemID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: itemID)]
        )
        AppLogger.data("Cancelled task reminder: \(itemID)")
    }

    static func notificationIdentifier(for itemID: UUID) -> String {
        "plan-task-\(itemID.uuidString)"
    }

    private static func requestAuthorizationIfNeeded() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        @unknown default:
            return false
        }
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
