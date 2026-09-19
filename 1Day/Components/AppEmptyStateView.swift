import SwiftUI

struct AppEmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var buttonTitle: String? = nil
    var buttonAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Rectangle()
                .fill(FamilyUI.panelMutedBackground)
                .overlay(
                    Rectangle()
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .frame(width: 72, height: 72)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(FamilyUI.accent)
                )

            Text(title)
                .font(FamilyTypography.text(.headline, .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(FamilyTypography.text(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let buttonTitle, let buttonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                        .font(FamilyTypography.button)
                        .tracking(0.4)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(FamilyUI.accent)
                        .foregroundStyle(FamilyUI.onAccent)
                        .overlay(
                            Rectangle()
                                .stroke(FamilyUI.accentDeep, lineWidth: 1)
                        )
                        .clipShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 36)
        .background(FamilyUI.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}
