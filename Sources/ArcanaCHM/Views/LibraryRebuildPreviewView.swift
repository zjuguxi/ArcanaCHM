import SwiftUI

struct LibraryRebuildPreviewView: View {
    let preview: LibraryRebuildPreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("library_rebuild_title".loc)
                .font(.title2.bold())
            Text("library_rebuild_explanation".loc)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                summaryRow("library_rebuild_scanned".loc, preview.scannedDirectoryCount)
                summaryRow("library_rebuild_preserved".loc, preview.preservedBookCount)
                summaryRow("library_rebuild_recovered".loc, preview.recoveredBookCount)
                summaryRow("library_rebuild_skipped".loc, preview.warnings.count)
            }

            GroupBox("library_rebuild_books".loc) {
                List(preview.books) { book in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                        Text(book.rootURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 180)
            }

            if !preview.warnings.isEmpty {
                GroupBox("library_rebuild_warnings".loc) {
                    List(preview.warnings) { warning in
                        Text("\(warning.folderName): \(message(for: warning.reason))")
                            .font(.caption)
                    }
                    .frame(minHeight: 90, maxHeight: 150)
                }
            }

            Text("library_rebuild_snapshot_note".loc)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("library_rebuild_cancel".loc, role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("library_rebuild_confirm".loc, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.books.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
    }

    @ViewBuilder
    private func summaryRow(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value.formatted())
                .monospacedDigit()
        }
    }

    private func message(for reason: LibraryRebuildSkippedReason) -> String {
        switch reason {
        case .unsafeDirectory:
            return "library_rebuild_warning_unsafe".loc
        case .noReadableContent:
            return "library_rebuild_warning_no_content".loc
        case .duplicateContent:
            return "library_rebuild_warning_duplicate".loc
        }
    }
}
