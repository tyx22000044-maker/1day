import SwiftUI

struct AppSettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var iconColor: Color = FamilyUI.accent
    var showsChevron: Bool = false
    var emphasizesValue: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(FamilyUI.panelMutedBackground)
                .overlay(
                    Rectangle()
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .frame(width: FamilyUI.iconBoxSize, height: FamilyUI.iconBoxSize)
                .overlay(
                    Image(systemName: icon)
                        .font(FamilyTypography.icon)
                        .foregroundStyle(iconColor)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FamilyTypography.text(.subheadline, .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(FamilyTypography.text(.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let value, !value.isEmpty {
                Text(value)
                    .font(FamilyTypography.text(.subheadline, emphasizesValue ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(emphasizesValue ? FamilyUI.accent : .secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(FamilyUI.subtleText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
