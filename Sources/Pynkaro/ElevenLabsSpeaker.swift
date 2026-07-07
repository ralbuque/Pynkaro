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

    /// Timeline de visemas construída a partir dos timestamps da ElevenLabs.
    private struct MouthEvent {
        let time: TimeInterval
        let level: Int
    }
    private var mouthEvents: [MouthEvent] = []
    private var mouthEventIndex = 0

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

        // O endpoint with-timestamps retorna JSON com o áudio em base64 e o
        // instante de cada caractere — usado para sincronizar a boca (visemas).
        var req = URLRequest(
            url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/with-timestamps?output_format=mp3_44100_128")!
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
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let audioB64 = json["audio_base64"] as? String,
                      let audioData = Data(base64Encoded: audioB64) else {
                    print("⚠️ ElevenLabs: resposta sem áudio válido.")
                    self.fallbackSpeak(text)
                    return
                }

                // Prefere o alinhamento normalizado (números por extenso etc.).
                let alignment = (json["normalized_alignment"] as? [String: Any])
                    ?? (json["alignment"] as? [String: Any])
                if let alignment,
                   let chars = alignment["characters"] as? [String],
                   let starts = alignment["character_start_times_seconds"] as? [Double],
                   let ends = alignment["character_end_times_seconds"] as? [Double] {
                    self.mouthEvents = self.buildMouthEvents(characters: chars, starts: starts, ends: ends)
                } else {
                    self.mouthEvents = []
                }
                self.mouthEventIndex = 0

                do {
                    let player = try AVAudioPlayer(data: audioData)
                    player.delegate = self
                    player.isMeteringEnabled = true
                    self.player = player
                    player.play()
                    if self.mouthEvents.isEmpty {
                        self.startMetering()   // sem timestamps: cai na amplitude
                    } else {
                        self.startVisemeTimer()
                    }
                } catch {
                    print("⚠️ Falha ao tocar o áudio: \(error.localizedDescription)")
                    self.fallbackSpeak(text)
                }
            }
        }.resume()
    }

    // MARK: - Visemas por timestamps

    /// Mapeia um caractere para o nível de boca:
    /// 0 fechada (m/b/p e pausas), 1 entreaberta (e/i e consoantes),
    /// 2 aberta (a), 3 arredondada (o/u), 4 lábio-dental (f/v).
    /// Retorna nil para espaços/pontuação (mantém a boca anterior).
    private static func viseme(for character: String) -> Int? {
        let c = character
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .lowercased()
        guard c.count == 1, let scalar = c.unicodeScalars.first,
              CharacterSet.letters.contains(scalar) else { return nil }
        switch c {
        case "a": return 2
        case "e", "i", "y": return 1
        case "o", "u", "w": return 3
        case "m", "b", "p": return 0
        case "f", "v": return 4
        default: return 1
        }
    }

    /// Converte o alinhamento por caractere numa timeline enxuta de trocas
    /// de boca, fechando-a em pausas longas e ao final do áudio.
    private func buildMouthEvents(characters: [String],
                                  starts: [Double],
                                  ends: [Double]) -> [MouthEvent] {
        var events: [MouthEvent] = []
        var lastLevel = -1
        var lastEnd: Double = 0
        for (i, ch) in characters.enumerated() {
            guard i < starts.count, i < ends.count else { break }
            guard let level = ElevenLabsSpeaker.viseme(for: ch) else { continue }
            // Pausa longa desde o último som → boca fechada.
            if !events.isEmpty, starts[i] - lastEnd > 0.12, lastLevel != 0 {
                events.append(MouthEvent(time: lastEnd, level: 0))
                lastLevel = 0
            }
            if level != lastLevel {
                events.append(MouthEvent(time: starts[i], level: level))
                lastLevel = level
            }
            lastEnd = ends[i]
        }
        events.append(MouthEvent(time: lastEnd, level: 0))
        return events
    }

    /// Segue a timeline de visemas acompanhando o relógio do próprio player,
    /// o que mantém a sincronia mesmo se o áudio atrasar para começar.
    private func startVisemeTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            let now = player.currentTime
            while self.mouthEventIndex < self.mouthEvents.count,
                  self.mouthEvents[self.mouthEventIndex].time <= now {
                self.onMouthLevel?(self.mouthEvents[self.mouthEventIndex].level)
                self.mouthEventIndex += 1
            }
        }
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
        mouthEvents = []
        mouthEventIndex = 0
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
