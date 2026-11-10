# Demo media

Captured from the installed Aether application on 10 November 2026. The interface, streamed responses, generation metrics, and source labels are genuine.

## Capture setup

- Local model: `huihui_ai/qwen3.5-abliterated:9b-q4_K`.
- Context budget: 8,192 tokens; Qwen thinking disabled.
- English prompts and responses, native macOS interface.
- Coding uses offline chat. The research segment explicitly enables Web and reads `https://www.swift.org/`.

## Walkthrough

The GIF and H.264 MP4 use selected app captures, resized and placed on a fixed canvas. Waiting time is shortened and completed responses are held for reading. They are edited walkthroughs, not real-time performance recordings. No interface or model response was recreated for the media.

The coding conversation requests a C word counter, then refines full whitespace handling and const correctness. The final function was compiled with warnings treated as errors and checked against nine cases: NULL, empty input, whitespace-only input, a single word, repeated spaces, tabs/newlines, vertical-tab/form-feed, the four-word example, and a high-byte character.

The research conversation asks for a two-sentence summary of the Swift website. The app displays a clickable source labeled **Page read**.

| File | Purpose |
| --- | --- |
| `aether-demo.gif` | Inline README walkthrough. |
| `aether-demo.mp4` | H.264 version of the same walkthrough. |
| `aether-code.png` | Full-size capture of the final highlighted C function. |
| `aether-web.png` | Full-size capture of the completed sourced answer. |

The phrase “Tung tung tung Sahur” is part of the demo's example data and developer-digest prompt.
