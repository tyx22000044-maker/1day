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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isEnabled ? FamilyUI.accent : Color(.systemGray4))
                .foregroundStyle(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(Color.black.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
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
                .font(.system(.subheadline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.itemSpacing)
        }
        .buttonStyle(.bordered)
    }
}
