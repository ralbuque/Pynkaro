import AppKit
import QuartzCore

/// Janela flutuante, sem borda e transparente, que mostra o avatar no canto
/// inferior direito da tela enquanto o assistente está ativo (ouvindo,
/// pensando ou falando). Entrada: o avatar sobe de baixo para cima; saída: fade.
///
/// A imagem é carregada de "avatar.png" no diretório atual (raiz do projeto)
/// ou de ~/.config/pynkaro/avatar.png. PNG com fundo transparente fica melhor.
final class AvatarWindow {

    private var window: NSWindow?
    private var imageView: NSImageView?
    /// Sprites por nível de boca: 0 = fechada (avatar.png),
    /// 1 = entreaberta (avatar_mid.png), 2 = aberta (avatar_open.png),
    /// 3 = arredondada o/u (avatar_round.png), 4 = f/v (avatar_fv.png).
    /// Os níveis 3 e 4 são opcionais; sem eles, caem no sprite mais próximo.
    private var sprites: [Int: NSImage] = [:]
    private var currentLevel = 0
    private static let fallbackChains: [Int: [Int]] = [
        0: [0],
        1: [1, 2, 0],
        2: [2, 1, 0],
        3: [3, 1, 2, 0],
        4: [4, 1, 2, 0]
    ]

    /// Posições da imagem DENTRO da janela (a janela fica fixa; quem sobe é a view).
    private var viewStartOrigin = NSPoint.zero  // escondida abaixo, recortada
    private var viewFinalOrigin = NSPoint.zero  // posição visível

    init() {
        guard let image = AvatarWindow.loadImage(named: "avatar") else {
            print("⚠️ avatar.png não encontrado (raiz do projeto ou ~/.config/pynkaro/);")
            print("   o avatar não será exibido.")
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

        // A janela é um pouco mais alta que a imagem, ancorada na borda
        // inferior da tela; a imagem começa abaixo dela (recortada) e sobe.
        let margin: CGFloat = 24
        let windowSize = NSSize(width: size.width, height: size.height + margin)

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

        let imageView = NSImageView(frame: NSRect(origin: viewStartOrigin, size: size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(imageView)
        window.contentView = container
        self.imageView = imageView

        // Canto inferior direito da tela principal.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: frame.maxX - size.width - margin,
                                          y: frame.minY))
        }
        window.alphaValue = 0
        self.window = window
    }

    private static func loadImage(named name: String) -> NSImage? {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("\(name).png"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/pynkaro/\(name).png")
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }

    /// Troca o sprite da boca (0 fechada, 1 entreaberta, 2 aberta,
    /// 3 arredondada, 4 f/v). Sem os sprites extras, usa o mais próximo
    /// disponível; sem nenhum, é um no-op e o avatar fica estático.
    func setMouth(_ level: Int) {
        DispatchQueue.main.async {
            guard self.sprites.count > 1, let view = self.imageView else { return }
            let clamped = max(0, min(4, level))
            guard clamped != self.currentLevel else { return }
            self.currentLevel = clamped
            let chain = AvatarWindow.fallbackChains[clamped] ?? [0]
            for index in chain {
                if let sprite = self.sprites[index] {
                    view.image = sprite
                    break
                }
            }
        }
    }

    func show() {
        guard let window else { return }
        DispatchQueue.main.async {
            // Reposiciona a imagem embaixo (recortada) e sobe até a posição final.
            self.imageView?.setFrameOrigin(self.viewStartOrigin)
            window.alphaValue = 1
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.imageView?.animator().setFrameOrigin(self.viewFinalOrigin)
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
                // Garante boca fechada e posição inicial na próxima aparição.
                self.currentLevel = 0
                if let base = self.sprites[0] {
                    self.imageView?.image = base
                }
                self.imageView?.setFrameOrigin(self.viewStartOrigin)
            })
        }
    }
}
