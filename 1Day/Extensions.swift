import SwiftUI
import Foundation
import UIKit
import AudioToolbox

// MARK: - App Typography

enum FamilyTypography {
    static let hero = Font.system(size: 38, weight: .black, design: .rounded)
    static let pageTitle = Font.system(size: 32, weight: .black, design: .rounded)
    static let sectionLabel = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let icon = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let actionIcon = Font.system(.caption, design: .rounded, weight: .black)
    static let badge = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let button = Font.system(.subheadline, design: .rounded, weight: .black)
}

enum AppTypography {
    static func configureGlobalAppearance() {
        let inlineTitle = roundedUIFont(textStyle: .headline, weight: .semibold)
        let largeTitle = roundedUIFont(textStyle: .largeTitle, weight: .bold)
        let tabLabel = roundedUIFont(textStyle: .caption1, weight: .medium)

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithDefaultBackground()
        navigationAppearance.titleTextAttributes = [.font: inlineTitle]
        navigationAppearance.largeTitleTextAttributes = [.font: largeTitle]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        UITabBarItem.appearance().setTitleTextAttributes([.font: tabLabel], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabLabel], for: .selected)
    }

    private static func roundedUIFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        if let rounded = descriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: 0)
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

private struct AppTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.body, design: .rounded))
            .fontDesign(.rounded)
    }
}

extension View {
    func appTypography() -> some View {
        modifier(AppTypographyModifier())
    }

    func appSwitchStyle() -> some View {
        toggleStyle(AppSwitchStyle())
    }
}

struct AppSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            HapticEngine.tap()
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 12)
                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                    .fill(configuration.isOn ? FamilyUI.accent : FamilyUI.panelMutedBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                            .stroke(FamilyUI.panelBorder, lineWidth: 1)
                    }
                    .frame(width: 50, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(configuration.isOn ? Color.white : Color.secondary.opacity(0.55))
                            .frame(width: 20, height: 20)
                            .padding(5)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Haptic Engine

enum SoundEngine {
    private static let confirmationSound: SystemSoundID = 1104

    static func confirmation() {
        guard FeedbackPreferences.shared.isSoundEffectsEnabled else { return }
        AudioServicesPlaySystemSound(confirmationSound)
    }
}

enum HapticEngine {
    static func tap() {
        guard FeedbackPreferences.shared.isHapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        guard FeedbackPreferences.shared.isHapticsEnabled else {
            SoundEngine.confirmation()
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        SoundEngine.confirmation()
    }
    static func warning() {
        guard FeedbackPreferences.shared.isHapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - App Spacing

enum AppSpacing {
    static let pageHorizontal: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardPaddingLarge: CGFloat = 20
    static let sectionSpacing: CGFloat = 12
    static let formSpacing: CGFloat = 16
    static let itemSpacing: CGFloat = 8
    static let rowIconSpacing: CGFloat = 12
    static let pageBottom: CGFloat = 24
}

// MARK: - Family UI V2

/// Shared visual language tokens, ported from the 1App Family V2 system-panel
/// direction (see APP_FAMILY_CONTEXT.md). Neutral surfaces match the family
/// baseline; `accent` follows the shared 1App Family blue direction.
enum FamilyUI {
    static let pageBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.086, green: 0.082, blue: 0.075, alpha: 1)   // #161410 warm near-black
            : UIColor(red: 0.957, green: 0.945, blue: 0.922, alpha: 1)   // #f4f1eb warm parchment
    })
    static let panelBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.122, green: 0.114, blue: 0.102, alpha: 1)   // #1f1d1a dark warm surface
            : UIColor.white
    })
    static let panelMutedBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.165, green: 0.153, blue: 0.141, alpha: 1)   // #2a2724 dark muted
            : UIColor(red: 0.941, green: 0.929, blue: 0.906, alpha: 1)   // #f0ede7
    })
    static let panelBorder = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.14)
    })
    static let divider = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.10)
    })

    static let accent = Color(hex: "1e4ed8")
    static let accentDeep = Color(hex: "173a98")
    static let success = Color(hex: "2f7a63")
    static let warning = Color.orange
    static let danger = Color.red
    static let subtleText = Color(.systemGray)

    static let panelCornerRadius: CGFloat = 12
    static let controlCornerRadius: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 6
    static let iconBoxSize: CGFloat = 34
}

// MARK: - Dismiss Keyboard

extension View {
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapBridge())
    }
}

private struct KeyboardDismissTapBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            installTapRecognizer(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            installTapRecognizer(from: uiView, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func installTapRecognizer(from view: UIView, coordinator: Coordinator) {
        guard let window = view.window, coordinator.window !== window else { return }
        coordinator.window?.gestureRecognizers?
            .filter { $0.name == Coordinator.recognizerName }
            .forEach { coordinator.window?.removeGestureRecognizer($0) }

        let recognizer = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.dismissKeyboard))
        recognizer.name = Coordinator.recognizerName
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = coordinator
        window.addGestureRecognizer(recognizer)
        coordinator.window = window
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        static let recognizerName = "OneDayDismissKeyboardTapRecognizer"
        weak var window: UIWindow?

        @objc func dismissKeyboard() {
            window?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.isTextInputDescendant
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private extension UIView {
    var isTextInputDescendant: Bool {
        if self is UITextField || self is UITextView || self is UISearchTextField {
            return true
        }
        return superview?.isTextInputDescendant ?? false
    }
}

// MARK: - Color(hex:)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6:  (a,r,g,b) = (255,int>>16,int>>8 & 0xFF,int & 0xFF)
        case 8:  (a,r,g,b) = (int>>24,int>>16 & 0xFF,int>>8 & 0xFF,int & 0xFF)
        default: (a,r,g,b) = (255,0,0,0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Date

extension Date {
    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月 yyyy"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private static let sectionHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    var isoDateString: String {
        Self.isoFormatter.string(from: self)
    }

    var monthYearDisplay: String {
        Self.monthYearFormatter.string(from: self)
    }

    var dayDisplay: String {
        Self.dayFormatter.string(from: self)
    }

    var sectionHeaderDisplay: String {
        Self.sectionHeaderFormatter.string(from: self)
    }

    func isSameMonth(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .month)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, equalTo: other, toGranularity: .day)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }
}
