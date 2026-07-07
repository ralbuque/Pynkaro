import Foundation

/// Cliente mínimo da Messages API da Anthropic, com histórico de conversa.
final class ClaudeClient {

    enum ClaudeError: LocalizedError {
        case badResponse(String)
        var errorDescription: String? {
            switch self {
            case .badResponse(let message): return message
            }
        }
    }

    private var history: [[String: String]] = []
    private let apiKey: String
    private let model: String
    private let webSearchEnabled: Bool

    /// Montado a cada pergunta para incluir a data/hora atual do Mac.
    private var systemPrompt: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy, HH:mm"
        let now = formatter.string(from: Date())
        let timezone = TimeZone.current.identifier

        return """
        Você é Pynkaro, um assistente de voz rodando no Mac do usuário. \
        Responda sempre em português do Brasil, adequado para ser lido em voz alta. \
        REGRA ESTRITA DE TAMANHO: responda em UMA única frase, com no máximo 40 \
        palavras. Nunca ultrapasse esse limite, mesmo que a pergunta peça detalhes; \
        nesse caso, resuma o essencial em uma frase. \
        Nunca use markdown, listas, símbolos ou emojis. \
        Seu tom é informal e coloquial, como um amigo brasileiro conversando: \
        pode usar gírias leves e soltar uma piada ou comentário espirituoso quando \
        couber. Mas sem exagerar: o humor é um tempero, não o prato principal. \
        Primeiro responda o que foi perguntado, com informação correta; em assuntos \
        sérios ou delicados, deixe o humor de lado. \
        MODO OPINIÃO: se a pergunta começar com "Na sua opinião" (ou variação \
        próxima), NÃO pesquise na web nem dê uma resposta fundamentada ou equilibrada: \
        dê uma opinião puramente cômica. Escolha um lado aleatoriamente, defenda-o com \
        exagero e convicção total, e se couber use um argumento absurdo ou maluco. \
        Continue respeitando o limite de uma frase e 60 palavras. \
        Data e hora atuais no Mac do usuário: \(now), fuso horário \(timezone). \
        Use essa informação para perguntas sobre data e hora; para a hora em outros \
        lugares, calcule a diferença de fuso a partir dela. \
        Você também tem acesso a busca na web: use-a quando a pergunta envolver \
        fatos atuais (notícias, cotações, clima, esportes). Não cite URLs em voz alta.
        """
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        apiKey = Config.anthropicKey ?? ""
        if apiKey.isEmpty {
            print("⚠️ Chave da Anthropic ausente: preencha anthropic_api_key no config.json.")
        }
        model = env["PYNKARO_MODEL"] ?? "claude-sonnet-5"
        webSearchEnabled = env["PYNKARO_WEB_SEARCH"] != "0"
        if webSearchEnabled {
            print("🌐 Busca na web habilitada (desative com PYNKARO_WEB_SEARCH=0).")
        }
    }

    func ask(_ question: String, completion: @escaping (Result<String, Error>) -> Void) {
        history.append(["role": "user", "content": question])
        // Limita o histórico para controlar custo/latência.
        if history.count > 20 {
            history.removeFirst(history.count - 20)
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "system": systemPrompt,
            "messages": history
        ]
        if webSearchEnabled {
            // Ferramenta executada nos servidores da Anthropic: o Claude decide
            // quando pesquisar. max_uses limita o custo (US$ 10 / 1000 buscas).
            body["tools"] = [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 3
                ] as [String: Any]
            ]
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(ClaudeError.badResponse("Resposta inválida da API.")))
                return
            }
            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                completion(.failure(ClaudeError.badResponse(message)))
                return
            }
            // Com busca na web, a resposta pode ter vários blocos (texto,
            // chamadas de busca, resultados): concatena só os blocos de texto.
            guard let content = json["content"] as? [[String: Any]] else {
                completion(.failure(ClaudeError.badResponse("Formato inesperado na resposta da API.")))
                return
            }
            let text = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                completion(.failure(ClaudeError.badResponse("A API não retornou texto.")))
                return
            }
            self?.history.append(["role": "assistant", "content": text])
            completion(.success(text))
        }.resume()
    }
}
