import SwiftUI
import SwiftData

@main
struct OneDayApp: App {
    @UIApplicationDelegateAdaptor(PlanNotificationDelegate.self) private var notificationDelegate
    @State private var showSplash = true

    init() {
        FamilyFontRegistration.registerIfNeeded()
        AppTypography.configureGlobalAppearance()
        NotificationService.configureCategories()
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
        .modelContainer(for: [
            PlanItem.self,
            Note.self,
            UserSettings.self,
            AIChatMessage.self
        ])
    }
}
