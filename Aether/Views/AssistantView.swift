import SwiftUI

struct AssistantRootView: View {
    @Bindable var runtime: AppRuntime

    var body: some View {
        Group {
            if let store = runtime.store {
                AssistantView(store: store, runtime: runtime)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Local history unavailable", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.title2)
                    Text(runtime.storageIssue ?? "Could not initialize local storage.")
                        .textSelection(.enabled)
                    Button("Retry Opening History") { runtime.initializeStorage() }.buttonStyle(.glassProminent)
                    Button("Quit Aether") { NSApplication.shared.terminate(nil) }
                }.padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusEffectDisabled()
        .modifier(FloatingSurface())
        .padding(14)
        .preferredColorScheme(runtime.settings.colorScheme)
        .onExitCommand { runtime.hidePanel() }
    }
}

struct AssistantView: View {
    @Bindable var store: ConversationStore
    @Bindable var runtime: AppRuntime
    @State private var showHistory = false
    @State private var speech = SpeechService.shared
    @FocusState private var inputFocused: Bool
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: OrbView.Phase {
        if speech.isListening { return .listening }
        if store.errorMessage != nil { return .error }
        if store.webStatus != nil { return .processing }
        if store.isGenerating { return store.isThinking || store.selected?.orderedMessages.last?.content.isEmpty == true ? .processing : .generating }
        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let persistenceError = store.persistenceError {
                HStack {
                    Text(persistenceError).font(.caption)
                    Button("Retry Save") { store.save() }
                }.padding(12).background(.orange.opacity(0.12))
            }
            if store.isExpanded {
                ConversationView(store: store)
            } else {
                welcome
            }
            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Retry") { store.regenerate() }.buttonStyle(.glass)
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
            if let error = speech.errorMessage {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Dismiss") { speech.errorMessage = nil }.buttonStyle(.borderless)
                }.padding(.horizontal, 24).padding(.vertical, 8)
            }
            GlassEffectContainer(spacing: 12) { composer }
            footer
        }
        .onChange(of: store.isExpanded, initial: true) { _, expanded in runtime.resizePanel(expanded: expanded) }
        .onChange(of: store.isGenerating) { if store.isGenerating { speech.stopListening() } }
        .onChange(of: store.selected?.id) { speech.stopListening() }
        .onChange(of: store.focusRequest) { inputFocused = true }
        .onAppear { inputFocused = true }
        .popover(isPresented: $showHistory, arrowEdge: .leading) {
            HistoryView(store: store, dismiss: { showHistory = false }).frame(width: 320, height: 450)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if store.isExpanded {
                OrbView(phase: phase, animate: runtime.panelVisible && runtime.settings.animateOrb, audioLevel: speech.audioLevel)
                    .frame(width: 30, height: 30).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("AETHER").font(.system(.caption, design: .rounded, weight: .semibold)).tracking(3)
                if store.isExpanded {
                    Text(store.selected?.title ?? "Conversation").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { showHistory.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .help("Conversation history").accessibilityLabel("Conversation history")
                        .keyboardShortcut("h", modifiers: [.command, .shift])
                    Button { store.newConversation() } label: { Image(systemName: "square.and.pencil") }
                        .help("New conversation (⌘N)").accessibilityLabel("New conversation").keyboardShortcut("n")
                    SettingsLink { Image(systemName: "slider.horizontal.3") }
                        .simultaneousGesture(TapGesture().onEnded { runtime.hidePanel(restoreFocus: false) })
                        .help("Settings").accessibilityLabel("Settings").keyboardShortcut(",")
                    Button { runtime.hidePanel() } label: { Image(systemName: "xmark") }
                        .help("Dismiss (Escape)").accessibilityLabel("Dismiss Aether")
                }
                .buttonStyle(.glass).controlSize(.small)
            }
        }
        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 4)
            OrbView(phase: phase, animate: runtime.panelVisible && runtime.settings.animateOrb, audioLevel: speech.audioLevel)
                .frame(width: 82, height: 82)
            VStack(spacing: 7) {
                Text("A little space to think.").font(.system(size: 25, weight: .medium, design: .rounded))
                Text("Your ideas. Your Mac. Your assistant.").font(.callout).foregroundStyle(.secondary)
            }
            if store.connection == .ready {
                HStack(spacing: 8) {
                    suggestion("Explain something")
                    suggestion("Help me write")
                    suggestion("Think it through")
                }.padding(.top, 5)
            } else {
                ConnectionSetupView(store: store, compact: true)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 24)
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) { store.draft = text + ": "; inputFocused = true }
            .font(.caption).buttonStyle(.glass).controlSize(.small)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask anything…", text: $store.draft, axis: .vertical)
                .textFieldStyle(.plain).font(.body).lineLimit(1...5)
                .focused($inputFocused)
                .onKeyPress(keys: [.return], phases: .down) { key in
                    if key.modifiers.contains(.shift) { return .ignored }
                    if !store.isGenerating { store.send() }
                    return .handled
                }
                .accessibilityLabel("Message to Aether")
                .padding(.vertical, 9)
            if !store.isGenerating {
                Button {
                    runtime.settings.webSearchEnabled.toggle()
                } label: {
                    Image(systemName: runtime.settings.webSearchEnabled ? "globe.badge.chevron.backward" : "globe")
                        .foregroundStyle(runtime.settings.webSearchEnabled ? .indigo : .secondary)
                        .frame(width: 18, height: 24)
                }
                .buttonStyle(.glass)
                .help(runtime.settings.webSearchEnabled ? "Web on — this question is sent to Bing, or its URLs are read directly" : "Enable web search")
                .accessibilityLabel(runtime.settings.webSearchEnabled ? "Disable web search" : "Enable web search")
                .accessibilityValue(runtime.settings.webSearchEnabled ? "On" : "Off")
                Button {
                    if speech.isListening || speech.isRequestingPermissions { speech.stopListening() }
                    else {
                        let prefix = store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            await speech.startListening { transcript in
                                store.draft = prefix.isEmpty ? transcript : prefix + " " + transcript
                            }
                        }
                    }
                } label: {
                    Image(systemName: speech.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(speech.isListening ? .red : .secondary).frame(width: 18, height: 24)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(speech.isListening ? "Stop dictation" : "Start on-device dictation")
                .help("On-device dictation")
            }
            if store.isGenerating {
                Button { store.stop() } label: { Image(systemName: "stop.fill").frame(width: 24, height: 24) }
                    .buttonStyle(.glass).help("Stop generation (⌘.)")
                    .keyboardShortcut(".").accessibilityLabel("Stop generation")
                    .glassEffectID("composerAction", in: glass)
            } else {
                Button { store.send() } label: { Image(systemName: "arrow.up").fontWeight(.semibold).frame(width: 24, height: 24) }
                    .buttonStyle(.glassProminent).tint(.indigo)
                    .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message").help("Send (Return)")
                    .glassEffectID("composerAction", in: glass)
            }
        }
        .padding(10).padding(.leading, 6)
        .background(.primary.opacity(0.045), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08)) }
        .padding(.horizontal, 20).padding(.top, 10)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: store.isGenerating)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield").font(.system(size: 10))
            Text(store.webStatus ?? (store.isGenerating ? (store.isThinking ? "Processing locally…" : "Generating locally…") : runtime.settings.webSearchEnabled ? "Web on · local AI" : store.connection.title))
            Spacer()
            if speech.isSpeaking {
                Button("Stop speaking") { speech.stopAll() }.buttonStyle(.borderless)
            }
            Text(store.isGenerating ? "⌘. to stop" : "↵ send  ·  ⇧↵ new line")
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .padding(.horizontal, 27).padding(.top, 9).padding(.bottom, 17)
    }
}

struct ConnectionSetupView: View {
    @Bindable var store: ConversationStore
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(store.connection.title, systemImage: "bolt.horizontal.circle")
                    .font(.callout.weight(.medium))
                Spacer()
                Button("Retry") { Task { await store.checkConnection() } }
                    .buttonStyle(.glass).controlSize(.small)
                    .disabled(store.connection == .checking)
            }
            if case .unavailable(let reason) = store.connection {
                if !compact { Text(reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("Install Ollama, then run it on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
            if store.connection == .modelMissing || { if case .unavailable = store.connection { true } else { false } }() {
                HStack(alignment: .center, spacing: 8) {
                    Text("ollama pull \(store.settings.model)")
                        .font(.system(.caption, design: .monospaced)).lineLimit(1).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { Clipboard.copy("ollama pull \(store.settings.model)") } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).accessibilityLabel("Copy model installation command")
                }
                Text("Run this command only when ready to download several GB. Choose another installed model in Settings.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12).background(.primary.opacity(0.035), in: .rect(cornerRadius: 14))
    }
}
