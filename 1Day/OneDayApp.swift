import SwiftUI
import SwiftData

/// 全局唯一的 ModelContainer 持有者。
/// 通知代理（UIApplicationDelegate）不在 SwiftUI 环境里，拿不到 `.modelContainer` 注入的容器；
/// 之前它在通知回调里自行 `ModelContainer(for:)` 新建一个容器，与主界面容器并存于同一个
/// store 上，会造成写入竞争与数据丢失。改为统一从这里取同一个容器。
enum AppContainer {
    private static var stored: ModelContainer?

    static func register(_ container: ModelContainer) {
        stored = container
    }

    static var current: ModelContainer {
        if let stored { return stored }
        let container = OneDayModelContainer.make()
        stored = container
        return container
    }
}

enum OneDayModelContainer {
    static func make() -> ModelContainer {
        let schema = Schema([PlanItem.self, Note.self, UserSettings.self, AIChatMessage.self])
        do {
            let configuration = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            AppLogger.dataError("ModelContainer 创建失败，降级为内存容器以免启动崩溃: \(error.localizedDescription)")
            let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(for: schema, configurations: [inMemory]) {
                return fallback
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
        let container = OneDayModelContainer.make()
        AppContainer.register(container)
        self.modelContainer = container
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
