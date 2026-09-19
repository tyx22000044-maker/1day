import SwiftUI
import Foundation
import UIKit
import CoreText
import AudioToolbox

// MARK: - Font Registration (Swiss Ledger — bundled Archivo grotesk)

/// Registers the bundled Archivo static instances so `Font.custom` / `UIFont(name:)`
/// can resolve them. Call once at app startup, before any appearance configuration.
enum FamilyFontRegistration {
    private static let fileNames = ["Archivo-400", "Archivo-500", "Archivo-600", "Archivo-700", "Archivo-800"]
    private(set) static var didRegister = false

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        for name in fileNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

// MARK: - App Typography

/// Swiss Ledger type scale. Body/label faces are Archivo (grotesk); SF Symbols keep
/// the system font. Weights map to the bundled static instances.
enum FamilyTypography {
    /// PostScript name of the bundled Archivo face nearest the requested weight.
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .regular, .ultraLight, .thin, .light: return "ArchivoRoman-Regular"
        case .medium:                              return "ArchivoRoman-Medium"
        case .semibold:                            return "ArchivoRoman-SemiBold"
        case .bold:                                return "ArchivoRoman-Bold"
        default:                                   return "ArchivoRoman-ExtraBold" // heavy, black
        }
    }

    static func text(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle:   size = 30
        case .title:        size = 26
        case .title2:       size = 20
        case .title3:       size = 17
        case .headline:     size = 16
        case .body:         size = 16
        case .callout:      size = 15
        case .subheadline:  size = 14
        case .footnote:     size = 12
        case .caption:      size = 11
        case .caption2:     size = 10
        @unknown default:   size = 16
        }
        return Font.custom(postScriptName(for: weight), size: size, relativeTo: style)
    }

    static func fixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.custom(postScriptName(for: weight), size: size)
    }

    /// 需要随 Dynamic Type 放大的展示型字号。
    ///
    /// 之前 hero / pageTitle 走 `fixed`，等于把大字号用户的标题钉死在 38/32pt，
    /// AX5 下标题被截断、按钮文字被压。`relativeTo:` 让系统按内容字号动态放大，
    /// 只有徽标、tab 标签这类微型排版才继续用 `fixed`。
    static let hero = Font.custom(postScriptName(for: .black), size: 38, relativeTo: .largeTitle)
    static let heroNumber = Font.custom(postScriptName(for: .black), size: 34, relativeTo: .largeTitle)
    static let pageTitle = Font.custom(postScriptName(for: .black), size: 32, relativeTo: .title)
    static let sectionLabel = Font.custom(postScriptName(for: .semibold), size: 11, relativeTo: .footnote)
    static let badge = fixed(9, .bold)
    static let button = text(.subheadline, .bold)

    // SF Symbols faces — must stay on the system font.
    static let icon = Font.system(size: 14, weight: .semibold)
    static let actionIcon = Font.system(.caption, weight: .black)
}

enum AppTypography {
    static func configureGlobalAppearance() {
        let inlineTitle = archivoUIFont(textStyle: .headline, weight: .semibold)
        let largeTitle = archivoUIFont(textStyle: .largeTitle, weight: .bold)
        let tabLabel = archivoUIFont(textStyle: .caption1, weight: .medium)

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

    private static func archivoUIFont(textStyle: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        let font = UIFont(name: FamilyTypography.postScriptName(for: Font.Weight(weight)), size: size)
        return font ?? UIFont.preferredFont(forTextStyle: textStyle)
    }
}

private extension Font.Weight {
    init(_ weight: UIFont.Weight) {
        switch weight {
        case .ultraLight: self = .ultraLight
        case .thin:       self = .thin
        case .light:      self = .light
        case .regular:    self = .regular
        case .medium:     self = .medium
        case .semibold:   self = .semibold
        case .bold:       self = .bold
        case .heavy:      self = .heavy
        default:          self = .black
        }
    }
}

private struct AppTypographyModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(FamilyTypography.text(.body))
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
                        RoundedRectangle(cornerRadius: 1)
                            .fill(configuration.isOn ? FamilyUI.onAccent : FamilyUI.subtleText)
                            .frame(width: 20, height: 20)
                            .padding(5)
                    }
            }
        }
        .buttonStyle(.plain)
        // 自绘的方块在 VoiceOver 里只是一个普通按钮，听不到「打开/关闭」。
        // 用原生 Toggle 承接无障碍语义，视觉仍是 Swiss Ledger 的方块，
        // 状态、转子操作和开关语义都交回系统。
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
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

/// 触觉类型作为值暴露，方便「哪个结果该给哪种反馈」被单测断言。
enum HapticFeedback: Equatable, Sendable {
    case tap
    case success
    case warning
}

enum HapticEngine {
    static func play(_ feedback: HapticFeedback) {
        switch feedback {
        case .tap: tap()
        case .success: success()
        case .warning: warning()
        }
    }

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

// MARK: - Family UI — Swiss Ledger

/// Shared visual language tokens for the "Swiss Ledger" direction: cold paper,
/// grid-first hairlines, a single accent, no shadows. Neutral surfaces follow the
/// family-wide Swiss Ledger spec; `accent` is the shared print red.
enum FamilyUI {
    static let pageBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.043, blue: 0.039, alpha: 1)   // #0B0B0A near-black paper
            : UIColor(red: 0.980, green: 0.980, blue: 0.969, alpha: 1)   // #FAFAF7 cold paper
    })
    static let panelBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.086, green: 0.086, blue: 0.078, alpha: 1)   // #161614 dark panel
            : UIColor.white                                              // #FFFFFF panel on paper
    })
    static let panelMutedBackground = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.122, green: 0.122, blue: 0.110, alpha: 1)   // #1F1F1C dark muted
            : UIColor(red: 0.949, green: 0.949, blue: 0.937, alpha: 1)   // #F2F2EF muted
    })
    static let panelBorder = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.14)
            : UIColor(red: 0.043, green: 0.043, blue: 0.039, alpha: 0.14) // rgba(11,11,10,0.14)
    })
    static let divider = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.10)
            : UIColor(red: 0.043, green: 0.043, blue: 0.039, alpha: 0.10) // rgba(11,11,10,0.10)
    })
    static let hairlineStrong = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.16)
            : UIColor(red: 0.043, green: 0.043, blue: 0.039, alpha: 0.16) // rgba(11,11,10,0.16) — tab bar rule
    })

    static let accent = Color(hex: "C4321F")        // print red — single signal color
    static let accentDeep = Color(hex: "8F2416")    // pressed/emphasis red (mockup hover value)
    static let ink = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.980, green: 0.980, blue: 0.969, alpha: 1)   // #FAFAF7 — inverted solid band
            : UIColor(red: 0.043, green: 0.043, blue: 0.039, alpha: 1)   // #0B0B0A — primary ink
    })
    /// 压在 accent / danger 实底上的前景色。两种外观模式下都要保持对比，
    /// 所以它跟着 ink/paper 走会失效 —— 深色下 ink 是近白、paper 是近黑。
    static let onAccent = Color(red: 0.980, green: 0.980, blue: 0.969)

    static let paper = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.043, green: 0.043, blue: 0.039, alpha: 1)   // text on inverted ink band
            : UIColor(red: 0.980, green: 0.980, blue: 0.969, alpha: 1)   // #FAFAF7
    })
    static let success = Color(hex: "2F7A63")       // muted green — label-only semantic
    static let warning = Color(hex: "8A6A1F")       // muted gold — label-only semantic
    static let danger = Color(hex: "C4321F")        // danger shares the accent red
    static let subtleText = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.612, green: 0.612, blue: 0.596, alpha: 1)   // #9C9B90 ink-faint
            : UIColor(red: 0.431, green: 0.431, blue: 0.408, alpha: 1)   // #6E6E68 ink-soft
    })

    static let panelCornerRadius: CGFloat = 2
    static let controlCornerRadius: CGFloat = 2
    static let badgeCornerRadius: CGFloat = 0
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
    /// 日期文案必须跟随界面语言：之前这几个 formatter 写死 `zh_CN`，
    /// 切到英文仍然是「7月1日 星期三」。同时删掉了四个从未被调用的
    /// formatter 属性（`Date.formatted(.dateTime…)` 才是真实的渲染路径）。
    func dayHeading(in locale: Locale) -> String {
        formatted(Date.FormatStyle().month().day().weekday(.wide).locale(locale))
    }

    func shortDate(in locale: Locale) -> String {
        formatted(Date.FormatStyle().month().day().locale(locale))
    }

    func weekdayName(in locale: Locale) -> String {
        formatted(Date.FormatStyle().weekday(.wide).locale(locale))
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

    /// 偏移 n 天。日历运算在极端时区设置下可能给 nil，退回按 24 小时推进，
    /// 排程入口不该因为一次日历换算失败就崩溃。
    func shiftedDays(_ days: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: self)
            ?? addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// 从 date 所在日期往后到下一个 target weekday（1 = 周日）要加几天；当天不算，至少 1 天。
    static func daysUntilNext(weekday target: Int, from date: Date, calendar: Calendar = .current) -> Int {
        let delta = (target - calendar.component(.weekday, from: date) + 7) % 7
        return delta == 0 ? 7 : delta
    }
}
