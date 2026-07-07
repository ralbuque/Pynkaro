# Pynkaro — assistente de voz local para macOS

Protótipo de linha de comando. Fica ouvindo o microfone; ao ouvir **"Píncaro"**, captura a pergunta, transcreve localmente, envia para o Claude via API e fala a resposta.

## Privacidade

- Wake word e transcrição: **Speech framework da Apple, on-device** (nenhum áudio sai do Mac, se o idioma pt-BR estiver baixado — veja abaixo).
- Voz: **AVSpeechSynthesizer**, local.
- Único tráfego de rede: o **texto** da pergunta para `api.anthropic.com`.

## Requisitos

- macOS 13+ (Apple Silicon recomendado), Xcode ou Command Line Tools instalados.
- Chave de API da Anthropic (https://console.anthropic.com).
- Para transcrição 100% local: em **Ajustes do Sistema > Teclado > Ditado**, ative o ditado e baixe o idioma Português (Brasil). O app avisa no início se o modo on-device está ativo.

## Como rodar

1. Copie `config.example.json` para `config.json` e preencha as chaves (o arquivo está no `.gitignore`, não vai em commits):

```json
{
  "anthropic_api_key": "sk-ant-...",
  "elevenlabs_api_key": "..."
}
```

2. Compile e rode:

```bash
cd ~/Git/Pynkaro
swift run -c release
```

O `config.json` é procurado no diretório atual e depois em `~/.config/pynkaro/config.json`. As variáveis de ambiente `ANTHROPIC_API_KEY`/`ELEVENLABS_API_KEY` seguem funcionando como fallback para campos vazios.

Na primeira execução o macOS pedirá permissão de **Microfone** e **Reconhecimento de Fala** para o Terminal. Se os diálogos não aparecerem, habilite manualmente em Ajustes do Sistema > Privacidade e Segurança.

## Uso

1. Aguarde `👂 Aguardando "Píncaro"...`
2. Diga: **"Píncaro, que horas são em Tóquio?"** (ou diga só "Píncaro", aguarde o `🎤 Pode falar...` no terminal, e pergunte)
3. Ele transcreve, consulta o Claude e responde em voz alta.
4. O histórico da conversa é mantido durante a sessão.

## Configuração

Chaves de API: no `config.json` (ver "Como rodar"). Demais ajustes, por variável de ambiente:

| Variável | Padrão | Descrição |
|---|---|---|
| `PYNKARO_MODEL` | `claude-sonnet-5` | modelo da API Anthropic |
| `PYNKARO_VOICE` | melhor voz masculina pt-BR instalada | nome da voz do sistema (ex.: `Felipe (Aprimorada)`) |
| `ELEVENLABS_VOICE_ID` | `9yzdeviXkFddZ4Oz8Mok` (Lutz, masculina, risonha) | voz da ElevenLabs — a Lutz vem da Voice Library: adicione-a em My Voices na sua conta antes de usar |
| `ELEVENLABS_MODEL` | `eleven_multilingual_v2` | use `eleven_flash_v2_5` para menor latência |
| `PYNKARO_WEB_SEARCH` | `1` (ligada) | `0` desativa a busca na web |
| `PYNKARO_WAKE_WORD` | `pincaro` | wake word (sem precisar recompilar; acentos e maiúsculas são ignorados) |

### Avatar na tela

Salve a imagem do assistente como `avatar.png` na raiz do projeto (ou em `~/.config/pynkaro/avatar.png`) — PNG com fundo transparente fica melhor. O avatar aparece com fade no canto inferior direito quando a wake word é detectada e some quando a resposta termina. A janela flutua acima das outras, não rouba o foco e deixa os cliques passarem. Sem o arquivo, o app apenas avisa e segue sem avatar.

**Boca animada (lip sync por amplitude):** adicione mais dois PNGs na mesma pasta, idênticos ao avatar.png exceto pela boca — `avatar_mid.png` (entreaberta) e `avatar_open.png` (aberta), nas mesmas dimensões. Com a voz da ElevenLabs, o app mede o volume do áudio ~30x por segundo e troca os sprites conforme a amplitude; com a voz do sistema, abre e fecha a boca no ritmo das palavras. Sem os sprites extras, o avatar fica estático (sem erro). Dica: gere as variações com um editor de imagens por IA pedindo "mesma imagem, apenas boca entreaberta/aberta".

### Busca na web

O app habilita a ferramenta de busca da própria API da Anthropic (`web_search`): o Claude decide quando pesquisar e responde com dados atuais (notícias, cotações, clima etc.). A busca roda nos servidores da Anthropic — nada muda no app. Custo: US$ 10 por 1.000 buscas, além dos tokens; limitado a 3 buscas por pergunta (`max_uses`). Perguntas que exigem busca demoram alguns segundos a mais.

### Voz ElevenLabs

Com `ELEVENLABS_API_KEY` definida, a resposta é sintetizada na nuvem da ElevenLabs (voz neural, muito mais natural). Apenas o **texto** da resposta é enviado; o áudio do microfone continua nunca saindo do Mac. Se a API falhar, o app usa a voz do sistema como fallback.

Para escolher outra voz, veja as suas em https://elevenlabs.io/app/voice-lab ou liste via API:

```bash
curl -s https://api.elevenlabs.io/v1/voices -H "xi-api-key: $ELEVENLABS_API_KEY" | python3 -c "import json,sys; [print(v['voice_id'], '-', v['name']) for v in json.load(sys.stdin)['voices']]"
```

Ajustes no código: wake word em `VoiceAssistant.swift` (`wakeWord`), tempo de silêncio para encerrar a pergunta (`armSilenceTimer`, 1,8 s), prompt de sistema em `ClaudeClient.swift`.

## Arquitetura

```
main.swift            → entrada, run loop
VoiceAssistant.swift  → máquina de estados (aguardando → capturando → pensando → falando)
SpeechRecognizer.swift→ AVAudioEngine + SFSpeechRecognizer (pt-BR, on-device)
ClaudeClient.swift    → Messages API da Anthropic, com histórico
Speaker.swift         → AVSpeechSynthesizer (voz pt-BR)
```

Detalhes de implementação: a sessão de reconhecimento é reiniciada a cada 45 s (limite de ~1 min do SFSpeechRecognizer); o fim da pergunta é detectado por silêncio (sem nova transcrição por 1,8 s); a escuta é pausada enquanto o assistente fala, para não ouvir a si mesmo.

## Limitações do protótipo / próximos passos

- Roda no terminal; o próximo passo natural é um app de menu bar (SwiftUI) com ícone de estado.
- Wake word via transcrição contínua funciona, mas consome mais CPU que um detector dedicado (ex.: Porcupine).
- Sem streaming: a fala começa só quando a resposta completa chega. Streaming da API + fala por sentenças reduziria a latência.
- Não dá para interromper a resposta falada (adicionar "Pynkaro, para").
