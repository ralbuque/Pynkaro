import AppKit
import QuartzCore
import RiveRuntime

/// Janela flutuante, sem borda e transparente, que mostra o avatar no canto
/// inferior direito da tela enquanto o assistente está ativo (ouvindo,
/// pensando ou falando). Entrada: o avatar sobe de baixo para cima; saída: fade.
///
/// Dois modos de renderização, escolhidos na inicialização:
///  1. Rig Rive: se existir "avatar.riv" (raiz do projeto ou ~/.config/pynkaro/),
///     a boca é dirigida por um input numérico do state machine (0 a 4).
///  2. Sprites PNG: "avatar.png" + variações de boca (comportamento anterior).
final class AvatarWindow {

    private enum Renderer {
        case sprites
        case rive
    }

    private var window: NSWindow?
    private var renderer: Renderer = .sprites
    private var currentLevel = 0

    // MARK: Modo sprites
    private var imageView: NSImageView?
    /// Sprites por nível de boca: 0 = fechada (avatar.png),
    /// 1 = entreaberta (avatar_mid.png), 2 = aberta (avatar_open.png),
    /// 3 = arredondada o/u (avatar_round.png), 4 = f/v (avatar_fv.png).
    private var sprites: [Int: NSImage] = [:]
    private static let fallbackChains: [Int: [Int]] = [
        0: [0],
        1: [1, 2, 0],
        2: [2, 1, 0],
        3: [3, 1, 2, 0],
        4: [4, 1, 2, 0]
    ]

    // MARK: Modo Rive
    private var riveViewModel: RiveViewModel?
    /// Nome do input numérico do state machine que recebe o nível da boca (0-4).
    private static let riveInputName =
        ProcessInfo.processInfo.environment["PYNKARO_RIVE_INPUT"] ?? "mouth"

    // MARK: Animação de entrada
    /// Posições da view DENTRO da janela (a janela fica fixa; quem sobe é a view).
    private weak var animatedView: NSView?
    private var viewStartOrigin = NSPoint.zero
    private var viewFinalOrigin = NSPoint.zero

    // MARK: Posicionamento
    private let screenMargin: CGFloat = 24
    private var windowSize = NSSize.zero

    // MARK: Legenda (pergunta/resposta)
    private var captionBox: NSView?
    private var captionLabel: NSTextField?

    init() {
        // 1) Rig Rive, se avatar.riv existir.
        if let url = AvatarWindow.locateFile("avatar.riv") {
            if let viewModel = AvatarWindow.makeRiveViewModel(url: url) {
                renderer = .rive
                riveViewModel = viewModel
                let size = NSSize(width: 600, height: 600)
                let riveView = viewModel.createRiveView()
                riveView.frame = NSRect(origin: .zero, size: size)
                configureWindow(with: riveView, size: size)
                print("🎭 Avatar Rive carregado (avatar.riv), input \"\(AvatarWindow.riveInputName)\".")
                return
            }
            print("   Tentando o modo de sprites PNG...")
        }

        // 2) Sprites PNG.
        guard let image = AvatarWindow.loadImage(named: "avatar") else {
            print("⚠️ Nem avatar.riv nem avatar.png encontrados (raiz do projeto ou")
            print("   ~/.config/pynkaro/); o avatar não será exibido.")
            return
        }
        sprites[0] = image
        if let mid = AvatarWindow.loadImage(named: "avatar_mid") { sprites[1] = mid }
        if let open = AvatarWindow.loadImage(named: "avatar_open") { sprites[2] = open }
        if let round = AvatarWindow.loadImage(named: "avatar_round") { sprites[3] = round }
        if let fv = AvatarWindow.loadImage(named: "avatar_fv") { sprites[4] = fv }
        if sprites.count == 1 {
            print("💋 Para animar a boca, adicione avatar_mid.png (entreaberta) e")
            print("   avatar_open.png (aberta) junto do avatar.png. Opcionais:")
            print("   avatar_round.png (o/u) e avatar_fv.png (f/v) para mais realismo.")
        }

        // Redimensiona mantendo a proporção, com lado maior de 600 pt.
        let maxSide: CGFloat = 600
        let scale = min(maxSide / image.size.width, maxSide / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView = imageView
        configureWindow(with: imageView, size: size)
    }

    /// Monta a janela (fixa, na borda inferior direita) e o container com
    /// recorte dentro do qual a view do avatar sobe na entrada.
    private func configureWindow(with view: NSView, size: NSSize) {
        let margin = screenMargin
        let windowSize = NSSize(width: size.width, height: size.height + margin)
        self.windowSize = windowSize

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating                    // acima das janelas comuns
        window.ignoresMouseEvents = true            // cliques atravessam o avatar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Container com recorte: o que estiver fora dele fica invisível.
        let container = NSView(frame: NSRect(origin: .zero, size: windowSize))
        container.wantsLayer = true
        container.layer?.masksToBounds = true

        viewStartOrigin = NSPoint(x: 0, y: -size.height)
        viewFinalOrigin = NSPoint(x: 0, y: margin)
        view.setFrameOrigin(viewStartOrigin)
        container.addSubview(view)

        // Legenda: pílula translúcida sobreposta à base do avatar.
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        box.layer?.cornerRadius = 12
        box.alphaValue = 0
        let label = NSTextField(wrappingLabelWithString: "")
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.alignment = .center
        label.maximumNumberOfLines = 6
        box.addSubview(label)
        container.addSubview(box, positioned: .above, relativeTo: view)
        captionBox = box
        captionLabel = label

        window.contentView = container
        animatedView = view

        window.alphaValue = 0
        self.window = window
        positionWindow()
    }

    /// Posiciona a janela no canto inferior direito da tela escolhida no menu
    /// ("avatarScreenIndex" em UserDefaults; 0 = tela principal).
    private func positionWindow() {
        guard let window else { return }
        let screens = NSScreen.screens
        let index = UserDefaults.standard.integer(forKey: "avatarScreenIndex")
        guard let screen = (index >= 0 && index < screens.count)
            ? screens[index] : NSScreen.main else { return }
        let frame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: frame.maxX - windowSize.width - screenMargin,
                                      y: frame.minY))
    }

    // MARK: - Carregamento de arquivos

    private static func locateFile(_ name: String) -> URL? {
        let fm = FileManager.default
        var candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(name),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/pynkaro/\(name)")
        ]
        // Dentro do bundle .app, os recursos são embutidos pelo make_app.sh.
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(name))
        }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = locateFile("\(name).png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private static func makeRiveViewModel(url: URL) -> RiveViewModel? {
        do {
            let data = try Data(contentsOf: url)
            let riveFile = try RiveFile(byteArray: [UInt8](data), loadCdn: false)
            let model = RiveModel(riveFile: riveFile)
            let stateMachine = ProcessInfo.processInfo.environment["PYNKARO_RIVE_STATE_MACHINE"]
                ?? "State Machine 1"
            return RiveViewModel(model, stateMachineName: stateMachine)
        } catch {
            print("⚠️ Falha ao carregar avatar.riv: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Boca

    /// Ajusta a boca (0 fechada, 1 entreaberta, 2 aberta, 3 arredondada, 4 f/v).
    /// No modo Rive, envia o valor ao input numérico do state machine;
    /// no modo sprites, troca a imagem pelo sprite mais próximo disponível.
    func setMouth(_ level: Int) {
        DispatchQueue.main.async {
            let clamped = max(0, min(4, level))
            guard clamped != self.currentLevel else { return }
            self.currentLevel = clamped

            switch self.renderer {
            case .rive:
                self.riveViewModel?.setInput(AvatarWindow.riveInputName,
                                             value: Double(clamped))
            case .sprites:
                guard self.sprites.count > 1, let view = self.imageView else { return }
                let chain = AvatarWindow.fallbackChains[clamped] ?? [0]
                for index in chain {
                    if let sprite = self.sprites[index] {
                        view.image = sprite
                        break
                    }
                }
            }
        }
    }

    // MARK: - Legenda

    /// Mostra o texto como legenda na base do avatar; nil ou vazio esconde.
    /// O tamanho da pílula se ajusta ao texto (até 6 linhas).
    func setCaption(_ text: String?) {
        DispatchQueue.main.async {
            guard let box = self.captionBox, let label = self.captionLabel else { return }
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    box.animator().alphaValue = 0
                }
                return
            }

            label.stringValue = trimmed
            let maxWidth = self.windowSize.width - 64
            let textSize = label.cell?.cellSize(
                forBounds: NSRect(x: 0, y: 0, width: maxWidth, height: 800)
            ) ?? .zero
            let width = ceil(min(textSize.width, maxWidth))
            let height = ceil(textSize.height)
            label.frame = NSRect(x: 14, y: 9, width: width, height: height)
            box.frame = NSRect(x: (self.windowSize.width - (width + 28)) / 2,
                               y: 10,
                               width: width + 28,
                               height: height + 18)

            if box.alphaValue < 1 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    box.animator().alphaValue = 1
                }
            }
        }
    }

    // MARK: - Entrada e saída

    func show() {
        guard let window else { return }
        DispatchQueue.main.async {
            // Reposiciona na tela configurada (pode ter mudado no menu) e
            // recoloca a view embaixo (recortada) para subir até o final.
            self.positionWindow()
            self.animatedView?.setFrameOrigin(self.viewStartOrigin)
            window.alphaValue = 1
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animatedView?.animator().setFrameOrigin(self.viewFinalOrigin)
            }
        }
    }

    func hide() {
        guard let window else { return }
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.4
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.orderOut(nil)
                // Garante boca fechada, legenda limpa e posição inicial
                // na próxima aparição.
                self.setMouth(0)
                self.captionBox?.alphaValue = 0
                self.captionLabel?.stringValue = ""
                self.animatedView?.setFrameOrigin(self.viewStartOrigin)
            })
        }
    }
}
