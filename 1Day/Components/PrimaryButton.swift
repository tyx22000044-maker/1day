import SwiftUI

struct PrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.tap()
            action()
        } label: {
            Text(title)
                .font(FamilyTypography.button)
                .tracking(0.4)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isEnabled ? FamilyUI.accent : Color(.systemGray4))
                .foregroundStyle(Color.white)
                .overlay(
                    Rectangle()
                        .stroke(isEnabled ? FamilyUI.accentDeep : FamilyUI.panelBorder, lineWidth: 1)
                )
                .clipShape(Rectangle())
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.tap()
            action()
        } label: {
            Text(title)
                .font(FamilyTypography.text(.subheadline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.itemSpacing)
        }
        .buttonStyle(.bordered)
    }
}
