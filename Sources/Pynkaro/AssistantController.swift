import Foundation
import Combine

/// Estado do assistente exposto para a interface (ícone e menu).
enum AssistantStatus: Equatable {
    case starting
    case waiting
    case listening
    case thinking
    case speaking
    case paused

    var symbolName: String {
        switch self {
        case .starting:  return "hourglass"
        case .waiting:   return "ear"
        case .listening: return "waveform"
        case .thinking:  return "ellipsis.bubble"
        case .speaking:  return "speaker.wave.2.fill"
        case .paused:    return "pause.circle"
        }
    }

    var label: String {
        switch self {
        case .starting:  return "Iniciando…"
        case .waiting:   return "Aguardando \"Píncaro\""
        case .listening: return "Ouvindo…"
        case .thinking:  return "Pensando…"
        case .speaking:  return "Falando…"
        case .paused:    return "Escuta pausada"
        }
    }
}

/// Ponte entre o VoiceAssistant (AppKit/GCD) e a interface SwiftUI.
final class AssistantController: ObservableObject {
    static let shared = AssistantController()

    @Published private(set) var status: AssistantStatus = .starting
    var isPaused: Bool { status == .paused }

    private let assistant = VoiceAssistant()

    private init() {
        assistant.onStatusChange = { [weak self] status in
            DispatchQueue.main.async { self?.status = status }
        }
    }

    func start() {
        assistant.start()
    }

    func togglePause() {
        if isPaused {
            assistant.resume()
        } else {
            assistant.pause()
        }
    }
}
