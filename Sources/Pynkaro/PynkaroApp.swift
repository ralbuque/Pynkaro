import SwiftUI
import AppKit
import Combine

/// App de menu bar. A UI do status item é feita com NSStatusItem (AppKit),
/// mais confiável que o MenuBarExtra do SwiftUI no macOS 13.
@main
struct PynkaroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Cena mínima exigida pelo ciclo de vida SwiftUI; a interface real
        // é o NSStatusItem criado no AppDelegate.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var statusLabelItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var screenMenuItems: [NSMenuItem] = []
    private var suggestersWindow: NSWindow?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sem ícone no Dock; o app vive na menu bar.
        NSApp.setActivationPolicy(.accessory)
        print("🤖 Pynkaro — assistente de voz local para macOS")

        buildStatusItem()

        // Ícone e rótulos acompanham o estado do assistente.
        cancellable = AssistantController.shared.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.statusItem?.button?.image = NSImage(
                    systemSymbolName: status.symbolName,
                    accessibilityDescription: status.label
                )
                self.statusLabelItem.title = status.label
                self.pauseItem.title = (status == .paused) ? "Retomar escuta" : "Pausar escuta"
            }

        AssistantController.shared.start()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: AssistantStatus.starting.symbolName,
            accessibilityDescription: "Pynkaro"
        )

        let menu = NSMenu()
        menu.autoenablesItems = false

        statusLabelItem = NSMenuItem(title: AssistantStatus.starting.label,
                                     action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())

        pauseItem = NSMenuItem(title: "Pausar escuta",
                               action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let suggestersItem = NSMenuItem(title: "Sugestores de notícias…",
                                        action: #selector(openSuggesters), keyEquivalent: "")
        suggestersItem.target = self
        menu.addItem(suggestersItem)

        // Em qual monitor o avatar aparece.
        let screenMenu = NSMenu()
        screenMenu.autoenablesItems = false
        screenMenuItems = NSScreen.screens.enumerated().map { index, screen in
            let item = NSMenuItem(title: screen.localizedName,
                                  action: #selector(selectScreen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            screenMenu.addItem(item)
            return item
        }
        let screenItem = NSMenuItem(title: "Tela do avatar", action: nil, keyEquivalent: "")
        menu.addItem(screenItem)
        menu.setSubmenu(screenMenu, for: screenItem)
        updateScreenChecks()

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Sair do Pynkaro",
                                  action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePause() {
        AssistantController.shared.togglePause()
    }

    @objc private func selectScreen(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "avatarScreenIndex")
        updateScreenChecks()
    }

    private func updateScreenChecks() {
        let selected = UserDefaults.standard.integer(forKey: "avatarScreenIndex")
        for item in screenMenuItems {
            item.state = (item.tag == selected) ? .on : .off
        }
    }

    @objc private func openSuggesters() {
        if suggestersWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SuggestersView()))
            window.title = "Sugestores de notícias"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            suggestersWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        suggestersWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Janela dos sugestores de notícias

/// Substitui a antiga entrada via stdin: os nomes ficam em UserDefaults
/// e o ClaudeClient os lê a cada pergunta.
struct SuggestersView: View {
    @AppStorage("newsSuggester1") private var name1 = ""
    @AppStorage("newsSuggester2") private var name2 = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quem sugeriu as notícias de hoje?")
                .font(.headline)
            TextField("Primeiro nome", text: $name1)
            TextField("Segundo nome", text: $name2)
            Text("Usados quando alguém pergunta \"quem sugeriu essas notícias?\". As mudanças valem já na próxima pergunta.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 340)
    }
}
