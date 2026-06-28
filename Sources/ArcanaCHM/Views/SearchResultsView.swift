import SwiftUI

struct SearchResultsView: View {
    @EnvironmentObject private var reader: ReaderStore
    @EnvironmentObject private var locale: LocalizationService
    let searchText: String
    let lastCompletedSearch: (query: String, hits: [SearchHit])?
    let history: [String]
    var runHistoricalSearch: (String) -> Void
    var deleteHistoryItem: (String) -> Void

    var body: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let completed = lastCompletedSearch, completed.query == trimmed {
            if completed.hits.isEmpty {
                ContentUnavailableView("search_no_results".loc, systemImage: "magnifyingglass")
            } else {
                List(completed.hits) { hit in
                    Button {
                        reader.open(hit.path, searchQuery: trimmed)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(highlighted(hit.title, query: trimmed, baseSize: 13))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(highlighted(hit.snippet, query: trimmed, baseSize: 12))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .help("search_help_open_result".loc)
                }
                .listStyle(.inset)
            }
        } else {
            SearchHistoryView(history: history, runHistoricalSearch: runHistoricalSearch, deleteHistoryItem: deleteHistoryItem)
        }
    }

    private func highlighted(_ text: String, query: String, baseSize: CGFloat) -> AttributedString {
        var attributed = AttributedString(text)
        var searchStart = attributed.startIndex

        while let range = attributed[searchStart...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].backgroundColor = .yellow.opacity(0.48)
            attributed[range].foregroundColor = .primary
            attributed[range].font = .system(size: baseSize, weight: .semibold)
            searchStart = range.upperBound
        }

        return attributed
    }
}

struct SearchHistoryView: View {
    @EnvironmentObject private var locale: LocalizationService
    let history: [String]
    var runHistoricalSearch: (String) -> Void
    var deleteHistoryItem: (String) -> Void

    var body: some View {
        List {
            Section("search_history".loc) {
                if history.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(.secondary)
                        Text("search_no_history".loc)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .help("search_no_history".loc)
                } else {
                    ForEach(history, id: \.self) { query in
                        HStack(spacing: 8) {
                            Button {
                                runHistoricalSearch(query)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    Text(query)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("search_help_search_again".loc(query))

                            Button {
                                deleteHistoryItem(query)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("search_help_delete_entry".loc)
                            .opacity(0.7)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}
