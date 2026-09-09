import SwiftUI

struct OnboardingView: View {
    @Bindable var settings: UserSettings

    @State private var currentStep = 0
    @State private var notificationStatusMessage: String?
    @State private var isRequestingNotificationPermission = false
    @State private var onboardingAPIKey = ""
    @State private var aiConfigurationMessage: String?

    private let totalSteps = 6
    private let avatarSymbols = [
        "person.crop.circle",
        "person.fill",
        "star.fill",
        "sparkles",
        "leaf.fill",
        "briefcase.fill"
    ]
    private let aiConfigurationService = LocalAIConfigurationService()

    private var canGoBack: Bool { currentStep > 0 }
    private var isLastStep: Bool { currentStep == totalSteps - 1 }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(
                currentStep: currentStep,
                totalSteps: totalSteps,
                canGoBack: canGoBack,
                onBack: goBack,
                onSkip: finish
            )

            ScrollView {
                VStack(spacing: 28) {
                    stepContent
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 12) {
                PrimaryButton(title: isLastStep ? "开始使用" : "继续") {
                    if isLastStep {
                        finish()
                    } else {
                        goForward()
                    }
                }

                if currentStep == 0 {
                    Button("稍后再设置") {
                        finish()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .background(FamilyUI.panelBackground)
        }
        .background(FamilyUI.pageBackground.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: currentStep)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            welcomeStep
        case 1:
            profileStep
        case 2:
            preferenceStep
        case 3:
            aiConfigStep
        case 4:
            reminderStep
        case 5:
            readyStep
        default:
            EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .fill(FamilyUI.panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .frame(width: 112, height: 112)
                .overlay {
                    Image("SplashAppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.top, 24)

            OnboardingStepHeader(
                title: "欢迎使用 1Day",
                subtitle: "把任务、提醒和笔记放在一个安静好用的地方。"
            )

            VStack(spacing: 12) {
                OnboardingFeatureRow(icon: "bolt.fill", text: "快速记录任务和想法")
                OnboardingFeatureRow(icon: "bell.fill", text: "按日期提醒重要事项")
                OnboardingFeatureRow(icon: "sparkles", text: "用 AI 整理自然语言任务")
                OnboardingFeatureRow(icon: "note.text", text: "保留过程中的笔记")
            }
        }
    }

    private var profileStep: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                title: "先认识一下你",
                subtitle: "昵称和头像只保存在本机，也可以稍后在设置里修改。"
            )

            UserAvatarView(
                avatarData: settings.avatarImageData,
                symbolName: settings.avatarSymbolName,
                name: settings.nickname,
                size: 92
            )

            TextField("你的名字", text: $settings.nickname)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(FamilyUI.panelMutedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                .textInputAutocapitalization(.words)
                .onChange(of: settings.nickname) { _, _ in touch() }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(avatarSymbols, id: \.self) { symbol in
                    Button {
                        settings.avatarSymbolName = symbol
                        settings.avatarImageData = nil
                        touch()
                        HapticEngine.success()
                    } label: {
                        Image(systemName: symbol)
                            .font(.title2)
                            .foregroundStyle(settings.avatarSymbolName == symbol ? Color.white : FamilyUI.accent)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity)
                            .background(settings.avatarSymbolName == symbol ? FamilyUI.accent : FamilyUI.panelMutedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var preferenceStep: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                title: "选择使用偏好",
                subtitle: "这里先把语言和外观定下来，进入应用后仍然可以随时改。"
            )

            SystemPanel(title: "偏好设置") {
                VStack(spacing: 16) {
                    Picker("语言", selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("外观", selection: appearanceBinding) {
                        ForEach(AppearanceMode.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var aiConfigStep: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                title: "AI 计划助手",
                subtitle: "用自然语言整理任务草稿。需要配置服务商和 API Key，这一步可以稍后在设置里完成。"
            )

            VStack(spacing: 12) {
                OnboardingFeatureRow(icon: "checklist", text: "一句话建任务：明天下午三点开会")
                OnboardingFeatureRow(icon: "calendar.badge.clock", text: "识别日期、优先级和备注")
                OnboardingFeatureRow(icon: "note.text", text: "后续支持笔记整理和计划建议")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("现在配置（可选）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("服务商", selection: aiProviderBinding) {
                    ForEach(aiConfigurationService.providerOptions) { option in
                        Text(option.displayName).tag(option.provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(FamilyUI.panelMutedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(FamilyUI.panelBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                TextField("模型 ID", text: $settings.selectedAIModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(FamilyUI.panelMutedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                            .stroke(FamilyUI.panelBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                SecureField("API Key（留空则稍后配置）", text: $onboardingAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(FamilyUI.panelMutedBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                            .stroke(FamilyUI.panelBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))

                if let aiConfigurationMessage {
                    Text(aiConfigurationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(FamilyUI.panelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
            .onAppear(perform: loadAIConfiguration)
            .onChange(of: settings.selectedAIProvider) { _, _ in
                onboardingAPIKey = (try? aiConfigurationService.readAPIKey(provider: settings.selectedAIProvider)) ?? ""
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(FamilyUI.accent)
                    Text("AI 功能完全可选")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                Text("不配置 AI 也能正常使用任务、提醒和笔记。API Key 保存在 iOS Keychain，不会进入备份文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(FamilyUI.panelMutedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))

            Text("点击「继续」可跳过，进入应用后在「设置 → AI 服务商」中随时配置。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var reminderStep: some View {
        VStack(spacing: 24) {
            OnboardingStepHeader(
                title: "设置默认提醒",
                subtitle: "创建带日期的任务时，会优先使用这个时间提醒你。"
            )

            DatePicker("默认提醒时间", selection: reminderDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()

            HStack(spacing: 10) {
                ForEach([8, 9, 10, 18], id: \.self) { hour in
                    OnboardingOptionButton(
                        title: String(format: "%02d:00", hour),
                        isSelected: settings.defaultReminderHour == hour && settings.defaultReminderMinute == 0
                    ) {
                        settings.defaultReminderHour = hour
                        settings.defaultReminderMinute = 0
                        NotificationService.syncDefaultReminderTime(hour: hour, minute: 0)
                        touch()
                        HapticEngine.success()
                    }
                }
            }

            Button {
                requestNotificationPermission()
            } label: {
                Label(
                    isRequestingNotificationPermission ? "正在请求权限" : "开启通知权限",
                    systemImage: "bell.badge"
                )
                .frame(maxWidth: .infinity)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(FamilyUI.panelMutedBackground)
            .overlay(
                RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                    .stroke(FamilyUI.panelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
            .buttonStyle(.plain)
            .disabled(isRequestingNotificationPermission)

            if let notificationStatusMessage {
                Text(notificationStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72, design: .rounded))
                .foregroundStyle(FamilyUI.success)
                .padding(.top, 24)

            OnboardingStepHeader(
                title: "一切就绪",
                subtitle: "你可以从「今天」开始，也可以直接去 AI 里用一句话创建任务。"
            )

            VStack(spacing: 12) {
                OnboardingSummaryRow(icon: "person.crop.circle", title: "昵称", value: settings.nickname.isEmpty ? "未设置" : settings.nickname)
                OnboardingSummaryRow(icon: "globe", title: "语言", value: settings.language.displayName)
                OnboardingSummaryRow(icon: "circle.lefthalf.filled", title: "外观", value: settings.appearance.displayName)
                OnboardingSummaryRow(icon: "bell.fill", title: "默认提醒", value: String(format: "%02d:%02d", settings.defaultReminderHour, settings.defaultReminderMinute))
            }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding {
            settings.language
        } set: { language in
            settings.language = language
            touch()
        }
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding {
            settings.appearance
        } set: { appearance in
            settings.appearance = appearance
            touch()
        }
    }

    private var aiProviderBinding: Binding<AIProvider> {
        Binding {
            settings.selectedAIProvider
        } set: { provider in
            settings.selectedAIProvider = provider
            if let option = aiConfigurationService.providerOptions.first(where: { $0.provider == provider }) {
                settings.selectedAIModel = option.defaultModel
            }
            settings.isAIConfigured = false
            touch()
        }
    }

    private var reminderDate: Binding<Date> {
        Binding {
            Calendar.current.date(
                bySettingHour: settings.defaultReminderHour,
                minute: settings.defaultReminderMinute,
                second: 0,
                of: Date()
            ) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.defaultReminderHour = components.hour ?? 9
            settings.defaultReminderMinute = components.minute ?? 0
            NotificationService.syncDefaultReminderTime(
                hour: settings.defaultReminderHour,
                minute: settings.defaultReminderMinute
            )
            touch()
        }
    }

    private func goForward() {
        if currentStep == 3 {
            saveAIConfiguration()
        }
        currentStep = min(currentStep + 1, totalSteps - 1)
    }

    private func goBack() {
        currentStep = max(currentStep - 1, 0)
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        touch()
        HapticEngine.success()
    }

    private func touch() {
        settings.updatedAt = Date()
    }

    private func loadAIConfiguration() {
        guard onboardingAPIKey.isEmpty else { return }
        onboardingAPIKey = (try? aiConfigurationService.readAPIKey(provider: settings.selectedAIProvider)) ?? ""
    }

    private func saveAIConfiguration() {
        do {
            if !onboardingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try aiConfigurationService.saveAPIKey(onboardingAPIKey, provider: settings.selectedAIProvider)
            }
            settings.isAIConfigured = try aiConfigurationService.validateLocalConfiguration(settings: settings)
            aiConfigurationMessage = settings.isAIConfigured ? "AI 配置已保存。" : "AI 配置未完成，可以稍后在设置中补充。"
            touch()
        } catch {
            settings.isAIConfigured = false
            aiConfigurationMessage = "AI 配置保存失败，可以稍后在设置中重试。"
        }
    }

    private func requestNotificationPermission() {
        isRequestingNotificationPermission = true
        notificationStatusMessage = nil

        Task {
            let granted = await NotificationService.requestAuthorization()
            await MainActor.run {
                isRequestingNotificationPermission = false
                notificationStatusMessage = granted ? "通知权限已开启" : "暂未开启通知权限，可以稍后在系统设置中打开。"
                HapticEngine.success()
            }
        }
    }
}

private struct OnboardingTopBar: View {
    let currentStep: Int
    let totalSteps: Int
    let canGoBack: Bool
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .opacity(canGoBack ? 1 : 0)
                .disabled(!canGoBack)

                Spacer()

                SystemStatusBadge(text: "STEP \(currentStep + 1) / \(totalSteps)", tone: .accent)

                Spacer()

                Button("跳过", action: onSkip)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(FamilyUI.panelBackground)
    }
}

private struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FamilyUI.panelMutedBackground)
                Capsule()
                    .fill(FamilyUI.accent)
                    .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps))
                    .animation(.easeInOut(duration: 0.22), value: currentStep)
            }
        }
        .frame(height: 4)
    }
}

private struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.black))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(FamilyUI.accent)
                .frame(width: 30, height: 30)
                .background(FamilyUI.accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FamilyUI.accent.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(text)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FamilyUI.panelMutedBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}

private struct OnboardingOptionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? FamilyUI.accent : FamilyUI.panelMutedBackground)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius)
                        .stroke(isSelected ? FamilyUI.accent : FamilyUI.panelBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: FamilyUI.controlCornerRadius))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingSummaryRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(FamilyUI.accent)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(FamilyUI.panelMutedBackground)
        .overlay(
            RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius)
                .stroke(FamilyUI.panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: FamilyUI.panelCornerRadius))
    }
}
