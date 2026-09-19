import SwiftUI

/// Family-standard avatar with a four-tier fallback: photo → SF Symbol → initials → placeholder.
struct UserAvatarView: View {
    var avatarData: Data? = nil
    var symbolName: String = ""
    let name: String
    let size: CGFloat

    private var initials: String {
        let parts = name.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Group {
            if let data = avatarData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
            } else if !symbolName.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.28)
                        .fill(FamilyUI.panelMutedBackground)
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.28)
                                .stroke(FamilyUI.panelBorder, lineWidth: 1)
                        )
                    Image(systemName: symbolName)
                        .font(.system(size: size * 0.48, weight: .semibold))
                        .foregroundStyle(FamilyUI.accent)
                }
            } else if !name.isEmpty {
                RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                    .fill(FamilyUI.ink)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(FamilyTypography.fixed(size * 0.35, .bold))
                            .foregroundColor(FamilyUI.paper)
                    )
            } else {
                RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                    .fill(FamilyUI.panelMutedBackground)
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                            .stroke(FamilyUI.panelBorder, lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.4))
                            .foregroundColor(FamilyUI.subtleText)
                    )
            }
        }
        .accessibilityLabel(name.isEmpty ? "用户头像" : "\(name) 的头像")
    }
}
