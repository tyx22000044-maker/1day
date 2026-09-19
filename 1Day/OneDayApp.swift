import SwiftUI
import SwiftData

/// SwiftData 容器的落盘状态。
///
/// 内存容器只用于「让 App 仍可操作并把数据导出去」，绝不能对用户伪装成已保存：
/// 之前降级是静默的，用户会以为任务已写入，重启后本次修改全部消失。
enum ModelContainerHealth: Equatable {
    case persisted
    case inMemoryOnly(reason: String)

    var isPersistingUserData: Bool {
        if case .persisted = self { return true }
        return false
    }
}

/// 全局唯一的 ModelContainer 持有者。
/// 通知代理（UIApplicationDelegate）不在 SwiftUI 环境里，拿不到 `.modelContainer` 注入的容器；
/// 之前它在通知回调里自行 `ModelContainer(for:)` 新建一个容器，与主界面容器并存于同一个
/// store 上，会造成写入竞争与数据丢失。改为统一从这里取同一个容器，并记录它是否真的在落盘。
enum AppContainer {
    private static var stored: ModelContainer?

    private(set) static var health: ModelContainerHealth = .persisted

    static func register(_ container: ModelContainer, health: ModelContainerHealth) {
        stored = container
        self.health = health
    }

    static var isPersistingUserData: Bool { health.isPersistingUserData }

    static var current: ModelContainer {
        if let stored { return stored }
        let outcome = OneDayModelContainer.make()
        register(outcome.container, health: outcome.health)
        return outcome.container
    }
}

enum OneDayModelContainer {
    struct Outcome {
        let container: ModelContainer
        let health: ModelContainerHealth
    }

    /// 唯一的 @Model 注册表在 `AppSchema`；新增模型必须先去那里登记，否则不会被持久化。
    static var schema: Schema { AppSchema.current }

    static func make() -> Outcome {
        make(configuration: ModelConfiguration(schema: schema))
    }

    /// 传入不可写的 `ModelConfiguration` 时不会崩溃，而是返回内存容器 + `inMemoryOnly`，
    /// 由调用方（App 入口 / 单测）决定如何提示用户。
    static func make(configuration: ModelConfiguration) -> Outcome {
        let schema = Self.schema
        do {
            return Outcome(
                container: try ModelContainer(
                    for: schema,
                    migrationPlan: OneDayMigrationPlan.self,
                    configurations: [configuration]
                ),
                health: .persisted
            )
        } catch {
            AppLogger.dataError("持久化 ModelContainer 创建失败，降级为内存容器: \(error.localizedDescription)")
            let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: schema, configurations: [inMemory]) {
                return Outcome(
                    container: fallback,
                    health: .inMemoryOnly(reason: error.localizedDescription)
                )
            }
            fatalError("Unable to create ModelContainer: \(error.localizedDescription)")
        }
    }
}

@main
struct OneDayApp: App {
    @UIApplicationDelegateAdaptor(PlanNotificationDelegate.self) private var notificationDelegate
    @State private var showSplash = true
    private let modelContainer: ModelContainer

    init() {
        FamilyFontRegistration.registerIfNeeded()
        AppTypography.configureGlobalAppearance()
        NotificationService.configureCategories()
        let outcome = OneDayModelContainer.make()
        AppContainer.register(outcome.container, health: outcome.health)
        self.modelContainer = outcome.container
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .appTypography()

                if showSplash {
                    SplashView(appName: "1Day", iconName: "SplashAppIcon") {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            showSplash = false
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}
