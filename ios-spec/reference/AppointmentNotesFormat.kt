package com.lifestyle.nestly.ui.appointments

/** Line formats available in the free-form notes & questions editor. */
enum class NoteLineFormat { BULLET, NUMBERED, CHECKBOX }

/**
 * Pure-text helpers for the free-form appointment notes. Checkbox state lives
 * in the text itself ("☐ ask about fever" / "☑ ask about fever") so notes stay
 * plain text in the database while still offering tappable checklist items.
 */
object AppointmentNotesFormat {
    const val BULLET_PREFIX = "• "
    const val UNCHECKED_PREFIX = "☐ "
    const val CHECKED_PREFIX = "☑ "

    private val numberedRegex = Regex("""^(\d+)\.\s+""")
    private val numberedPrefixRegex = Regex("""^(\d+)\.(?:\s+|$)""")
    private val anyPrefixRegex = Regex("""^(•\s+|☐\s+|☑\s+|\d+\.\s+)""")

    data class CheckboxItem(val lineIndex: Int, val text: String, val checked: Boolean)

    data class FormatResult(val text: String, val cursor: Int)

    fun checkboxItems(text: String): List<CheckboxItem> =
        text.lines().mapIndexedNotNull { index, line ->
            val trimmed = line.trimStart()
            when {
                trimmed.startsWith(UNCHECKED_PREFIX) ->
                    CheckboxItem(index, trimmed.removePrefix(UNCHECKED_PREFIX), checked = false)
                trimmed.startsWith(CHECKED_PREFIX) ->
                    CheckboxItem(index, trimmed.removePrefix(CHECKED_PREFIX), checked = true)
                else -> null
            }
        }

    /** Flips ☐ ↔ ☑ on the given line; returns the text unchanged if that line isn't a checkbox. */
    fun toggleCheckbox(text: String, lineIndex: Int): String {
        val lines = text.lines().toMutableList()
        if (lineIndex !in lines.indices) return text
        val line = lines[lineIndex]
        val indent = line.takeWhile { it == ' ' || it == '\t' }
        val trimmed = line.trimStart()
        lines[lineIndex] = when {
            trimmed.startsWith(UNCHECKED_PREFIX) ->
                indent + CHECKED_PREFIX + trimmed.removePrefix(UNCHECKED_PREFIX)
            trimmed.startsWith(CHECKED_PREFIX) ->
                indent + UNCHECKED_PREFIX + trimmed.removePrefix(CHECKED_PREFIX)
            else -> return text
        }
        return lines.joinToString("\n")
    }

    /**
     * Applies [format] to the line containing [cursor], replacing any existing
     * list prefix on that line. Numbered lines continue the sequence of the
     * numbered lines above them.
     */
    fun formatCurrentLine(text: String, cursor: Int, format: NoteLineFormat): FormatResult {
        val safeCursor = cursor.coerceIn(0, text.length)
        val lineStart = text.lastIndexOf('\n', safeCursor - 1) + 1
        val lineEnd = text.indexOf('\n', safeCursor).let { if (it == -1) text.length else it }
        val line = text.substring(lineStart, lineEnd)
        val indent = line.takeWhile { it == ' ' || it == '\t' }
        val content = line.trimStart().replaceFirst(anyPrefixRegex, "")
        val prefix = when (format) {
            NoteLineFormat.BULLET -> BULLET_PREFIX
            NoteLineFormat.CHECKBOX -> UNCHECKED_PREFIX
            NoteLineFormat.NUMBERED -> "${nextNumber(text.substring(0, lineStart))}. "
        }
        val newLine = indent + prefix + content
        val newText = text.substring(0, lineStart) + newLine + text.substring(lineEnd)
        val cursorInLine = (safeCursor - lineStart).coerceIn(0, line.length)
        val newCursor = lineStart + (indent.length + prefix.length +
            (cursorInLine - (line.length - content.length)).coerceAtLeast(0))
            .coerceAtMost(newLine.length)
        return FormatResult(newText, newCursor)
    }

    /**
     * If the change from the old value to the new value is exactly one "\n"
     * inserted (replacing any selection), continues the list on the new line
     * and returns the adjusted value. Returns null for every other change, so
     * callers can fall back to accepting the new value as-is.
     */
    fun continueListOnEnter(
        oldText: String,
        oldSelectionStart: Int,
        oldSelectionEnd: Int,
        newText: String,
        newCursor: Int,
    ): FormatResult? {
        val start = oldSelectionStart.coerceIn(0, oldText.length)
        val end = oldSelectionEnd.coerceIn(start, oldText.length)
        val expected = oldText.substring(0, start) + "\n" + oldText.substring(end)
        if (newText != expected || newCursor != start + 1) return null
        return continueListAfterEnter(newText, newCursor)
    }

    /**
     * Assumes [cursor] sits just after a freshly inserted newline. If the line
     * above is a bullet / numbered / checkbox line, inserts the matching prefix
     * for the new line (numbered lines increment, and any numbered lines below
     * are renumbered; checkboxes always start unchecked). Pressing Enter on an
     * empty list item exits the list instead of perpetuating an empty prefix.
     * Returns null when the line above has no list prefix.
     */
    fun continueListAfterEnter(text: String, cursor: Int): FormatResult? {
        val safeCursor = cursor.coerceIn(0, text.length)
        if (safeCursor == 0 || text[safeCursor - 1] != '\n') return null

        val prevLineStart = if (safeCursor >= 2) text.lastIndexOf('\n', safeCursor - 2) + 1 else 0
        val prevLine = text.substring(prevLineStart, safeCursor - 1)
        val indent = prevLine.takeWhile { it == ' ' || it == '\t' }
        val trimmed = prevLine.trimStart()

        val numberMatch = numberedPrefixRegex.find(trimmed)
        val prefixLength: Int
        val content: String
        val nextPrefix: String
        val nextNumber: Int?
        when {
            trimmed.startsWith(BULLET_PREFIX) || trimmed == "•" -> {
                prefixLength = if (trimmed.startsWith(BULLET_PREFIX)) BULLET_PREFIX.length else 1
                content = trimmed.substring(prefixLength)
                nextPrefix = BULLET_PREFIX
                nextNumber = null
            }
            trimmed.startsWith(UNCHECKED_PREFIX) || trimmed == "☐" ||
                trimmed.startsWith(CHECKED_PREFIX) || trimmed == "☑" -> {
                prefixLength = when {
                    trimmed.startsWith(UNCHECKED_PREFIX) || trimmed.startsWith(CHECKED_PREFIX) -> UNCHECKED_PREFIX.length
                    else -> 1
                }
                content = trimmed.substring(prefixLength)
                // A fresh item is never pre-checked, even below a checked one.
                nextPrefix = UNCHECKED_PREFIX
                nextNumber = null
            }
            numberMatch != null -> {
                prefixLength = numberMatch.value.length
                content = trimmed.substring(prefixLength)
                nextNumber = (numberMatch.groupValues[1].toIntOrNull() ?: 0) + 1
                nextPrefix = "$nextNumber. "
            }
            else -> return null
        }

        if (content.isBlank()) {
            // Enter on an empty list item: drop the prefix and stay on a plain line.
            val newText = text.substring(0, prevLineStart) + indent + text.substring(safeCursor - 1)
            return FormatResult(newText, safeCursor - trimmed.length)
        }

        var newText = text.substring(0, safeCursor) + indent + nextPrefix + text.substring(safeCursor)
        val newCursor = safeCursor + indent.length + nextPrefix.length
        if (nextNumber != null) {
            newText = renumberFollowing(newText, newLineStart = safeCursor, firstNumber = nextNumber + 1)
        }
        return FormatResult(newText, newCursor)
    }

    /** Renumbers the consecutive numbered lines directly below the line starting at [newLineStart]. */
    private fun renumberFollowing(text: String, newLineStart: Int, firstNumber: Int): String {
        val result = StringBuilder(text)
        val newLineEnd = result.indexOf("\n", newLineStart).let { if (it == -1) result.length else it }
        if (newLineEnd >= result.length) return text
        var lineStart = newLineEnd + 1
        var expected = firstNumber
        while (lineStart < result.length) {
            val lineEnd = result.indexOf("\n", lineStart).let { if (it == -1) result.length else it }
            val line = result.substring(lineStart, lineEnd)
            val trimmed = line.trimStart()
            val match = numberedRegex.find(trimmed) ?: break
            val prefixStart = lineStart + (line.length - trimmed.length)
            result.replace(prefixStart, prefixStart + match.value.length, "$expected. ")
            expected++
            val nextNewline = result.indexOf("\n", lineStart)
            if (nextNewline == -1) break
            lineStart = nextNewline + 1
        }
        return result.toString()
    }

    private fun nextNumber(textBeforeLine: String): Int {
        // Only an immediately preceding (non-blank) numbered line continues a
        // sequence; a numbered line buried above bullets/paragraphs starts over.
        val previous = textBeforeLine.lines().lastOrNull { it.isNotBlank() } ?: return 1
        return (numberedRegex.find(previous.trimStart())?.groupValues?.get(1)?.toIntOrNull() ?: 0) + 1
    }
}
