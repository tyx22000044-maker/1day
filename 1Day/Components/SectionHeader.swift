import SwiftUI

struct SectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = ""

    var body: some View {
        HStack {
            Text(title)
                .font(FamilyTypography.text(.headline, .bold))
            Spacer()
            if let action, !actionLabel.isEmpty {
                Button {
                    HapticEngine.tap()
                    action()
                } label: {
                    Text(actionLabel)
                        .font(FamilyTypography.text(.subheadline))
                        .foregroundStyle(FamilyUI.accent)
                }
            }
        }
    }
}
