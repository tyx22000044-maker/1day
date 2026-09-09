import SwiftUI

/// Shared labeled input surface for settings and edit flows.
struct SystemTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String? = nil
    var keyboardType: UIKeyboardType = .default
    var lineLimit: ClosedRange<Int>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Group {
                if let lineLimit {
                    TextField(placeholder ?? label, text: $text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(placeholder ?? label, text: $text)
                }
            }
            .keyboardType(keyboardType)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(FamilyUI.panelMutedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
        }
    }
}
