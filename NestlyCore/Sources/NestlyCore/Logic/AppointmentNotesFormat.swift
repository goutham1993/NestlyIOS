import Foundation

/// Line formats available in the free-form notes & questions editor.
public enum NoteLineFormat: Sendable { case BULLET, NUMBERED, CHECKBOX }

/// Pure-text helpers for the free-form appointment notes. Checkbox state lives in the text itself
/// ("☐ ask about fever" / "☑ ask about fever"). All offsets are UTF-16 code units, matching
/// `UITextView.selectedRange` and Kotlin string indices.
public enum AppointmentNotesFormat {
    public static let BULLET_PREFIX = "• "
    public static let UNCHECKED_PREFIX = "☐ "
    public static let CHECKED_PREFIX = "☑ "

    private static let numberedRegex = try! NSRegularExpression(pattern: #"^(\d+)\.\s+"#)
    private static let numberedPrefixRegex = try! NSRegularExpression(pattern: #"^(\d+)\.(?:\s+|$)"#)
    private static let anyPrefixRegex = try! NSRegularExpression(pattern: #"^(•\s+|☐\s+|☑\s+|\d+\.\s+)"#)

    public struct CheckboxItem: Equatable, Sendable {
        public let lineIndex: Int
        public let text: String
        public let checked: Bool

        public init(lineIndex: Int, text: String, checked: Bool) {
            self.lineIndex = lineIndex
            self.text = text
            self.checked = checked
        }
    }

    public struct FormatResult: Equatable, Sendable {
        public let text: String
        public let cursor: Int

        public init(text: String, cursor: Int) {
            self.text = text
            self.cursor = cursor
        }
    }

    public static func checkboxItems(_ text: String) -> [CheckboxItem] {
        lines(text).enumerated().compactMap { index, line in
            let trimmed = trimStart(line)
            if trimmed.hasPrefix(UNCHECKED_PREFIX) {
                return CheckboxItem(lineIndex: index, text: String(trimmed.dropFirst(UNCHECKED_PREFIX.count)), checked: false)
            }
            if trimmed.hasPrefix(CHECKED_PREFIX) {
                return CheckboxItem(lineIndex: index, text: String(trimmed.dropFirst(CHECKED_PREFIX.count)), checked: true)
            }
            return nil
        }
    }

    /// Flips ☐ ↔ ☑ on the given line; returns the text unchanged if that line isn't a checkbox.
    public static func toggleCheckbox(_ text: String, _ lineIndex: Int) -> String {
        var all = lines(text)
        guard all.indices.contains(lineIndex) else { return text }
        let line = all[lineIndex]
        let indent = leadingIndent(line)
        let trimmed = trimStart(line)
        if trimmed.hasPrefix(UNCHECKED_PREFIX) {
            all[lineIndex] = indent + CHECKED_PREFIX + String(trimmed.dropFirst(UNCHECKED_PREFIX.count))
        } else if trimmed.hasPrefix(CHECKED_PREFIX) {
            all[lineIndex] = indent + UNCHECKED_PREFIX + String(trimmed.dropFirst(CHECKED_PREFIX.count))
        } else {
            return text
        }
        return all.joined(separator: "\n")
    }

    /// Applies `format` to the line containing `cursor`, replacing any existing list prefix on that line.
    public static func formatCurrentLine(_ text: String, _ cursor: Int, _ format: NoteLineFormat) -> FormatResult {
        let t = U16(text)
        let safeCursor = cursor.clamped(0, t.count)
        let lineStart = t.lastIndexOfNewline(before: safeCursor - 1) + 1
        let lineEnd = t.indexOfNewline(from: safeCursor) ?? t.count
        let line = t.sub(lineStart, lineEnd)
        let indent = leadingIndent(line)
        let content = replaceFirst(anyPrefixRegex, in: trimStart(line))
        let prefix: String
        switch format {
        case .BULLET: prefix = BULLET_PREFIX
        case .CHECKBOX: prefix = UNCHECKED_PREFIX
        case .NUMBERED: prefix = "\(nextNumber(t.sub(0, lineStart))). "
        }
        let newLine = indent + prefix + content
        let newText = t.sub(0, lineStart) + newLine + t.sub(lineEnd, t.count)
        let lineLen = line.utf16.count
        let cursorInLine = (safeCursor - lineStart).clamped(0, lineLen)
        let offset = indent.utf16.count + prefix.utf16.count + max(cursorInLine - (lineLen - content.utf16.count), 0)
        return FormatResult(text: newText, cursor: lineStart + min(offset, newLine.utf16.count))
    }

    /// If the change from old to new is exactly one "\n" inserted (replacing any selection), continues the
    /// list on the new line. Returns nil for every other change.
    public static func continueListOnEnter(oldText: String, oldSelectionStart: Int, oldSelectionEnd: Int, newText: String, newCursor: Int) -> FormatResult? {
        let old = U16(oldText)
        let start = oldSelectionStart.clamped(0, old.count)
        let end = oldSelectionEnd.clamped(start, old.count)
        let expected = old.sub(0, start) + "\n" + old.sub(end, old.count)
        if newText != expected || newCursor != start + 1 { return nil }
        return continueListAfterEnter(newText, newCursor)
    }

    /// Assumes `cursor` sits just after a freshly inserted newline; inserts the matching list prefix.
    /// Enter on an empty list item exits the list. Returns nil when the line above has no list prefix.
    public static func continueListAfterEnter(_ text: String, _ cursor: Int) -> FormatResult? {
        let t = U16(text)
        let safeCursor = cursor.clamped(0, t.count)
        if safeCursor == 0 || t.units[safeCursor - 1] != U16.newline { return nil }

        let prevLineStart = safeCursor >= 2 ? t.lastIndexOfNewline(before: safeCursor - 2) + 1 : 0
        let prevLine = t.sub(prevLineStart, safeCursor - 1)
        let indent = leadingIndent(prevLine)
        let trimmed = trimStart(prevLine)
        let trimmedNS = trimmed as NSString

        let numberMatch = numberedPrefixRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: trimmedNS.length))
        let prefixLength: Int
        let nextPrefix: String
        var nextNumber: Int?
        if trimmed.hasPrefix(BULLET_PREFIX) || trimmed == "•" {
            prefixLength = trimmed.hasPrefix(BULLET_PREFIX) ? BULLET_PREFIX.utf16.count : 1
            nextPrefix = BULLET_PREFIX
        } else if trimmed.hasPrefix(UNCHECKED_PREFIX) || trimmed == "☐" || trimmed.hasPrefix(CHECKED_PREFIX) || trimmed == "☑" {
            prefixLength = (trimmed.hasPrefix(UNCHECKED_PREFIX) || trimmed.hasPrefix(CHECKED_PREFIX)) ? UNCHECKED_PREFIX.utf16.count : 1
            nextPrefix = UNCHECKED_PREFIX
        } else if let numberMatch {
            prefixLength = numberMatch.range.length
            let n = (Int(trimmedNS.substring(with: numberMatch.range(at: 1))) ?? 0) + 1
            nextNumber = n
            nextPrefix = "\(n). "
        } else {
            return nil
        }
        let content = trimmedNS.substring(from: prefixLength)

        if content.isBlank {
            let newText = t.sub(0, prevLineStart) + indent + t.sub(safeCursor - 1, t.count)
            return FormatResult(text: newText, cursor: safeCursor - trimmedNS.length)
        }

        var newText = t.sub(0, safeCursor) + indent + nextPrefix + t.sub(safeCursor, t.count)
        let newCursor = safeCursor + indent.utf16.count + nextPrefix.utf16.count
        if let nextNumber {
            newText = renumberFollowing(newText, newLineStart: safeCursor, firstNumber: nextNumber + 1)
        }
        return FormatResult(text: newText, cursor: newCursor)
    }

    /// Renumbers the consecutive numbered lines directly below the line starting at `newLineStart`.
    private static func renumberFollowing(_ text: String, newLineStart: Int, firstNumber: Int) -> String {
        let result = NSMutableString(string: text)
        func indexOfNewline(_ from: Int) -> Int {
            let r = result.range(of: "\n", range: NSRange(location: from, length: result.length - from))
            return r.location == NSNotFound ? -1 : r.location
        }
        let found = indexOfNewline(newLineStart)
        let newLineEnd = found == -1 ? result.length : found
        if newLineEnd >= result.length { return text }
        var lineStart = newLineEnd + 1
        var expected = firstNumber
        while lineStart < result.length {
            let nl = indexOfNewline(lineStart)
            let lineEnd = nl == -1 ? result.length : nl
            let line = result.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
            let trimmed = trimStart(line)
            guard let match = numberedRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else { break }
            let prefixStart = lineStart + ((line as NSString).length - (trimmed as NSString).length)
            result.replaceCharacters(in: NSRange(location: prefixStart, length: match.range.length), with: "\(expected). ")
            expected += 1
            let next = indexOfNewline(lineStart)
            if next == -1 { break }
            lineStart = next + 1
        }
        return result as String
    }

    private static func nextNumber(_ textBeforeLine: String) -> Int {
        guard let previous = lines(textBeforeLine).last(where: { !$0.isBlank }) else { return 1 }
        let trimmed = trimStart(previous)
        guard let match = numberedRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else { return 1 }
        return (Int((trimmed as NSString).substring(with: match.range(at: 1))) ?? 0) + 1
    }

    // MARK: - Kotlin string helpers

    /// Kotlin `lines()`: splits on CRLF, LF and CR.
    static func lines(_ text: String) -> [String] {
        var out: [String] = []
        var current: [UInt16] = []
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let u = units[i]
            if u == 0x0A || u == 0x0D {
                out.append(String(decoding: current, as: UTF16.self))
                current.removeAll()
                if u == 0x0D, i + 1 < units.count, units[i + 1] == 0x0A { i += 1 }
            } else {
                current.append(u)
            }
            i += 1
        }
        out.append(String(decoding: current, as: UTF16.self))
        return out
    }

    private static func trimStart(_ s: String) -> String {
        String(s.drop { $0.isWhitespace })
    }

    private static func leadingIndent(_ s: String) -> String {
        String(s.prefix { $0 == " " || $0 == "\t" })
    }

    private static func replaceFirst(_ regex: NSRegularExpression, in s: String) -> String {
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return s }
        return ns.replacingCharacters(in: m.range, with: "")
    }
}

/// UTF-16 view with Kotlin-style index helpers.
private struct U16 {
    static let newline: UInt16 = 0x0A
    let units: [UInt16]

    init(_ s: String) { units = Array(s.utf16) }

    var count: Int { units.count }

    func sub(_ a: Int, _ b: Int) -> String {
        guard a < b else { return "" }
        return String(decoding: units[a..<b], as: UTF16.self)
    }

    /// Kotlin `lastIndexOf('\n', startIndex)`; -1 when not found.
    func lastIndexOfNewline(before start: Int) -> Int {
        var i = min(start, count - 1)
        while i >= 0 {
            if units[i] == U16.newline { return i }
            i -= 1
        }
        return -1
    }

    func indexOfNewline(from start: Int) -> Int? {
        var i = max(start, 0)
        while i < count {
            if units[i] == U16.newline { return i }
            i += 1
        }
        return nil
    }
}
