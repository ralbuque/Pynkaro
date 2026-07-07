import Foundation
import AVFoundation
import Speech

/// Máquina de estados do assistente:
/// aguardando wake word → capturando pergunta → pensando (Claude) → falando → volta ao início.
final class VoiceAssistant: NSObject {

    private enum State {
        case waitingWakeWord
        case capturingQuestion
        case thinking
        case speaking
    }

    /// Wake word (busca case/diacritic-insensitive, então "pincaro" casa
    /// "Píncaro", "PÍNCARO"...). Sobrescreva com PYNKARO_WAKE_WORD, sem recompilar.
    private let wakeWords: [String] = {
        if let custom = ProcessInfo.processInfo.environment["PYNKARO_WAKE_WORD"], !custom.isEmpty {
            return [custom.lowercased()]
        }
        return ["pincaro"]
    }()

    private var state: State = .waitingWakeWord
    private let recognizer = SpeechRecognizer()
    private let speaker: Speaking = {
        if let key = Config.elevenLabsKey {
            return ElevenLabsSpeaker(apiKey: key)
        }
        return Speaker()
    }()
    private let claude: ClaudeClient
    private lazy var avatar = AvatarWindow()

    init(newsSuggesters: [String] = []) {
        claude = ClaudeClient(newsSuggesters: newsSuggesters)
        super.init()
    }

    private var lastTranscript = ""
    private var question = ""
    private var silenceTimer: Timer?

    // MARK: - Inicialização e permissões

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard auth == .authorized else {
                print("❌ Permissão de reconhecimento de fala negada.")
                print("   Habilite em Ajustes do Sistema > Privacidade e Segurança > Reconhecimento de Fala.")
                exit(1)
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else {
                    print("❌ Permissão de microfone negada.")
                    print("   Habilite em Ajustes do Sistema > Privacidade e Segurança > Microfone.")
                    exit(1)
                }
                DispatchQueue.main.async { self?.setup() }
            }
        }
    }

    private func setup() {
        if recognizer.isOnDevice {
            print("🔒 Reconhecimento de fala 100% local (on-device).")
        } else {
            print("⚠️ Este Mac não suporta reconhecimento on-device em pt-BR;")
            print("   o áudio será processado nos servidores da Apple.")
            print("   (Baixe o idioma em Ajustes > Teclado > Ditado para ativar o modo local.)")
        }

        // Favorece a wake word na transcrição (palavra rara no dia a dia).
        recognizer.contextualStrings = wakeWords

        // Anima a boca do avatar conforme o volume/ritmo da fala.
        speaker.onMouthLevel = { [weak self] level in
            self?.avatar.setMouth(level)
        }

        recognizer.onPartial = { [weak self] text in
            DispatchQueue.main.async { self?.handlePartial(text) }
        }
        recognizer.onError = { [weak self] _ in
            DispatchQueue.main.async { self?.recoverListening() }
        }

        // O SFSpeechRecognizer limita sessões a ~1 minuto:
        // reinicia a escuta periodicamente enquanto aguarda a wake word.
        Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            guard let self, self.state == .waitingWakeWord else { return }
            self.restartListening()
        }

        restartListening()
        print("👂 Aguardando \"\(wakeWords[0])\"... (Ctrl+C para sair)")
    }

    // MARK: - Escuta

    private func restartListening() {
        lastTranscript = ""
        do {
            try recognizer.startListening()
        } catch {
            print("⚠️ Falha ao iniciar o áudio: \(error.localizedDescription). Tentando de novo em 2s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.restartListening()
            }
        }
    }

    /// Recupera a escuta após um erro do reconhecedor (ex.: timeout de sessão).
    private func recoverListening() {
        guard state == .waitingWakeWord || state == .capturingQuestion else { return }
        if state == .capturingQuestion { avatar.hide() }
        state = .waitingWakeWord
        silenceTimer?.invalidate()
        question = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.state == .waitingWakeWord else { return }
            self.restartListening()
        }
    }

    // MARK: - Transcrições

    private func handlePartial(_ text: String) {
        switch state {
        case .waitingWakeWord:
            if wakeWords.contains(where: {
                text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) {
                state = .capturingQuestion
                print("🎤 Pode falar...")
                avatar.show()
                updateQuestion(from: text)
            }
        case .capturingQuestion:
            updateQuestion(from: text)
        case .thinking, .speaking:
            break
        }
    }

    private func updateQuestion(from transcript: String) {
        // Só rearma o timer de silêncio quando o texto realmente mudou.
        guard transcript != lastTranscript else { return }
        lastTranscript = transcript

        // A pergunta é tudo que vem depois da última ocorrência da wake word
        // (considerando todas as variantes).
        let ranges = wakeWords.compactMap {
            transcript.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .backwards])
        }
        if let last = ranges.max(by: { $0.upperBound < $1.upperBound }) {
            question = String(transcript[last.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        }
        armSilenceTimer()
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        // Se ainda não há pergunta, dá mais tempo para o usuário formular.
        let interval: TimeInterval = question.isEmpty ? 6.0 : 1.8
        silenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.finishCapture()
        }
    }

    // MARK: - Pergunta → Claude → Fala

    private func finishCapture() {
        guard state == .capturingQuestion else { return }
        recognizer.stopListening()

        let q = question
        question = ""
        lastTranscript = ""

        guard !q.isEmpty else {
            print("😴 Nenhuma pergunta detectada. Voltando a aguardar.")
            avatar.hide()
            state = .waitingWakeWord
            restartListening()
            return
        }

        state = .thinking
        print("🧠 Pergunta: \(q)")
        claude.ask(q) { [weak self] result in
            DispatchQueue.main.async { self?.handleAnswer(result) }
        }
    }

    private func handleAnswer(_ result: Result<String, Error>) {
        let reply: String
        switch result {
        case .success(let text):
            reply = text
        case .failure(let error):
            print("⚠️ Erro na API: \(error.localizedDescription)")
            reply = "Desculpe, não consegui falar com a inteligência artificial agora."
        }

        print("💬 \(reply)")
        state = .speaking
        // A escuta fica parada enquanto fala — evita que o assistente ouça a si mesmo.
        speaker.speak(reply) { [weak self] in
            guard let self else { return }
            self.avatar.hide()
            self.state = .waitingWakeWord
            print("👂 Aguardando \"\(wakeWords[0])\"...")
            self.restartListening()
        }
    }
}
