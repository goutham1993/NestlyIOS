import NestlyCore
import SwiftUI
import UIKit

/// Gives the toolbar access to the live text view's cursor.
@MainActor
final class NotesEditorHandle {
    weak var textView: UITextView?
    var onChange: ((String) -> Void)?

    func format(_ format: NoteLineFormat) {
        guard let tv = textView else { return }
        apply(AppointmentNotesFormat.formatCurrentLine(tv.text, tv.selectedRange.location, format), to: tv)
    }

    func done() { textView?.resignFirstResponder() }

    func apply(_ result: AppointmentNotesFormat.FormatResult, to tv: UITextView) {
        tv.text = result.text
        tv.selectedRange = NSRange(location: min(result.cursor, (result.text as NSString).length), length: 0)
        onChange?(result.text)
    }
}

/// Plain-text editor that continues bullet / numbered / checkbox lists on Enter (spec §17.3).
struct NotesTextView: UIViewRepresentable {
    @Binding var text: String
    let handle: NotesEditorHandle

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        tv.delegate = context.coordinator
        tv.text = text
        handle.textView = tv
        handle.onChange = { [binding = $text] in binding.wrappedValue = $0 }
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        if tv.text != text { tv.text = text }
        handle.textView = tv
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NotesTextView

        init(_ parent: NotesTextView) { self.parent = parent }

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            let old = tv.text ?? ""
            let newText = (old as NSString).replacingCharacters(in: range, with: "\n")
            guard let result = AppointmentNotesFormat.continueListOnEnter(
                oldText: old, oldSelectionStart: range.location, oldSelectionEnd: range.location + range.length,
                newText: newText, newCursor: range.location + 1
            ) else { return true }
            MainActor.assumeIsolated { parent.handle.apply(result, to: tv) }
            return false
        }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
        }
    }
}

/// Editor + toolbar, or a read-only preview with tappable checkboxes.
struct FormattedNotesSection: View {
    let title: String
    @Binding var text: String
    @Binding var preview: Bool
    /// Called after a checkbox is toggled in preview mode.
    let onToggle: (String) -> Void
    @State private var handle = NotesEditorHandle()

    var body: some View {
        Section {
            if preview {
                NotesPreview(text: text) { lineIndex in
                    text = AppointmentNotesFormat.toggleCheckbox(text, lineIndex)
                    onToggle(text)
                }
            } else {
                HStack(spacing: 8) {
                    Button("• Bullet") { handle.format(.BULLET) }
                    Button("1. Numbered") { handle.format(.NUMBERED) }
                    Button("☐ Checkbox") { handle.format(.CHECKBOX) }
                    Spacer()
                    Button("Done") { handle.done() }.bold()
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                NotesTextView(text: $text, handle: handle)
                    .frame(minHeight: 180)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if let progress = NotesProgress(text) { Text("\(progress.done) of \(progress.total) done") }
                Button(preview ? "Edit" : "Preview") { preview.toggle() }.textCase(nil)
            }
        }
    }
}

struct NotesPreview: View {
    let text: String
    let toggle: (Int) -> Void

    var body: some View {
        let lines = text.components(separatedBy: "\n")
        if text.isBlank {
            Text("No notes yet.").foregroundStyle(.secondary)
        }
        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(AppointmentNotesFormat.UNCHECKED_PREFIX.trimmingCharacters(in: .whitespaces))
                || line.trimmingCharacters(in: .whitespaces).hasPrefix(AppointmentNotesFormat.CHECKED_PREFIX.trimmingCharacters(in: .whitespaces)) {
                let checked = line.trimmingCharacters(in: .whitespaces).hasPrefix("☑")
                Button { toggle(index) } label: {
                    HStack(alignment: .top) {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                        Text(String(line.trimmingCharacters(in: .whitespaces).dropFirst(2)))
                            .strikethrough(checked)
                            .foregroundStyle(checked ? .secondary : .primary)
                    }
                }
                .foregroundStyle(.primary)
            } else if !line.isBlank {
                Text(line)
            }
        }
    }
}

struct NotesProgress {
    let done: Int
    let total: Int

    init?(_ text: String?) {
        let items = AppointmentNotesFormat.checkboxItems(text ?? "")
        guard !items.isEmpty else { return nil }
        total = items.count
        done = items.filter(\.checked).count
    }
}
