import SwiftUI

struct ConversationView: View {
    @Bindable var store: ConversationStore
    @State private var followLatest = true
    @State private var userScrolling = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(store.selected?.orderedMessages ?? []) { message in
                        MessageView(message: message, isThinking: store.isThinking && message.state == "streaming")
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 28).padding(.vertical, 20)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollPhaseChange { _, phase in userScrolling = phase == .interacting || phase == .decelerating }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height < 100
            } action: { _, nearBottom in
                if userScrolling { followLatest = nearBottom }
            }
            .onChange(of: store.selected?.orderedMessages.last?.content) {
                if followLatest { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: store.selected?.id) { followLatest = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: store.selected?.messages.count) { followLatest = true; proxy.scrollTo("bottom", anchor: .bottom) }
            .overlay(alignment: .bottom) {
                if !followLatest {
                    Button { followLatest = true; proxy.scrollTo("bottom", anchor: .bottom) } label: {
                        Label("Latest", systemImage: "arrow.down")
                    }.buttonStyle(.glass).padding(8)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !store.isGenerating, store.selected?.orderedMessages.last?.role == "assistant" {
                Button { store.regenerate() } label: { Label("Regenerate", systemImage: "arrow.trianglehead.clockwise") }
                    .font(.caption).buttonStyle(.glass).controlSize(.small)
                    .padding(.trailing, 20).padding(.bottom, 4)
            }
        }
    }
}

struct MessageView: View {
    let message: StoredMessage
    let isThinking: Bool
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(isUser ? "YOU" : "AETHER").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.8)
                if !isUser {
                    Text(message.model).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
                if !message.content.isEmpty {
                    Button { Clipboard.copy(message.content) } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy message").accessibilityLabel("Copy \(isUser ? "your" : "assistant") message")
                    if !isUser {
                        Button { SpeechService.shared.speak(message.content) } label: { Image(systemName: "speaker.wave.2") }
                            .help("Read aloud").accessibilityLabel("Read response aloud")
                    }
                }
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
            if isUser {
                Text(message.content).textSelection(.enabled).font(.body)
            } else if message.content.isEmpty, message.state == "streaming" {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(isThinking ? "Working through your question…" : "Loading model…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                MarkdownContent(text: message.content)
            }
            if message.state == "stopped" || message.state == "failed" {
                Text(message.state == "stopped" ? "Response interrupted" : "Response incomplete — use Retry or Regenerate")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let rate = message.tokensPerSecond {
                Text("\(message.tokenCount ?? 0) tokens · \(rate, specifier: "%.1f") tokens/s\(message.finishReason == "length" ? " · response limit reached" : "")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isUser ? 15 : 0)
        .background(isUser ? Color.primary.opacity(0.045) : .clear, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }
}

@MainActor enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
