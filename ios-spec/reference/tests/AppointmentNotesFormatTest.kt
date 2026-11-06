package com.lifestyle.nestly.ui.appointments

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppointmentNotesFormatTest {

    @Test
    fun checkboxItemsParsesCheckedAndUnchecked() {
        val items = AppointmentNotesFormat.checkboxItems("☐ Ask about fever\nplain note\n☑ Bring records")
        assertEquals(2, items.size)
        assertEquals(AppointmentNotesFormat.CheckboxItem(0, "Ask about fever", false), items[0])
        assertEquals(AppointmentNotesFormat.CheckboxItem(2, "Bring records", true), items[1])
    }

    @Test
    fun toggleCheckboxFlipsBothWays() {
        val text = "☐ Ask about fever\n☑ Done thing"
        val toggled = AppointmentNotesFormat.toggleCheckbox(text, 0)
        assertEquals("☑ Ask about fever\n☑ Done thing", toggled)
        assertEquals(text, AppointmentNotesFormat.toggleCheckbox(toggled, 0))
        assertEquals(text, AppointmentNotesFormat.toggleCheckbox(text, 1).let {
            AppointmentNotesFormat.toggleCheckbox(it, 1)
        })
    }

    @Test
    fun toggleCheckboxIgnoresPlainLines() {
        val text = "just a note"
        assertEquals(text, AppointmentNotesFormat.toggleCheckbox(text, 0))
        assertEquals(text, AppointmentNotesFormat.toggleCheckbox(text, 5))
    }

    @Test
    fun bulletFormatsCurrentLine() {
        val result = AppointmentNotesFormat.formatCurrentLine("Ask about fever", 4, NoteLineFormat.BULLET)
        assertEquals("• Ask about fever", result.text)
        assertTrue(result.cursor in 0..result.text.length)
    }

    @Test
    fun checkboxReplacesBulletPrefixInsteadOfStacking() {
        val result = AppointmentNotesFormat.formatCurrentLine("• Ask about fever", 5, NoteLineFormat.CHECKBOX)
        assertEquals("☐ Ask about fever", result.text)
    }

    @Test
    fun numberedContinuesSequence() {
        val text = "1. First\n2. Second\nThird"
        val result = AppointmentNotesFormat.formatCurrentLine(text, text.length, NoteLineFormat.NUMBERED)
        assertEquals("1. First\n2. Second\n3. Third", result.text)
    }

    @Test
    fun numberedStartsAtOneWithoutPreviousNumbers() {
        val result = AppointmentNotesFormat.formatCurrentLine("Only line", 2, NoteLineFormat.NUMBERED)
        assertEquals("1. Only line", result.text)
    }

    @Test
    fun formatOnlyTouchesTheCursorLine() {
        val text = "first line\nsecond line"
        val result = AppointmentNotesFormat.formatCurrentLine(text, 2, NoteLineFormat.BULLET)
        assertEquals("• first line\nsecond line", result.text)
    }

    @Test
    fun enterContinuesBullet() {
        val text = "• First\n"
        val result = AppointmentNotesFormat.continueListAfterEnter(text, text.length)
        assertEquals("• First\n• ", result?.text)
        assertEquals(result?.text?.length, result?.cursor)
    }

    @Test
    fun enterContinuesCheckboxAsUnchecked() {
        val text = "☑ Done thing\n"
        val result = AppointmentNotesFormat.continueListAfterEnter(text, text.length)
        assertEquals("☑ Done thing\n☐ ", result?.text)
    }

    @Test
    fun enterIncrementsNumberedAndRenumbersFollowing() {
        val text = "1. First\n\n2. Second"
        // Cursor sits on the blank line created by pressing Enter after "1. First".
        val result = AppointmentNotesFormat.continueListAfterEnter(text, "1. First\n".length)
        assertEquals("1. First\n2. \n3. Second", result?.text)
        assertEquals("1. First\n2. ".length, result?.cursor)
    }

    @Test
    fun enterSplitsLineCarryingRemainderIntoNewItem() {
        val text = "• FooBar"
        val rawAfterEnter = "• Foo\nBar"
        val result = AppointmentNotesFormat.continueListAfterEnter(rawAfterEnter, "• Foo\n".length)
        assertEquals("• Foo\n• Bar", result?.text)
    }

    @Test
    fun enterOnEmptyListItemExitsList() {
        val text = "• First\n• \n"
        val result = AppointmentNotesFormat.continueListAfterEnter(text, text.length)
        assertEquals("• First\n\n", result?.text)
        assertEquals(result?.text?.length, result?.cursor)

        val numbered = "1. First\n2. \n"
        assertEquals(
            "1. First\n\n",
            AppointmentNotesFormat.continueListAfterEnter(numbered, numbered.length)?.text,
        )
    }

    @Test
    fun enterOnPlainLineDoesNothing() {
        val text = "just a note\n"
        assertEquals(null, AppointmentNotesFormat.continueListAfterEnter(text, text.length))
        assertEquals(null, AppointmentNotesFormat.continueListAfterEnter("no newline", 4))
    }

    @Test
    fun continueListOnEnterOnlyFiresForSingleNewlineInsertion() {
        val result = AppointmentNotesFormat.continueListOnEnter(
            oldText = "• First",
            oldSelectionStart = "• First".length,
            oldSelectionEnd = "• First".length,
            newText = "• First\n",
            newCursor = "• First\n".length,
        )
        assertEquals("• First\n• ", result?.text)

        // Ordinary typing, deletions and multi-char pastes are left alone.
        assertEquals(
            null,
            AppointmentNotesFormat.continueListOnEnter("• First", 7, 7, "• Firstx", 8),
        )
        assertEquals(
            null,
            AppointmentNotesFormat.continueListOnEnter("• First", 7, 7, "• Firs", 6),
        )
        assertEquals(
            null,
            AppointmentNotesFormat.continueListOnEnter("• First", 7, 7, "• First\n\n", 9),
        )
    }

    @Test
    fun numberedFormatRestartsAfterNonNumberedLine() {
        val text = "1. First\n• a bullet\nNew item"
        val result = AppointmentNotesFormat.formatCurrentLine(text, text.length, NoteLineFormat.NUMBERED)
        assertEquals("1. First\n• a bullet\n1. New item", result.text)
    }
}
