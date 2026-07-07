import Foundation
import AVFoundation

/// Converte texto em fala via API da ElevenLabs (voz neural, muito natural).
/// Em caso de falha na API, usa a voz do sistema como fallback.
final class ElevenLabsSpeaker: NSObject, Speaking, AVAudioPlayerDelegate {

    private let apiKey: String
    private let voiceId: String
    private let model: String

    /// Fallback local; lazy para só inicializar (e imprimir) se for necessário.
    private lazy var fallback = Speaker()
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

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
                    self.player = player
                    player.play()
                } catch {
                    print("⚠️ Falha ao tocar o áudio: \(error.localizedDescription)")
                    self.fallbackSpeak(text)
                }
            }
        }.resume()
    }

    private func fallbackSpeak(_ text: String) {
        print("   Usando a voz do sistema como fallback.")
        let callback = completion
        completion = nil
        fallback.speak(text) { callback?() }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        let callback = completion
        completion = nil
        callback?()
    }
}
