import Foundation
import AVFoundation
import Speech

/// Captura o microfone com AVAudioEngine e transcreve continuamente
/// com SFSpeechRecognizer (on-device quando disponível).
final class SpeechRecognizer {

    /// Chamado a cada transcrição parcial (texto acumulado da sessão atual).
    var onPartial: ((String) -> Void)?
    /// Chamado quando a sessão de reconhecimento termina com erro.
    var onError: ((Error) -> Void)?
    /// Palavras incomuns cujo reconhecimento deve ser favorecido (ex.: a wake word).
    var contextualStrings: [String] = []

    private let recognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Contador de geração: invalida callbacks de sessões antigas.
    private var generation = 0

    init() {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR")) else {
            fatalError("Reconhecimento de fala em pt-BR não está disponível neste Mac.")
        }
        recognizer = r
    }

    var isOnDevice: Bool {
        recognizer.supportsOnDeviceRecognition
    }

    func startListening() throws {
        stopListening()
        generation += 1
        let gen = generation

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition {
            // Garante privacidade: nada de áudio vai para servidores da Apple.
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, gen == self.generation else { return }
            if let result {
                self.onPartial?(result.bestTranscription.formattedString)
            }
            if let error {
                self.onError?(error)
            }
        }
    }

    func stopListening() {
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
