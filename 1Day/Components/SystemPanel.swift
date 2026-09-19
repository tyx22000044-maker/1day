import SwiftUI

struct SystemPageHeader: View {
    let eyebrow: String
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(FamilyTypography.sectionLabel)
                .tracking(1.2)
                .foregroundStyle(.secondary)

            Text(title)
                .font(FamilyTypography.pageTitle)
                .monospacedDigit()
                .foregroundStyle(.primary)

            if let detail {
                Text(detail)
                .font(FamilyTypography.text(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SystemPanel<Content: View>: View {
    let title: String?
    let detail: String?
    let content: Content

    init(title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.detail = nil
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(FamilyTypography.sectionLabel)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)

                    if let detail {
                        Text(detail)
                            .font(FamilyTypography.text(.subheadline))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FamilyUI.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}

struct SystemPanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(FamilyUI.divider)
            .frame(height: 1)
    }
}

struct FamilyAddButtonLabel: View {
    var body: some View {
        Image(systemName: "plus")
            .font(FamilyTypography.actionIcon)
            .frame(width: 34, height: 34)
            .background(Color.black)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
            .accessibilityLabel("新增")
    }
}

struct FamilyAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FamilyAddButtonLabel()
        }
        .buttonStyle(.plain)
    }
}

struct FamilyListIconBox: View {
    let systemName: String
    var color: Color = FamilyUI.accent
    var size: CGFloat = FamilyUI.iconBoxSize

    var body: some View {
        Rectangle()
            .fill(FamilyUI.panelMutedBackground)
            .overlay(
                Rectangle()
                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(FamilyTypography.icon)
                    .foregroundStyle(color)
            )
    }
}

struct FamilyTaskRow: View {
    let item: PlanItem
    let asOf: Date
    var showsScheduleDetails = false
    var language: AppLanguage = .system

    private var overdueLabel: String {
        item.isOverdue(asOf: asOf) ? AppSettingsLocalization.text("过期", "Overdue", language: language) : ""
    }

    var body: some View {
        HStack(spacing: AppSpacing.rowIconSpacing) {
            FamilyListIconBox(
                systemName: item.isCompleted ? "checkmark.circle.fill" : "circle",
                color: item.isCompleted ? FamilyUI.success : FamilyUI.accent
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(FamilyTypography.text(.subheadline, .semibold))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(FamilyTypography.text(.caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showsScheduleDetails {
                    HStack(spacing: 6) {
                        if let dueDate = item.dueDate {
                            Text(dueDate.shortDate(in: language.locale))
                                .font(FamilyTypography.text(.caption2))
                                .monospacedDigit()
                                .foregroundStyle(item.isOverdue(asOf: asOf) ? FamilyUI.danger : .secondary)
                        }
                        if item.reminderTime != nil {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(FamilyUI.warning)
                        }
                    }
                }
            }

            Spacer()

            if item.priority != .none {
                Image(systemName: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(item.priority.color)
            }

            if item.isOverdue(asOf: asOf) {
                SystemStatusBadge(text: overdueLabel, tone: .danger)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// 删除后的短时撤销条。Today / Plan / Notes 共用一套外观，
/// 保证「误删还能拿回来」这条能力在各列表里长得一样。
struct UndoDeleteToast: View {
    let label: String
    let title: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.slash.fill")
                .foregroundStyle(FamilyUI.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(FamilyTypography.sectionLabel)
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(FamilyTypography.text(.subheadline))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button(action: onUndo) {
                Text("撤销")
                    .font(FamilyTypography.text(.subheadline, .bold))
                    .foregroundStyle(FamilyUI.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FamilyUI.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label)：\(title)")
        .accessibilityHint("点按撤销可恢复")
    }
}

struct SystemStatusBadge: View {
    enum Tone {
        case neutral
        case accent
        case success
        case warning
        case danger

        var foreground: Color {
            switch self {
            case .neutral:
                return FamilyUI.subtleText
            case .accent:
                return FamilyUI.accent
            case .success:
                return FamilyUI.success
            case .warning:
                return FamilyUI.warning
            case .danger:
                return FamilyUI.danger
            }
        }
    }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text.uppercased())
            .font(FamilyTypography.badge)
            .tracking(0.6)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                Rectangle()
                    .stroke(tone == .neutral ? FamilyUI.panelBorder : tone.foreground, lineWidth: 1)
            )
    }
}
