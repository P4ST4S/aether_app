import SwiftUI

struct HistoryView: View {
    @Bindable var store: ConversationStore
    let dismiss: () -> Void
    @State private var query = ""
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?

    private var filtered: [Conversation] {
        store.conversations.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your conversations").font(.headline)
                Spacer()
                Button { store.newConversation(); dismiss() } label: { Image(systemName: "plus") }
                    .buttonStyle(.glass).accessibilityLabel("New conversation")
            }.padding(.horizontal).padding(.top)
            TextField("Search history", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
            if filtered.isEmpty {
                ContentUnavailableView(query.isEmpty ? "A fresh start" : "No conversations found",
                                       systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Conversations are stored only on this Mac."))
            } else {
                List(filtered) { conversation in
                    Button {
                        store.open(conversation)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(conversation.title).lineLimit(2).foregroundStyle(.primary)
                                Text(conversation.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selected?.id == conversation.id { Image(systemName: "checkmark").foregroundStyle(.indigo) }
                        }.padding(.vertical, 5).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Rename…") { newTitle = conversation.title; renaming = conversation }
                        Button("Delete…", role: .destructive) { deleting = conversation }
                    }
                    .accessibilityHint("Open conversation. Use the context menu to rename or delete.")
                }.listStyle(.plain)
            }
        }
        .alert("Rename Conversation", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let conversation = renaming { store.rename(conversation, to: newTitle) }
                renaming = nil
            }
        }
        .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete Conversation", role: .destructive) {
                if let conversation = deleting { store.delete(conversation) }
                deleting = nil
            }
        } message: { Text("This permanently removes the conversation from this Mac.") }
    }
}
