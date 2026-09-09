import SwiftUI

final class FeedbackPreferences {
    static let shared = FeedbackPreferences()

    private enum Keys {
        static let hapticsEnabled = "feedback.hapticsEnabled"
        static let soundEffectsEnabled = "feedback.soundEffectsEnabled"
    }

    private(set) var isHapticsEnabled: Bool
    private(set) var isSoundEffectsEnabled: Bool

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.hapticsEnabled) == nil {
            defaults.set(true, forKey: Keys.hapticsEnabled)
        }
        if defaults.object(forKey: Keys.soundEffectsEnabled) == nil {
            defaults.set(true, forKey: Keys.soundEffectsEnabled)
        }
        isHapticsEnabled = defaults.bool(forKey: Keys.hapticsEnabled)
        isSoundEffectsEnabled = defaults.bool(forKey: Keys.soundEffectsEnabled)
    }

    func apply(settings: UserSettings) {
        setHapticsEnabled(settings.isHapticsEnabled)
        setSoundEffectsEnabled(settings.isSoundEffectsEnabled)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        isHapticsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.hapticsEnabled)
    }

    func setSoundEffectsEnabled(_ enabled: Bool) {
        isSoundEffectsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.soundEffectsEnabled)
    }
}

@Observable
final class AppViewModel {
    var selectedTab: AppTab = .today
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)
}
