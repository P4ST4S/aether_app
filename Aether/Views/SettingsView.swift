import SwiftUI

struct SettingsView: View {
    @Bindable var runtime: AppRuntime
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            ModelSettingsView(settings: runtime.settings, store: runtime.store)
                .tabItem { Label("Local AI", systemImage: "cpu") }.tag(0)
            GeneralSettingsView(runtime: runtime)
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }.tag(1)
            WebSettingsView(settings: runtime.settings)
                .tabItem { Label("Web", systemImage: "globe") }.tag(3)
            HistorySettingsView(store: runtime.store)
                .tabItem { Label("History", systemImage: "clock") }.tag(2)
        }
        .frame(width: 590, height: 640)
        .onAppear { runtime.hidePanel(restoreFocus: false); NSApp.activate() }
    }
}

struct ModelSettingsView: View {
    @Bindable var settings: AppSettings
    var store: ConversationStore?
    @State private var endpointDraft = ""
    @State private var endpointError: String?
    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    TextField("Local endpoint", text: $endpointDraft).textFieldStyle(.roundedBorder)
                    Button("Apply") { applyEndpoint() }.disabled(store?.isGenerating == true)
                }
                Text("Only literal loopback addresses are accepted. No accounts, cloud inference, or telemetry.")
                    .font(.caption).foregroundStyle(.secondary)
                if let endpointError { Text(endpointError).font(.caption).foregroundStyle(.red) }
                if let store { ConnectionSetupView(store: store) }
            }
            Section("Model") {
                Picker("Installed model", selection: $settings.model) {
                    if !(store?.installedModels.contains { $0.name == settings.model } ?? false) {
                        Text("\(settings.model) (not installed)").tag(settings.model)
                    }
                    ForEach(store?.installedModels ?? []) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .disabled(store?.isGenerating == true)
                .onChange(of: settings.model) { Task { await store?.checkConnection() } }
                Picker("Context budget", selection: $settings.contextLength) {
                    ForEach([2048, 4096, 8192, 16384, 32768, 65536], id: \.self) { count in
                        Text("\(count.formatted()) tokens\(count == 8192 ? " — recommended" : "")").tag(count)
                    }
                }
                Text("Start at 8,192 on a 16 GB Mac. Larger contexts increase KV-cache memory and prompt processing time; 32K–64K may cause memory pressure. The model's maximum context is not a RAM guarantee. Older turns are omitted conservatively from requests while remaining in history.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Temperature")
                    Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                    Text(settings.temperature, format: .number.precision(.fractionLength(1))).monospacedDigit().frame(width: 30)
                }
                Picker("Response limit", selection: $settings.responseLimit) {
                    ForEach([512, 1024, 2048, 4096, 8192], id: \.self) { count in Text("\(count) tokens").tag(count) }
                }
                Text("Response length is capped at half the context budget.").font(.caption).foregroundStyle(.secondary)
            }
            if settings.model.lowercased().contains("qwen3") {
                Section("Reasoning") {
                    Toggle("Enable Qwen thinking (slower)", isOn: $settings.enableThinking)
                    Text("Off by default for faster answers. When enabled, the model reasons before answering; this output remains hidden and is discarded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("System prompt") {
                TextEditor(text: $settings.systemPrompt)
                    .font(.body).frame(minHeight: 85).padding(6)
                    .background(.primary.opacity(0.03), in: .rect(cornerRadius: 8))
                    .accessibilityLabel("System prompt")
                Text("Applied to the next response, including existing conversations.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { endpointDraft = settings.endpoint; Task { await store?.checkConnection() } }
    }
    private func applyEndpoint() {
        do {
            _ = try OllamaClient.validateEndpoint(endpointDraft)
            settings.endpoint = endpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            endpointError = nil
            Task { await store?.checkConnection() }
        } catch { endpointError = error.localizedDescription }
    }
}

struct GeneralSettingsView: View {
    @Bindable var runtime: AppRuntime
    var body: some View {
        @Bindable var settings = runtime.settings
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Animate the Aether orb", isOn: $settings.animateOrb)
                Text("Aether also follows Reduce Motion and Reduce Transparency in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Global shortcut") {
                Picker("Modifiers", selection: $settings.shortcutModifiers) {
                    Text("Option ⌥").tag("option")
                    Text("Control + Option ⌃⌥").tag("controlOption")
                    Text("Command + Shift ⇧⌘").tag("commandShift")
                    Text("Control + Shift ⌃⇧").tag("controlShift")
                }
                Picker("Key", selection: $settings.shortcutKey) {
                    Text("Space").tag("space")
                    Text("A").tag("a")
                    Text("Return").tag("return")
                    Text("F1").tag("f1")
                }
                if let issue = runtime.shortcutIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                Text("Option + Space is the default. If another app uses it, choose another combination. The menu bar icon always remains available.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Voice") {
                Text("Read any completed response aloud using its speaker button. Dictation uses on-device recognition only, when supported for your language.")
                    .font(.callout)
                Button("Stop Speaking") { SpeechService.shared.stopAll() }
            }
            Section {
                Text("Aether 1.0 · Built for local thought.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.shortcutModifiers) { runtime.applyShortcut() }
        .onChange(of: settings.shortcutKey) { runtime.applyShortcut() }
    }
}

struct HistorySettingsView: View {
    var store: ConversationStore?
    @State private var confirmDelete = false
    var body: some View {
        Form {
            Section("On this Mac") {
                LabeledContent("Conversations", value: "\(store?.conversations.count ?? 0)")
                Text("History is saved in Aether's sandbox using SwiftData, with CloudKit disabled. It contains your messages and model replies. Thinking output is discarded. Protect your Mac account and disk with FileVault if needed.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Delete All Conversations…", role: .destructive) { confirmDelete = true }
                    .disabled(store?.conversations.isEmpty ?? true)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all conversations?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete All Conversations", role: .destructive) { store?.deleteAll() }
        } message: { Text("All conversation history on this Mac will be permanently removed. Active generation will stop.") }
    }
}


struct WebSettingsView: View {
    @Bindable var settings: AppSettings
    var body: some View {
        Form {
            Section("Web access") {
                Toggle("Use web sources for new messages", isOn: $settings.webSearchEnabled)
                Text("You can also toggle Web with the globe next to the message field. It is off by default, so normal chat works offline.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Search and page reading") {
                LabeledContent("Search provider", value: "Bing public RSS search")
                Text("When Web is on, the current question is sent to Bing. Earlier conversation messages and your system prompt are not sent to the search engine. Paste a public HTTPS URL to read it directly instead of searching. The selected local model writes the answer from the retrieved text.")
                Text("Sources appear under each answer. Aether distinguishes pages it read from search excerpts when a site blocks reading. Public search can be unavailable or return irrelevant results; try a more precise query or a direct URL.")
            }
            Section("Limits") {
                Text("Text pages only: no JavaScript, login, cookies, remote images, PDF downloads, or local-network access. Up to three sources are read per question, with bounded downloads and excerpts. A failed search is shown as an error, rather than silently answering as if it succeeded.")
                    .foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
