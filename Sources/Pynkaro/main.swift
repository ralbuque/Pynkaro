import Foundation

print("🤖 Pynkaro — assistente de voz local para macOS")

let assistant = VoiceAssistant()
assistant.start()

// Mantém o processo vivo para os callbacks de áudio/fala.
RunLoop.main.run()
