import SwiftUI
import UIKit

struct AIConfigurationHeader: View {
    let status: AIConfigurationStatus?
    let isConfigured: Bool
    let errorMessage: String?
    let providerOptions: [AIProviderOption]
    let selectedProvider: AIProvider
    let selectedModel: String
    let onSelectProvider: (AIProvider) -> Void
    let onSelectModel: (String) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                .fill(FamilyUI.panelMutedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .frame(width: FamilyUI.iconBoxSize, height: FamilyUI.iconBoxSize)
                .overlay(
                    Image(systemName: isConfigured ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isConfigured ? FamilyUI.success : FamilyUI.warning)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("AI 配置")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                    SystemStatusBadge(text: isConfigured ? "已启用" : "待配置", tone: isConfigured ? .success : .warning)
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(errorMessage == nil ? .secondary : FamilyUI.danger)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Section("服务商") {
                    ForEach(providerOptions) { option in
                        Button {
                            onSelectProvider(option.provider)
                        } label: {
                            Label(
                                option.displayName,
                                systemImage: option.provider == selectedProvider ? "checkmark.circle.fill" : "circle"
                            )
                        }
                    }
                }
                if !selectedProviderModels.isEmpty {
                    Section("模型") {
                        ForEach(selectedProviderModels, id: \.self) { model in
                            Button {
                                onSelectModel(model)
                            } label: {
                                Label(
                                    model,
                                    systemImage: model == selectedModel ? "checkmark.circle.fill" : "circle"
                                )
                            }
                        }
                    }
                }
                Divider()
                Button("AI 设置", action: onOpenSettings)
            } label: {
                Label("切换", systemImage: "arrow.left.arrow.right")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(FamilyUI.panelMutedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, AppSpacing.pageHorizontal)
        .padding(.vertical, 12)
        .background(FamilyUI.pageBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FamilyUI.panelBorder)
                .frame(height: 1)
        }
    }

    private var detailText: String {
        if let errorMessage { return errorMessage }
        guard let status else { return "请先选择服务商并保存 API Key" }
        return "\(status.provider.displayName) · \(status.model) · \(status.maskedKey)"
    }

    private var selectedProviderModels: [String] {
        providerOptions.first { $0.provider == selectedProvider }?.models ?? []
    }
}

struct AIRequestProgressView: View {
    let elapsedSeconds: Int
    var hasImages: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer()

            SystemStatusBadge(text: statusBadge, tone: .neutral)
        }
        .padding(12)
        .background(FamilyUI.panelMutedBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
    }

    private var statusTitle: String {
        if hasImages {
            if elapsedSeconds < 20 { return "正在分析图片" }
            return "正在整理图片中的计划信息"
        }
        if elapsedSeconds < 12 { return "正在理解你的描述" }
        if elapsedSeconds < 30 { return "正在整理任务字段" }
        return "正在生成确认结果"
    }

    private var statusDetail: String {
        if hasImages {
            return "逐张提取任务、日期和备注线索"
        }
        if elapsedSeconds < 12 { return "识别标题、日期和优先级意图" }
        if elapsedSeconds < 30 { return "补全日期、提醒和优先级等字段" }
        return "结果较复杂，请继续等待一下"
    }

    private var statusBadge: String {
        if elapsedSeconds < 12 { return "理解" }
        if elapsedSeconds < 30 { return "整理" }
        return "生成"
    }
}

struct AIMessageBubble: View {
    let message: AIChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) }

            AITextMessageBubble(content: message.content, isUser: isUser)
                .frame(maxWidth: 280, alignment: isUser ? .trailing : .leading)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.content
                        HapticEngine.success()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

private struct AITextMessageBubble: View {
    let content: String
    let isUser: Bool

    private var hasImageAttachment: Bool {
        content.contains("[图片") || content.contains("[照片")
    }

    private var displayText: String {
        content
            .split(separator: "\n")
            .filter { !$0.hasPrefix("[图片") && !$0.hasPrefix("[照片") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !displayText.isEmpty {
                Text(displayText)
                    .font(.subheadline)
            }

            if hasImageAttachment {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.caption.weight(.semibold))
                    Text("图片附件")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isUser ? FamilyUI.paper.opacity(0.18) : FamilyUI.panelMutedBackground)
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.badgeCornerRadius))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isUser ? FamilyUI.ink : FamilyUI.panelBackground)
        .foregroundStyle(isUser ? FamilyUI.paper : FamilyUI.ink)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(isUser ? FamilyUI.ink.opacity(0.18) : FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}

struct NoteKeywordChips: View {
    let note: String
    let color: Color

    private var keywords: [String] {
        NoteKeywordExtractor.extract(from: note)
    }

    var body: some View {
        if !keywords.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(keywords, id: \.self) { keyword in
                        Text(keyword)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(color.opacity(0.14))
                            .foregroundStyle(color)
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.badgeCornerRadius))
                    }
                }
            }
            .accessibilityLabel("详情关键词")
        }
    }
}

private enum NoteKeywordExtractor {
    static func extract(from note: String) -> [String] {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let separators = ["→", "·", "/", "｜", "|", "，", ",", "、"]
        var normalized = trimmed
        for separator in separators {
            normalized = normalized.replacingOccurrences(of: separator, with: "\n")
        }
        for connector in [" 到 ", " 去 ", " 从 ", "在", "关于", "讨论", "整理"] {
            normalized = normalized.replacingOccurrences(of: connector, with: "\n")
        }

        let removable = CharacterSet(charactersIn: " ，,;；。、：:（）()[]【】")
            .union(.whitespacesAndNewlines)
        let parts = normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: removable) }
            .filter { !$0.isEmpty && $0.count <= 12 }

        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }
}

struct AIEmptyState: View {
    let isConfigured: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SystemPanel {
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .fill(FamilyUI.panelMutedBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                                .stroke(FamilyUI.panelBorder, lineWidth: 1)
                        )
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .black))
                                .foregroundStyle(FamilyUI.accent)
                        )

                    VStack(alignment: .leading, spacing: 6) {
                        SystemStatusBadge(text: isConfigured ? "AI 已就绪" : "待配置", tone: isConfigured ? .success : .warning)
                        Text("AI 计划助手")
                            .font(.title3.weight(.black))
                        Text("用自然语言整理待办、笔记和今日计划。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !isConfigured {
                AISetupNoticeCard(
                    title: "AI 尚未配置",
                    message: "配置服务商和 API Key 后，可以让 1Day 帮你整理任务草稿。核心任务和笔记功能无需 AI 也能使用。",
                    actionTitle: "前往设置配置 AI",
                    onOpenSettings: onOpenSettings
                )
            }

            VStack(spacing: 10) {
                AIFeatureCard(icon: "checklist", title: "自然语言建任务", desc: "例如：明天下午三点开会讨论 Q3 计划")
                AIFeatureCard(icon: "calendar.badge.clock", title: "计划整理", desc: "把零散输入整理成可确认的任务草稿")
                AIFeatureCard(icon: "note.text", title: "笔记辅助", desc: "后续可辅助整理会议纪要和想法")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct AISetupNoticeCard: View {
    let title: String
    let message: String
    let actionTitle: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(FamilyUI.warning)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenSettings) {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(FamilyUI.ink)
                    .foregroundStyle(FamilyUI.paper)
                    .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(FamilyUI.warning.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.warning.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}

private struct AIFeatureCard: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                .fill(FamilyUI.panelMutedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .frame(width: FamilyUI.iconBoxSize, height: FamilyUI.iconBoxSize)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FamilyUI.accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(FamilyUI.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}
