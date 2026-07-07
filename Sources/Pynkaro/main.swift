import Foundation
import AppKit

print("🤖 Pynkaro — assistente de voz local para macOS")

// Nomes de quem sugeriu as notícias do dia (usados quando alguém pergunta
// "quem sugeriu essas notícias?").
print("📰 Quem sugeriu as notícias de hoje? Digite dois nomes, um por linha:")
let newsSuggesters = [readLine(), readLine()]
    .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }
if newsSuggesters.isEmpty {
    print("   (nenhum nome informado — a pergunta sobre sugestões terá resposta genérica)")
} else {
    print("   Anotado: \(newsSuggesters.joined(separator: " e "))")
}

// NSApplication é necessário para exibir a janela do avatar.
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // sem ícone no Dock

let assistant = VoiceAssistant(newsSuggesters: newsSuggesters)
assistant.start()

// Loop de eventos do AppKit (também atende os timers e callbacks de áudio/fala).
app.run()
