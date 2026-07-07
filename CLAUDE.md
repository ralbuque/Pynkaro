# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é

Pynkaro é um assistente de voz para macOS (protótipo de linha de comando, Swift Package). Fluxo: escuta contínua do microfone → wake word "Píncaro" → transcrição local (pt-BR) → pergunta à API da Anthropic (Claude, com busca na web) → resposta falada (ElevenLabs ou voz do sistema) com avatar animado na tela e lip sync por visemas.

## Comandos

```bash
swift build            # compila
swift run -c release   # roda (interativo: pede nomes de quem sugeriu as notícias, via stdin)
```

Não há testes nem linter configurados. O app só roda de fato em macOS (frameworks Speech/AVFoundation/AppKit) e requer permissões de Microfone e Reconhecimento de Fala concedidas ao terminal na primeira execução.

## Configuração em runtime

- `config.json` na raiz (gitignored; modelo em `config.example.json`) ou `~/.config/pynkaro/config.json`: chaves `anthropic_api_key` e `elevenlabs_api_key`. Carregado por `Config.swift`; variáveis de ambiente `ANTHROPIC_API_KEY`/`ELEVENLABS_API_KEY` são fallback.
- Env vars opcionais: `PYNKARO_MODEL`, `PYNKARO_WAKE_WORD`, `PYNKARO_WEB_SEARCH=0`, `PYNKARO_VOICE`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL`.
- Imagens carregadas em runtime da raiz do projeto (ou `~/.config/pynkaro/`): `avatar.png` (obrigatória para exibir o avatar) e sprites de boca opcionais `avatar_mid.png`, `avatar_open.png`, `avatar_round.png`, `avatar_fv.png`.

## Arquitetura (Sources/Pynkaro/)

O centro é a máquina de estados em `VoiceAssistant.swift`: `waitingWakeWord → capturingQuestion → thinking → speaking → waitingWakeWord`. Tudo converge para ela; os demais arquivos são satélites plugados por closures.

- `main.swift` — lê os nomes dos sugestores de notícias via stdin, configura `NSApplication` (`.accessory`, sem Dock) e roda o event loop do AppKit. O run loop do AppKit é necessário para a janela do avatar e para os `Timer`s.
- `SpeechRecognizer.swift` — AVAudioEngine + SFSpeechRecognizer pt-BR (on-device quando disponível). Emite transcrições parciais via `onPartial`. Detalhes críticos: sessões do SFSpeechRecognizer expiram em ~1 min, então `VoiceAssistant` reinicia a escuta a cada 45s (watchdog) e após erros; um contador `generation` invalida callbacks de sessões antigas; a wake word é injetada em `contextualStrings` para favorecer o reconhecimento.
- Detecção de fim de pergunta: por silêncio — timer rearmado a cada transcrição parcial *alterada* (1,8s com pergunta; 6s sem). A pergunta é o texto após a última ocorrência da wake word no transcript.
- `ClaudeClient.swift` — Messages API da Anthropic com histórico (máx. 20 mensagens) e ferramenta server-side `web_search` (max_uses 3). O system prompt é recomputado a cada chamada para injetar data/hora locais e inclui: persona bem-humorada, limite estrito de 1 frase, "modo opinião" (perguntas iniciadas com "Na sua opinião" → resposta cômica sem busca) e a resposta fixa sobre quem sugeriu as notícias. Respostas com busca vêm em múltiplos blocos: concatenar apenas os blocos `type == "text"`.
- `Speaker.swift` — define o protocolo `Speaking` (speak + callback `onMouthLevel`) e a implementação com AVSpeechSynthesizer (escolhe a melhor voz pt-BR masculina instalada). Boca animada por evento de palavra (`willSpeakRangeOfSpeechString`).
- `ElevenLabsSpeaker.swift` — TTS principal. Usa o endpoint `with-timestamps` (JSON com `audio_base64` + alignment por caractere) e constrói uma timeline de visemas (mapa caractere→nível de boca 0-4); um timer 60fps segue `player.currentTime`. Degradação em camadas: sem alignment → medição de amplitude (`averagePower`); falha da API → fallback para `Speaker` (voz do sistema).
- `AvatarWindow.swift` — janela borderless/transparente/flutuante no canto inferior direito, que ignora cliques. Entrada animada: a *janela fica fixa* e a NSImageView sobe dentro de um container com `masksToBounds` (animar frame de NSWindow via animator não respeita NSAnimationContext — não "consertar" voltando a animar a janela). `setMouth(_:)` troca sprites com cadeias de fallback por nível.
- A escuta é **pausada durante a fala** (para o assistente não se ouvir) e retomada no completion do `speak`.

## Convenções

- Idioma do código/comentários/mensagens de terminal: português brasileiro.
- Concorrência por GCD/closures (`DispatchQueue.main`) — não migrar para async/await sem pedido explícito.
- Um único alvo executável; sem dependências externas de pacote (rede via URLSession + JSONSerialization).
