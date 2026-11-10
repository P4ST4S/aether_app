# Validation — 9 November 2026

## Verified

- macOS 27.2, Apple silicon; Xcode 27.0 (27A266a), Swift 6.4. Deployment target: macOS 26.0.
- Debug build and tests with Swift 6 strict concurrency: **18 tests passed**, no failures or unexpected process exits in the final run.
- Release build: **BUILD SUCCEEDED**, locally signed with the app sandbox, local-network client access, and optional microphone/speech entitlements. Release excludes the debugger entitlement and enables the hardened runtime.
- Launched the actual Release application and inspected its native floating interface and Settings.
- The composer received focus at launch. Return submitted an actual question to Ollama. The panel expanded, displayed a partial streamed answer, then the complete French response and generation metrics.
- Qwen model `qwen3.5:9b-q4_K_M` installed with explicit user consent. Ollama 0.40.15 served it locally on `127.0.0.1:11434`; `ollama ps` reported an 8,192-token context and 100% GPU execution, with about 5.8 GB loaded.
- Live response in Aether: 50 generated tokens at approximately 12.6 tokens/s. This is one short request, not a general benchmark.
- Separate real local API timing with thinking disabled: first text at 0.61 seconds, complete 31-token answer at 2.37 seconds, approximately 17.63 generated tokens/s. Warm model, one short request; cold loads and longer prompts can take longer.
- Stop generation worked in the live interface and preserved the interrupted response. Tests also covered cancellation and ignoring callbacks from old tasks.
- Light and dark appearance, installed-model setup information, and native Settings controls inspected.
- The unwanted outer outline is no longer present, confirmed by the user after relaunching the corrected panel. The hosting view's focus ring and native WindowServer shadow are disabled; native Liquid Glass remains.

## Automated coverage

- Stream content, Unicode, separate thinking, completion metrics, server errors, malformed JSON, blank lines.
- Literal-loopback endpoint acceptance and rejection of remote endpoints, credentials, query strings, and unexpected paths.
- Cloud-backed model filtering and explicit fast-mode request encoding.
- Multi-turn request construction without thinking output; regeneration without duplicated user messages.
- Partial-response retention, cancellation, empty-response handling, ignored blank input.
- SwiftData save/reopen, interrupted-response recovery, rename and cascading deletion.
- Model readiness/missing-model states, conservative whole-turn prompt trimming, oversized prompts, unfinished Markdown fences.

Test backends are confined to the test target. No application code returns simulated model replies. Tests use in-memory stores and do not download models or contact Ollama.

## Remaining verification and limits

- Optional dictation and read-aloud compile, but microphone permissions, speech language assets, audio-reactive rendering, and audible playback have not been verified on the user's hardware. Dictation refuses to use a remote recognition service.
- Global hotkey registration and conflict reporting are implemented. Invocation across every desktop/fullscreen combination, conflicting third-party shortcuts, multiple monitors, and keyboard layouts have not been comprehensively exercised.
- Reduce Motion/Transparency behavior is implemented; a full VoiceOver and accessibility audit remains.
- Long sessions, sustained memory/thermal behavior, sleep/wake, network loss during an actual Ollama stream, and disk-full recovery require broader soak testing. Deterministic state tests cover interruption and failure handling.
- Persistence was verified with separate SwiftData contexts; a complete manual reopen/rename/delete matrix across repeated OS restarts remains unverified.
- Markdown highlighting is intentionally lightweight. No rich tables, equations, remote image fetching, or model tools/attachments.
- Local ad hoc signing is suitable for running on this Mac. Developer ID signing and notarization for public distribution have not been performed.
- Xcode's App Intents metadata processor emits its tool warning that extraction is skipped because this app does not depend on AppIntents. There are no Swift source compilation warnings in the final build. The test host also logs unavailable system App Intents registration services; tests still complete successfully.

## Reproduce

```sh
./Scripts/test.sh
./Scripts/build.sh
./Scripts/run.sh
```

Start the Ollama application first, or run `OLLAMA_NO_CLOUD=1 ollama serve` in a terminal. No further model download is needed on the machine used for this validation.

## Installation and background startup update

- `Scripts/build.sh` now builds Release, verifies a staged signed bundle, and installs it at `/Applications/Aether.app`. It refuses to replace a running Aether and restores the previous installed bundle if the replacement fails.
- Ran the updated build/install script successfully. Verified the installed signature and compared its executable with the Release build product.
- `Scripts/run.sh` now launches the installed copy in the background. Confirmed the process runs from `/Applications/Aether.app/Contents/MacOS/Aether`, with `LSUIElement` enabled.
- Startup registers the existing configurable global shortcut and keeps the panel hidden. Menu bar actions, the shortcut, and explicit reopening show the panel. Physical keyboard invocation across other apps remains a manual check; targeted UI-automation keystrokes do not establish global shortcut behavior.
- After this update, the existing test suite was rerun: **18 tests passed**, and the installed application was launched in the background.

## 10 November 2026 — code highlighting and selected model

- Replaced the previous regex-overwrite highlighter with one lexical pass, compiled once per language. Added C/C++ and other common language labels/aliases, separate light/dark palettes, and distinct colors for keywords, types, functions, numbers, strings, comments, and directives. Comment markers inside strings do not override string colors. Very large blocks remain plain and copyable.
- Final test rerun: **23 tests passed**, no failures or unexpected exits. Five new tests cover C styling/content preservation, strings containing URLs/comment markers, multiline comments and partial streamed strings, aliases/themes, and unsupported/large snippets.
- Release build and installation to `/Applications/Aether.app` succeeded. Verified its code signature.
- With the user's explicit request, downloaded `huihui_ai/qwen3.5-abliterated:9b-q4_K` from the publisher's Ollama namespace. Local digest: `92a443adb124f5e805bbdee23fdb38fcd22a7bf00a1016b53f764e741369c600`; download size 6,594,474,755 bytes; quantization Q4_K_M. The original Qwen model remains installed as an alternative.
- Made this Huihui variant the default for new preferences. Verified the installed app's Local AI settings select it, with context 8,192 and Qwen thinking disabled.
- Real local API smoke test: French explanation of C `strlen`, completed normally with 40 tokens. Cold first text 6.63 seconds; total 8.80 seconds; generation approximately 17.96 tokens/s. These timings are one request and are not a general performance claim.
- Verified a real streamed C-code answer inside the installed app using the new model. The completed reply displayed colored C types, keywords, function names, comments, strings, and numbers; 87 tokens at approximately 12.3 tokens/s.
- `ollama ps` reported the Huihui model running at 100% GPU, context 8,192, approximately 5.7 GB loaded. Ollama was started with cloud features disabled and bound to loopback.
- Publisher sources: https://ollama.com/huihui_ai/qwen3.5-abliterated:9b-q4_K and https://huggingface.co/huihui-ai/Huihui-Qwen3.5-9B-abliterated . This is a community modification, not an official Qwen release; no comprehensive comparative model-quality evaluation was performed.
