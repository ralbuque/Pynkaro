import Foundation
import AVFoundation

/// Converte texto em fala via API da ElevenLabs (voz neural, muito natural).
/// Em caso de falha na API, usa a voz do sistema como fallback.
final class ElevenLabsSpeaker: NSObject, Speaking, AVAudioPlayerDelegate {

    var onMouthLevel: ((Int) -> Void)?

    private let apiKey: String
    private let voiceId: String
    private let model: String

    /// Fallback local; lazy para só inicializar (e imprimir) se for necessário.
    private lazy var fallback = Speaker()
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var meterTimer: Timer?

    init(apiKey: String) {
        let env = ProcessInfo.processInfo.environment
        self.apiKey = apiKey
        // "Lutz - Chuckling, Giggly and Cheerful" (Voice Library; é preciso
        // adicioná-la em My Voices na sua conta ElevenLabs antes de usar via API).
        // Alternativas do catálogo padrão (funcionam sem adicionar):
        // Daniel (onwK4e9ZLuTAKqWW03F9), George (JBFqnCBsd6RMkjVDRZzb),
        // Brian (nPczCjzI2devNBz1zQrb), Chris (iP95p4xoKVk53GoZ742B).
        // Lutz (9yzdeviXkFddZ4Oz8Mok)
         
        self.voiceId = env["ELEVENLABS_VOICE_ID"] ?? "f016iUUEKqhX0trYHH6Q"
        self.model = env["ELEVENLABS_MODEL"] ?? "eleven_multilingual_v2"
        super.init()
        print("🗣️ Voz: ElevenLabs (modelo \(model), voice_id \(voiceId))")
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion

        var req = URLRequest(
            url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)?output_format=mp3_44100_128")!
        )
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "text": text,
            "model_id": model
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard error == nil, status == 200, let data, !data.isEmpty else {
                    if let error {
                        print("⚠️ ElevenLabs: \(error.localizedDescription)")
                    } else if let data, let detail = String(data: data, encoding: .utf8) {
                        print("⚠️ ElevenLabs (HTTP \(status)): \(detail.prefix(200))")
                    } else {
                        print("⚠️ ElevenLabs: HTTP \(status)")
                    }
                    self.fallbackSpeak(text)
                    return
                }
                do {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.isMeteringEnabled = true
                    self.player = player
                    player.play()
                    self.startMetering()
                } catch {
                    print("⚠️ Falha ao tocar o áudio: \(error.localizedDescription)")
                    self.fallbackSpeak(text)
                }
            }
        }.resume()
    }

    /// Mede o volume do áudio ~30x por segundo e converte em nível de boca.
    private func startMetering() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let player = self.player, player.isPlaying else { return }
            player.updateMeters()
            let db = player.averagePower(forChannel: 0) // -160 (silêncio) a 0 dB
            let level: Int
            if db > -18 {
                level = 2
            } else if db > -32 {
                level = 1
            } else {
                level = 0
            }
            self.onMouthLevel?(level)
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        onMouthLevel?(0)
    }

    private func fallbackSpeak(_ text: String) {
        print("   Usando a voz do sistema como fallback.")
        fallback.onMouthLevel = onMouthLevel
        let callback = completion
        completion = nil
        fallback.speak(text) { callback?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopMetering()
        self.player = nil
        let callback = completion
        completion = nil
        callback?()
    }
}
