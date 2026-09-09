import AVFoundation
import Observation
import Speech

@Observable
@MainActor
final class SpeechInputController {
    var isRecording = false
    var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func toggleRecording(onTranscript: @escaping (String) -> Void) {
        if isRecording {
            stopRecording()
        } else {
            Task { await startRecording(onTranscript: onTranscript) }
        }
    }

    func stopRecording() {
        finishRecording(cancelTask: true)
    }

    private func startRecording(onTranscript: @escaping (String) -> Void) async {
        errorMessage = nil

        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别暂不可用，请稍后再试。"
            return
        }

        let speechStatus = await requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = "请在系统设置中允许语音识别权限。"
            return
        }

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            errorMessage = "请在系统设置中允许麦克风权限。"
            return
        }

        do {
            stopRecording()

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

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        onTranscript(result.bestTranscription.formattedString)
                    }
                    if error != nil || result?.isFinal == true {
                        self.finishRecording(cancelTask: false)
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            stopRecording()
            errorMessage = "语音输入启动失败：\(error.localizedDescription)"
        }
    }

    private func finishRecording(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
        } else {
            recognitionTask?.finish()
        }
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
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
