import SwiftUI

struct ReaderTabBar: View {
    @EnvironmentObject private var workspace: ReaderWorkspaceStore
    @EnvironmentObject private var locale: LocalizationService

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(workspace.tabs) { tab in
                            ReaderTabButton(tab: tab)
                                .id(tab.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .onChange(of: workspace.activeTabID) { _, id in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Divider()
                .frame(height: 22)

            Button {
                workspace.newTab()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(workspace.tabs.count >= ReaderWorkspaceStore.maximumTabCount)
            .help("reader_new_tab".loc)
            .accessibilityLabel("reader_new_tab".loc)
            .padding(.horizontal, 8)
        }
        .frame(height: 40)
        .background(.bar)
    }
}

private struct ReaderTabButton: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var workspace: ReaderWorkspaceStore
    @EnvironmentObject private var locale: LocalizationService
    @ObservedObject var tab: ReaderTabSession
    @State private var isHovering = false

    private var isActive: Bool {
        workspace.activeTabID == tab.id
    }

    private var title: String {
        library.book(id: tab.bookID)?.title ?? "reader_new_tab_title".loc
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: tab.bookID == nil ? "plus.square" : "book.closed")
                .font(.caption)
                .foregroundStyle(isActive ? .teal : .secondary)

            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)

            Button {
                workspace.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(isHovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("reader_close_tab".loc)
            .accessibilityLabel("reader_close_tab_named".loc(title))
            .opacity(isActive || isHovering ? 1 : 0.45)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(minWidth: 130, maxWidth: 220, minHeight: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isActive ? Color(nsColor: .textBackgroundColor) : (isHovering ? Color.primary.opacity(0.06) : .clear))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isActive ? Color.primary.opacity(0.12) : .clear, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture {
            workspace.activateTab(tab.id)
        }
        .onHover { isHovering = $0 }
        .help(title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
