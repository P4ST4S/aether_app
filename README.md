# Aether

A native floating AI assistant for macOS 26+. Swift 6, SwiftUI Liquid Glass, SwiftData, and direct streaming from a local Ollama instance. No web views, cloud model inference, accounts, API keys, or telemetry. Optional text-only web retrieval uses one pinned dependency, SwiftSoup 2.14.3, to parse HTML locally.

## Requirements

- macOS 26 or newer and Apple silicon recommended.
- Xcode with a macOS 26+ SDK. Developed and tested with Xcode 27.0 / Swift 6.4.
- Ollama and an installed local model. The default is `huihui_ai/qwen3.5-abliterated:9b-q4_K`, the community Huihui abliterated variant of Qwen 3.5 9B, quantized as Q4_K_M. The original `qwen3.5:9b-q4_K_M` remains usable as an alternative.
- Approximately 6.6 GB for this model, plus runtime memory and Xcode build storage.

## Set up Ollama

Install the native macOS application from [Ollama](https://ollama.com/download/mac) and launch it. Alternatively, install the command-line runtime:

```sh
brew install ollama
OLLAMA_NO_CLOUD=1 OLLAMA_HOST=127.0.0.1:11434 ollama serve
```

In a second terminal, explicitly download the model:

```sh
ollama pull huihui_ai/qwen3.5-abliterated:9b-q4_K
curl http://127.0.0.1:11434/api/tags
```

The download is several GB. Aether never installs or downloads models itself. For an already running Ollama application, you can disable its cloud features by adding `"disable_ollama_cloud": true` to `~/.ollama/server.json` (preserve existing settings), then restarting Ollama. See the [official local-only configuration](https://docs.ollama.com/faq#how-do-i-disable-ollamas-cloud-features).

For inference, Aether accepts HTTP endpoints on literal `127.0.0.1` or `[::1]` only. Redirects and proxies are disabled. Cloud-backed model metadata and cloud model names are rejected. Model metadata is checked before each inference. This assumes a genuine Ollama server on your Mac; the app cannot audit a replacement server's implementation.

## Build and run

Open `Aether.xcodeproj`, select the **Aether** scheme and **My Mac**, then Run. A Developer Team is not needed for a local ad hoc build. If Xcode asks for signing, select **Sign to Run Locally**.

Or run:

```sh
./Scripts/build.sh
./Scripts/run.sh
```

The build script compiles Release and installs it directly at **`/Applications/Aether.app`**, replacing the previous installed version after verifying the new bundle. Quit Aether from its menu bar before rebuilding; the script refuses to update a running copy. If Applications is not writable, use an account permitted to install apps.

`run.sh` opens the installed application in the background. It stays in the menu bar, without a Dock icon or an assistant panel at startup. Use the configured global shortcut or **Show Aether** to open the panel; Escape dismisses it while the app keeps running. Double-clicking an already running Aether also opens the panel. **Quit Aether** exits and unregisters its shortcut.

The build product also remains at `.build/Build/Products/Release/Aether.app`. It is locally signed and sandboxed; public distribution requires your own Developer ID signing and notarization.

The complete generated Xcode project is included. `project.yml` is the reproducible XcodeGen source; XcodeGen is needed only if you change project configuration:

```sh
xcodegen generate
```

## Use

- Open Aether once from Applications, then invoke it with **Option + Space**, or **Show Aether** in its menu bar menu. The text field receives focus.
- Type a message and press **Return**. **Shift + Return** inserts a new line.
- **Command + .** stops generation. **Escape** dismisses the panel; a running text response may continue in the background.
- **Command + N** starts a new conversation. **Command + Shift + H** opens searchable history.
- Use a history row's context menu to rename or permanently delete it.
- Copy whole messages or individual code blocks. Use **Regenerate** to replace the latest assistant response.
- Scroll upward to pause automatic following; click **Latest** to return to the live response.
- Settings are available through the panel or menu bar. If another app owns Option + Space, choose another modifier/key combination in General.

## Optional web access

Click the **globe** beside the composer to enable Web, or enable it in **Settings → Web**. It is off by default. With Web off, chat stays offline and regeneration makes no web request. The selected Ollama model always runs locally.

With Web on:

- A plain question is sent to Bing's public RSS search endpoint (up to the first 500 characters). Previous messages and the system prompt are not sent to the search engine.
- If the question contains HTTP/HTTPS URLs, Aether reads up to three public HTTPS URLs directly instead of searching. The question itself is not sent to those websites; they receive ordinary page requests.
- Up to three sources are supplied as bounded excerpts to the local model. Page text is marked as untrusted reference data in the prompt. No web content can trigger additional tools or computer actions.
- Sources are shown under the answer with clickable titles and an indication of **Page read** or **Search excerpt only**. Excerpts are used when search results exist but a publisher blocks text retrieval. Links and source metadata remain in history; downloaded page bodies are transient.
- A search or page-reading failure is shown explicitly and does not silently generate an answer claiming to have consulted the web. You can retry, use a more precise query, paste a different URL, or turn Web off and regenerate offline.

Bing RSS is a public search interface, not a guaranteed commercial API. It may be unavailable or return weak/irrelevant results; a direct URL is often more precise. Only static HTML/text is read: no JavaScript execution, sign-in, cookies, remote images, PDFs, or arbitrary downloads. Some documentation sites require JavaScript and cannot be read this way.

Web requests use HTTPS, an isolated ephemeral session, limited redirects, request timeouts, and download caps (256 KB for search feeds, 1.5 MB per page). URL credentials, custom ports, local hostnames, IP literals, and DNS answers pointing to private/reserved addresses are blocked. DNS is validated before each request and redirect; this is not a network sandbox or protection against a malicious server changing its DNS between validation and connection. No request includes Ollama conversation payloads or credentials.

SwiftSoup is pinned in `project.yml` and `Package.resolved`; the first build needs Internet access to resolve this dependency. Its MIT license is included in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the application bundle.

## Settings and memory

The default context is **8,192 tokens**, with a **2,048-token** response limit. Increasing context increases KV-cache memory and prompt evaluation time. Start at 8K on a 16 GB Mac; the model's advertised maximum is not a guarantee that it fits available memory. Response length is capped at half the context.

A conservative UTF-8 byte budget retains complete recent conversation turns and reserves room for the system prompt, model template, and response. This deliberately retains less history than a model-specific tokenizer might. Full messages remain in local history. An oversized single prompt produces a clear error instead of silent truncation.

Qwen thinking is **off by default** (`think: false`) so answers start promptly. You can enable it in Local AI settings for harder questions; it can substantially delay the first visible answer. Thinking output remains hidden and is discarded. Other models use their own default thinking behavior.

Choose another installed local model, temperature, response limit, system prompt, appearance, orb animation preference, and global shortcut in Settings. Changes apply to subsequent responses. No model download control is hidden behind these settings.

## Voice and accessibility

The microphone button starts optional dictation only after permission. Aether requires both on-device support for the current macOS locale and on-device recognition for the request. If local speech assets or permissions are unavailable, it reports the problem and leaves text chat usable. Dictation fills the composer and never sends it automatically. Microphone input stops when sending, changing conversations, or hiding the panel.

A response's speaker button uses native speech synthesis. **Stop speaking** stops playback. Voice behavior depends on installed macOS language assets and audio hardware.

The UI follows Reduce Motion, Reduce Transparency, and system/light/dark appearance preferences. Animations pause while the panel is hidden. Controls have accessibility labels, keyboard shortcuts, and selectable text. Code blocks scroll horizontally and have a copy action. Markdown supports headings, quotes, lists, rules, inline emphasis/links/code, and fenced code blocks; syntax highlighting colors keywords, types, functions, strings, numbers, comments, and preprocessor directives, with separate light/dark palettes. Supported labels include C/C++, C#, Objective-C, Swift, Python, JavaScript/TypeScript, Java, Kotlin, Go, Rust, SQL, JSON, shell, XML/HTML, CSS, Ruby, YAML and TOML. Highlighting is lexical rather than a full compiler parser, and blocks above 100 KB stay plain to keep streaming responsive. Tables, mathematical typesetting, and embedded remote images are not rendered as rich content.

## Storage and privacy

SwiftData stores conversations and messages in `Aether/History.store` inside the sandbox's Application Support directory, normally:

```
~/Library/Containers/com.aether.local.Aether/Data/Library/Application Support/Aether/
```

Preferences are in Aether's local UserDefaults domain. CloudKit is explicitly disabled. Model thinking output is discarded and is never displayed, stored, or sent back as chat history. Partial responses are checkpointed about once per second, and retained on cancellation or connection failure. A response interrupted by a previous app exit is marked interrupted on reopen.

History is not separately encrypted by Aether. It inherits macOS account and disk protection. History deletion removes records from the active store, rather than securely erasing filesystem blocks or backups. A storage error is shown without automatically deleting or replacing existing history. Tests use in-memory stores.

## Architecture

- `App/`: lifecycle, focus restoration, floating NSPanel, global Carbon hotkey registration.
- `Models/`: Ollama wire types and SwiftData conversation/message schema.
- `Services/`: native URLSession NDJSON client, bounded public-web retrieval, RSS/HTML parsing, and optional native speech.
- `State/`: observable settings, conversation lifecycle, prompt budgeting, cancellation, persistence.
- `Views/`: native glass shell, orb, streaming conversation, Markdown, history, settings.
- `AetherTests/`: stream decoding, local-only endpoint checks, conversation lifecycle and persistence, prompt budgeting, Markdown fences. Test fixtures never appear in the application.

`InferenceBackend` separates chat state from Ollama. Model work runs asynchronously; persistence and observable UI state are confined to the main actor. Streaming text updates are batched to limit UI work. Orb rendering is limited to 12 fps idle / 24 fps active and pauses when hidden or disabled.

## Validate

```sh
./Scripts/test.sh
```

See [VALIDATION.md](VALIDATION.md) for the checks actually performed and remaining limits. Default tests do not download a model or contact the network. To run the separate live page/search check:

```sh
TEST_RUNNER_AETHER_LIVE_WEB_TESTS=1 xcodebuild -project Aether.xcodeproj -scheme Aether \
  -destination 'platform=macOS' -derivedDataPath .build \
  -only-testing:AetherTests/LiveWebTests CODE_SIGNING_ALLOWED=NO test
```

## Official references

- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Ollama streaming chat API](https://docs.ollama.com/api/chat)
- [Ollama local model listing](https://docs.ollama.com/api/tags)
- [Huihui Qwen 3.5 9B abliterated Q4_K_M](https://ollama.com/huihui_ai/qwen3.5-abliterated:9b-q4_K)
- [Original Qwen 3.5 9B Q4_K_M model](https://ollama.com/library/qwen3.5:9b-q4_K_M)
- [Apple: On-device recognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
