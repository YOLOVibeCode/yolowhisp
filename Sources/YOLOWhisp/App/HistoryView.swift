import SwiftUI

struct HistoryView: View {
    @State private var searchText: String = ""
    @State private var entries: [HistoryEntry] = []
    @State private var expandedID: UUID?
    private let store: any HistoryStoring

    init(store: any HistoryStoring) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onChange(of: searchText) {
                    loadEntries()
                }

            List {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1fs", entry.duration))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        if expandedID == entry.id {
                            Text(entry.rawText)
                                .font(.body)

                            if let processed = entry.processedText {
                                Divider()
                                Text("Processed:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(processed)
                                    .font(.body)
                            }

                            Button("Copy") {
                                #if canImport(AppKit)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.processedText ?? entry.rawText, forType: .string)
                                #endif
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Text(entry.rawText)
                                .lineLimit(1)
                                .font(.body)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation {
                            expandedID = expandedID == entry.id ? nil : entry.id
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let entry = entries[index]
                        try? store.delete(id: entry.id)
                    }
                    entries.remove(atOffsets: indexSet)
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear { loadEntries() }
    }

    private func loadEntries() {
        if searchText.isEmpty {
            entries = (try? store.entries(limit: 100)) ?? []
        } else {
            entries = (try? store.search(query: searchText)) ?? []
        }
    }
}
