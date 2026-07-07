import Foundation
import AppKit

print("🤖 Pynkaro — assistente de voz local para macOS")

// NSApplication é necessário para exibir a janela do avatar.
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // sem ícone no Dock

let assistant = VoiceAssistant()
assistant.start()

// Loop de eventos do AppKit (também atende os timers e callbacks de áudio/fala).
app.run()
