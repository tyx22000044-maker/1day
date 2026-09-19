import AVFoundation
import Observation
import Speech

/// 语音输入的相位。
///
/// 之前只有一个 `isRecording` 布尔：启动是异步的（权限弹窗、音频会话、引擎启动），
/// 在这段窗口里再点一次麦克风会再起一个任务，UI 显示「正在录音」而引擎其实没跑。
enum SpeechPhase: Equatable, Sendable {
    case idle
    case starting
    case recording
    case stopping

    var showsRecordingUI: Bool { self == .recording }
}

/// 驱动相位迁移的事件。非法组合一律保持原相位。
enum SpeechEvent: Equatable, Sendable {
    case tapped
    case engineStarted
    case engineStopped
    case startRejected
    case interrupted
}

enum SpeechPhaseMachine {
    static func next(_ phase: SpeechPhase, on event: SpeechEvent) -> SpeechPhase {
        switch (phase, event) {
        case (.idle, .tapped):
            return .starting
        // 启动还没就绪又被点：当作取消这次启动，而不是叠第二个任务。
        case (.starting, .tapped), (.starting, .startRejected), (.starting, .engineStopped):
            return .idle
        case (.starting, .engineStarted):
            return .recording
        case (.recording, .tapped), (.recording, .interrupted):
            return .stopping
        case (.stopping, .engineStopped), (.stopping, .startRejected):
            return .idle
        default:
            return phase
        }
    }
}

@Observable
@MainActor
final class SpeechInputController {
    private(set) var phase: SpeechPhase = .idle
    var errorMessage: String?

    /// 视图只关心「是不是在录」，从这里派生，避免两处状态各自为政。
    var isRecording: Bool { phase.showsRecordingUI }

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var startTask: Task<Void, Never>?
    /// 只在 init 里写、deinit 里读，不跨越并发边界，但要被非隔离的 deinit 访问。
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var tapInstalled = false

    init() {
        installSessionObservers()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func toggleRecording(onTranscript: @escaping (String) -> Void) {
        guard phase != .stopping else { return }
        if phase == .recording {
            stopRecording()
        } else if phase == .starting {
            // 第二次点击 = 放弃这次启动。
            startTask?.cancel()
            apply(.tapped)
        } else {
            apply(.tapped)
            startTask = Task { [weak self] in
                guard let self else { return }
                await self.startRecording(onTranscript: onTranscript)
            }
        }
    }

    func stopRecording() {
        guard phase == .recording || phase == .starting else { return }
        apply(.tapped)
        finishRecording(cancelTask: true)
        apply(.engineStopped)
    }

    private func apply(_ event: SpeechEvent) {
        phase = SpeechPhaseMachine.next(phase, on: event)
    }

    // MARK: - 系统对音频会话的干预

    private func installSessionObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.apply(.interrupted)
                self.finishRecording(cancelTask: true)
                self.apply(.engineStopped)
                self.errorMessage = "录音被系统打断，请再点一次麦克风。"
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                // 耳机/蓝牙切换后继续用旧输入通道会录到静音，直接停下更诚实。
                self.apply(.interrupted)
                self.finishRecording(cancelTask: true)
                self.apply(.engineStopped)
                self.errorMessage = "音频输出有变化，录音已停止，请再点一次麦克风。"
            }
        })
    }

    private func startRecording(onTranscript: @escaping (String) -> Void) async {
        errorMessage = nil

        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别暂不可用，请稍后再试。"
            apply(.startRejected)
            return
        }

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = "请在系统设置中允许语音识别权限。"
            apply(.startRejected)
            return
        }

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            errorMessage = "请在系统设置中允许麦克风权限。"
            apply(.startRejected)
            return
        }

        // 权限弹窗期间用户可能已经又点了一次，相位不再是 starting 就放弃。
        guard phase == .starting else {
            apply(.startRejected)
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        onTranscript(result.bestTranscription.formattedString)
                    }
                    if error != nil || result?.isFinal == true {
                        self.finishRecording(cancelTask: false)
                        self.apply(.engineStopped)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            apply(.engineStarted)
        } catch {
            finishRecording(cancelTask: true)
            apply(.startRejected)
            errorMessage = "语音输入启动失败：\(error.localizedDescription)"
        }
    }

    private func finishRecording(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission(completionHandler: { granted in
                continuation.resume(returning: granted)
            })
        }
    }
}
