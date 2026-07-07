import Foundation

/// Chaves de API carregadas de um arquivo de configuração, para não irem
/// em commits (config.json está no .gitignore).
///
/// Ordem de busca do arquivo:
///   1. config.json no diretório atual (raiz do projeto)
///   2. ~/.config/pynkaro/config.json
///
/// Variáveis de ambiente (ANTHROPIC_API_KEY, ELEVENLABS_API_KEY) ainda
/// funcionam como fallback se o arquivo não existir ou o campo estiver vazio.
struct Config: Decodable {
    var anthropicApiKey: String?
    var elevenLabsApiKey: String?

    enum CodingKeys: String, CodingKey {
        case anthropicApiKey = "anthropic_api_key"
        case elevenLabsApiKey = "elevenlabs_api_key"
    }

    static let shared = load()

    static var anthropicKey: String? {
        resolve(shared.anthropicApiKey, envVar: "ANTHROPIC_API_KEY")
    }

    static var elevenLabsKey: String? {
        resolve(shared.elevenLabsApiKey, envVar: "ELEVENLABS_API_KEY")
    }

    private static func resolve(_ fileValue: String?, envVar: String) -> String? {
        if let fileValue, !fileValue.isEmpty {
            return fileValue
        }
        if let envValue = ProcessInfo.processInfo.environment[envVar], !envValue.isEmpty {
            return envValue
        }
        return nil
    }

    private static func load() -> Config {
        let fm = FileManager.default
        let candidates = [
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("config.json"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/pynkaro/config.json")
        ]
        for url in candidates where fm.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(Config.self, from: data)
                print("🔑 Configuração carregada de \(url.path)")
                return config
            } catch {
                print("⚠️ Não consegui ler \(url.path): \(error.localizedDescription)")
            }
        }
        return Config(anthropicApiKey: nil, elevenLabsApiKey: nil)
    }
}
