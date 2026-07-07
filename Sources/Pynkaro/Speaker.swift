import Foundation
import AVFoundation

/// Interface comum para os sintetizadores de voz (local ou nuvem).
protocol Speaking: AnyObject {
    func speak(_ text: String, completion: @escaping () -> Void)
}

/// Converte texto em fala com a voz pt-BR do sistema.
final class Speaker: NSObject, Speaking, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var completion: (() -> Void)?

    override init() {
        voice = Speaker.bestVoice()
        super.init()
        synthesizer.delegate = self
        if let voice {
            let quality: String
            switch voice.quality {
            case .premium: quality = "premium"
            case .enhanced: quality = "aprimorada"
            default: quality = "padrão"
            }
            print("🗣️ Voz: \(voice.name) (\(quality))")
            if voice.quality == .default {
                print("   Dica: baixe o Felipe (Aprimorada) em Ajustes > Acessibilidade >")
                print("   Conteúdo Falado > Voz do Sistema > Gerenciar Vozes, para uma voz muito mais natural.")
            }
        }
    }

    /// Escolhe a voz definida em PYNKARO_VOICE ou, senão, a voz pt-BR
    /// masculina de maior qualidade instalada (premium > aprimorada > padrão).
    /// Se não houver voz masculina, usa a melhor pt-BR disponível.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        if let name = ProcessInfo.processInfo.environment["PYNKARO_VOICE"] {
            if let v = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return v
            }
            print("⚠️ Voz \"\(name)\" não encontrada; usando a melhor pt-BR disponível.")
        }
        let ptVoices = all.filter { $0.language == "pt-BR" }
        let maleVoices = ptVoices.filter { $0.gender == .male }
        let pool = maleVoices.isEmpty ? ptVoices : maleVoices
        return pool.max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: "pt-BR")
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func finish() {
        let callback = completion
        completion = nil
        DispatchQueue.main.async { callback?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish()
    }
}
