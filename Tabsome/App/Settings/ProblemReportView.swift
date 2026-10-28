import AppKit
import SwiftUI

/// Settings › About › Report a Problem… (PLAN.md §7 Phase 7a): the whole report, exactly as it
/// will be saved, then a save panel. Tabsome sends nothing; the user attaches the file to an
/// email or message themselves (§6.1 S4).
struct ProblemReportView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    /// Built once when the sheet opens; the description goes on top when it's saved.
    @State private var reportBody = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a Problem").font(.title3.bold())
            Text("What happened? What did you expect instead?")
                .foregroundStyle(.secondary)
            TextEditor(text: $description)
                .font(.body)
                .frame(height: 72)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .accessibilityLabel("What happened")
            Text("Your description and everything below go in the report. Tabsome’s log records what it did with windows, by number; it never records window titles, tab names, or what’s in your apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ReportTextView(text: reportBody)
                .frame(minHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                .accessibilityLabel("Report")
            HStack {
                Text("Tabsome doesn’t send it anywhere. Save it, then attach the file to an email or message.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Report…") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 600)
        .onAppear {
            FileLog.shared.flush()
            reportBody = ProblemReport.body(facts: model.reportFacts, logs: ProblemReport.logs(in: FileLog.shared.directory, keep: FileLog.shared.keep))
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = ProblemReport.fileName()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let text = ProblemReport.text(description: description, body: reportBody)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            FileLog.shared.write("problem report saved bytes=\(text.utf8.count)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismiss()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

/// A read-only text view that stays quick with megabytes of log (SwiftUI's Text doesn't).
private struct ReportTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        view.textContainerInset = NSSize(width: 6, height: 6)
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }
}
