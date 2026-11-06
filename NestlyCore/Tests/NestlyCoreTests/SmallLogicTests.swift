@testable import NestlyCore
import XCTest

final class ActivityFiltersTests: XCTestCase {
    private func row(_ type: ActivityType = .BOTTLE_FEED, note: String? = nil, photo: String? = nil) -> ActivityEntity {
        activity(type: type, start: 0, note: note, photo: photo, bottle: type == .BOTTLE_FEED ? BottleDetails(.BREAST_MILK, totalMl: 100) : nil)
    }

    func testEmptyFiltersMatchEverything() {
        XCTAssertTrue(ActivityFilters.matches(row(), []))
        XCTAssertTrue(ActivityFilters.matches(row(.SLEEP), []))
    }

    func testTypeFilterRestricts() {
        XCTAssertTrue(ActivityFilters.matches(row(), [.FEED]))
        XCTAssertFalse(ActivityFilters.matches(row(.DIAPER), [.FEED]))
        XCTAssertTrue(ActivityFilters.matches(row(.DIAPER), [.DIAPER]))
        XCTAssertTrue(ActivityFilters.matches(row(.MEDICAL), [.HEALTH]))
    }

    func testNotesAndPhotosRequireContent() {
        XCTAssertFalse(ActivityFilters.matches(row(), [.NOTES]))
        XCTAssertTrue(ActivityFilters.matches(row(note: "hi"), [.NOTES]))
        XCTAssertFalse(ActivityFilters.matches(row(note: "hi"), [.PHOTOS]))
        XCTAssertTrue(ActivityFilters.matches(row(note: "hi", photo: "/p.jpg"), [.PHOTOS, .NOTES]))
    }

    func testTypePlusNotesMustSatisfyBoth() {
        XCTAssertFalse(ActivityFilters.matches(row(), [.FEED, .NOTES]))
        XCTAssertTrue(ActivityFilters.matches(row(note: "x"), [.FEED, .NOTES]))
        XCTAssertFalse(ActivityFilters.matches(row(.PUMP, note: "x"), [.FEED, .NOTES]))
    }
}

final class AppointmentNotesFormatTests: XCTestCase {
    typealias F = AppointmentNotesFormat

    func testCheckboxItemsParsesCheckedAndUnchecked() {
        let items = F.checkboxItems("☐ Ask about fever\nplain note\n☑ Bring records")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0], F.CheckboxItem(lineIndex: 0, text: "Ask about fever", checked: false))
        XCTAssertEqual(items[1], F.CheckboxItem(lineIndex: 2, text: "Bring records", checked: true))
    }

    func testToggleCheckboxFlipsBothWays() {
        let text = "☐ Ask about fever\n☑ Done thing"
        let toggled = F.toggleCheckbox(text, 0)
        XCTAssertEqual(toggled, "☑ Ask about fever\n☑ Done thing")
        XCTAssertEqual(F.toggleCheckbox(toggled, 0), text)
        XCTAssertEqual(F.toggleCheckbox(F.toggleCheckbox(text, 1), 1), text)
    }

    func testToggleCheckboxIgnoresPlainLines() {
        XCTAssertEqual(F.toggleCheckbox("just a note", 0), "just a note")
        XCTAssertEqual(F.toggleCheckbox("just a note", 5), "just a note")
    }

    func testBulletFormatsCurrentLine() {
        let result = F.formatCurrentLine("Ask about fever", 4, .BULLET)
        XCTAssertEqual(result.text, "• Ask about fever")
        XCTAssertTrue((0...result.text.utf16.count).contains(result.cursor))
    }

    func testCheckboxReplacesBulletPrefixInsteadOfStacking() {
        XCTAssertEqual(F.formatCurrentLine("• Ask about fever", 5, .CHECKBOX).text, "☐ Ask about fever")
    }

    func testNumberedContinuesSequence() {
        let text = "1. First\n2. Second\nThird"
        XCTAssertEqual(F.formatCurrentLine(text, text.utf16.count, .NUMBERED).text, "1. First\n2. Second\n3. Third")
    }

    func testNumberedStartsAtOneWithoutPreviousNumbers() {
        XCTAssertEqual(F.formatCurrentLine("Only line", 2, .NUMBERED).text, "1. Only line")
    }

    func testFormatOnlyTouchesTheCursorLine() {
        XCTAssertEqual(F.formatCurrentLine("first line\nsecond line", 2, .BULLET).text, "• first line\nsecond line")
    }

    func testEnterContinuesBullet() {
        let text = "• First\n"
        let result = F.continueListAfterEnter(text, text.utf16.count)
        XCTAssertEqual(result?.text, "• First\n• ")
        XCTAssertEqual(result?.text.utf16.count, result?.cursor)
    }

    func testEnterContinuesCheckboxAsUnchecked() {
        let text = "☑ Done thing\n"
        XCTAssertEqual(F.continueListAfterEnter(text, text.utf16.count)?.text, "☑ Done thing\n☐ ")
    }

    func testEnterIncrementsNumberedAndRenumbersFollowing() {
        let text = "1. First\n\n2. Second"
        let result = F.continueListAfterEnter(text, "1. First\n".utf16.count)
        XCTAssertEqual(result?.text, "1. First\n2. \n3. Second")
        XCTAssertEqual(result?.cursor, "1. First\n2. ".utf16.count)
    }

    func testEnterSplitsLineCarryingRemainderIntoNewItem() {
        XCTAssertEqual(F.continueListAfterEnter("• Foo\nBar", "• Foo\n".utf16.count)?.text, "• Foo\n• Bar")
    }

    func testEnterOnEmptyListItemExitsList() {
        let text = "• First\n• \n"
        let result = F.continueListAfterEnter(text, text.utf16.count)
        XCTAssertEqual(result?.text, "• First\n\n")
        XCTAssertEqual(result?.text.utf16.count, result?.cursor)

        let numbered = "1. First\n2. \n"
        XCTAssertEqual(F.continueListAfterEnter(numbered, numbered.utf16.count)?.text, "1. First\n\n")
    }

    func testEnterOnPlainLineDoesNothing() {
        let text = "just a note\n"
        XCTAssertNil(F.continueListAfterEnter(text, text.utf16.count))
        XCTAssertNil(F.continueListAfterEnter("no newline", 4))
    }

    func testContinueListOnEnterOnlyFiresForSingleNewlineInsertion() {
        let result = F.continueListOnEnter(oldText: "• First", oldSelectionStart: 7, oldSelectionEnd: 7, newText: "• First\n", newCursor: 8)
        XCTAssertEqual(result?.text, "• First\n• ")
        XCTAssertNil(F.continueListOnEnter(oldText: "• First", oldSelectionStart: 7, oldSelectionEnd: 7, newText: "• Firstx", newCursor: 8))
        XCTAssertNil(F.continueListOnEnter(oldText: "• First", oldSelectionStart: 7, oldSelectionEnd: 7, newText: "• Firs", newCursor: 6))
        XCTAssertNil(F.continueListOnEnter(oldText: "• First", oldSelectionStart: 7, oldSelectionEnd: 7, newText: "• First\n\n", newCursor: 9))
    }

    func testNumberedFormatRestartsAfterNonNumberedLine() {
        let text = "1. First\n• a bullet\nNew item"
        XCTAssertEqual(F.formatCurrentLine(text, text.utf16.count, .NUMBERED).text, "1. First\n• a bullet\n1. New item")
    }

    func testOffsetsAreUtf16() {
        // An emoji is two UTF-16 units; the cursor after it must land on the right line.
        let text = "👶 first\nsecond"
        XCTAssertEqual(F.formatCurrentLine(text, text.utf16.count, .BULLET).text, "👶 first\n• second")
    }
}

final class AppointmentReminderLogicTests: XCTestCase {
    let now: EpochMs = 1_700_000_000_000
    var startsAt: EpochMs { now + 3 * 24 * 60 * 60_000 }

    func testNoReminderSchedulesNothing() {
        XCTAssertNil(AppointmentReminderLogic.fireAtMs(startsAt, .NONE, now: now))
    }

    func testAtTimeFiresAtStart() {
        XCTAssertEqual(AppointmentReminderLogic.fireAtMs(startsAt, .AT_TIME, now: now), startsAt)
    }

    func testOneHourBeforeSubtractsHour() {
        XCTAssertEqual(AppointmentReminderLogic.fireAtMs(startsAt, .ONE_HOUR, now: now), startsAt - 60 * 60_000)
    }

    func testOneDayBeforeSubtractsDay() {
        XCTAssertEqual(AppointmentReminderLogic.fireAtMs(startsAt, .ONE_DAY, now: now), startsAt - 24 * 60 * 60_000)
    }

    func testPastAppointmentSchedulesNothing() {
        XCTAssertNil(AppointmentReminderLogic.fireAtMs(now - 60_000, .ONE_HOUR, now: now))
        XCTAssertNil(AppointmentReminderLogic.fireAtMs(now, .AT_TIME, now: now))
    }

    func testLeadAlreadyPassedFiresAsCatchUp() {
        XCTAssertEqual(AppointmentReminderLogic.fireAtMs(now + 30 * 60_000, .ONE_DAY, now: now), now + 60_000)
    }

    func testCatchUpNeverFiresAfterAppointment() {
        let imminent = now + 30_000
        XCTAssertEqual(AppointmentReminderLogic.fireAtMs(imminent, .ONE_DAY, now: now), imminent)
    }

    func testRequestCodesAreNamespacedPerAppointment() {
        XCTAssertEqual(AppointmentReminderLogic.requestCode("abc"), AppointmentReminderLogic.requestCode("abc"))
        XCTAssertNotEqual(AppointmentReminderLogic.requestCode("abc"), AppointmentReminderLogic.requestCode("def"))
        XCTAssertNotEqual(javaHashCode("abc"), AppointmentReminderLogic.requestCode("abc"))
        XCTAssertEqual(javaHashCode("abc"), 96354)
    }
}

final class DailyDoseTests: XCTestCase {
    let today = LocalDate.of(2026, 11, 4)
    var startOfToday: EpochMs { today.startOfDayMs(chicago) }
    var startOfTomorrow: EpochMs { today.plusDays(1).startOfDayMs(chicago) }

    private func at(_ h: Int, _ m: Int = 0, _ date: LocalDate? = nil) -> EpochMs { (date ?? today).atTimeMs(h, m, zone: chicago) }

    private func entry(_ start: EpochMs, _ type: ActivityType = .VITAMIN_D, deleted: Bool = false) -> ActivityEntity {
        activity(id: "a\(start)\(type)", type: type, start: start, timeZone: chicago.identifier, deletedAt: deleted ? start : nil)
    }

    private func givenAt(_ entries: ActivityEntity...) -> EpochMs? {
        DailyDose.givenAt(entries, startOfToday: startOfToday, startOfTomorrow: startOfTomorrow)
    }

    func testNotGivenWhenNothingLogged() { XCTAssertNil(givenAt()) }

    func testYesterdaysDoseDoesNotCountToday() { XCTAssertNil(givenAt(entry(at(23, 59, today.minusDays(1))))) }

    func testDoseRightAtMidnightCountsForToday() { XCTAssertEqual(givenAt(entry(startOfToday)), startOfToday) }

    func testTomorrowsDoseDoesNotCountToday() { XCTAssertNil(givenAt(entry(startOfTomorrow))) }

    func testEarliestDoseTodayIsReported() { XCTAssertEqual(givenAt(entry(at(20)), entry(at(8, 12))), at(8, 12)) }

    func testDeletedAndOtherTypesAreIgnored() {
        XCTAssertNil(givenAt(entry(at(9), deleted: true), entry(at(10), .MEDICAL)))
    }
}

final class DefaultBottleAmountTests: XCTestCase {
    func testOffersToSetDefaultWhenNoneStored() {
        XCTAssertTrue(shouldOfferDefaultBottleUpdate(isEditing: false, newMl: 120, defaultMl: nil))
    }

    func testOffersToUpdateDefaultWhenAmountChanged() {
        XCTAssertTrue(shouldOfferDefaultBottleUpdate(isEditing: false, newMl: 150, defaultMl: 120))
    }

    func testNoOfferWhenAmountMatchesDefault() {
        XCTAssertFalse(shouldOfferDefaultBottleUpdate(isEditing: false, newMl: 120, defaultMl: 120))
    }

    func testNoOfferForOzRoundingDrift() {
        XCTAssertFalse(shouldOfferDefaultBottleUpdate(isEditing: false, newMl: 120.06, defaultMl: 120))
    }

    func testNoOfferWhenEditingExistingEntryOrClearingAmount() {
        XCTAssertFalse(shouldOfferDefaultBottleUpdate(isEditing: true, newMl: 150, defaultMl: 120))
        XCTAssertFalse(shouldOfferDefaultBottleUpdate(isEditing: false, newMl: nil, defaultMl: 120))
    }
}

final class QuickBottleLogTests: XCTestCase {
    func testPrefersStoredDefaultOverLastAmount() { XCTAssertEqual(resolveQuickBottleMl(defaultMl: 150, lastMl: 120), 150) }

    func testFallsBackToLastAmountWhenNoDefaultSet() { XCTAssertEqual(resolveQuickBottleMl(defaultMl: nil, lastMl: 120), 120) }

    func testNoAmountWhenNeitherDefaultNorLastExists() { XCTAssertNil(resolveQuickBottleMl(defaultMl: nil, lastMl: nil)) }

    func testOnlyNotAuthenticatedCountsAsSignedOut() { XCTAssertEqual(sessionWaitOutcome(.signedOut), .SIGNED_OUT) }

    func testTransientSessionStatesAreNotSignedOut() {
        XCTAssertEqual(sessionWaitOutcome(.restoring), .NOT_READY)
        XCTAssertEqual(sessionWaitOutcome(.refreshFailed), .NOT_READY)
    }

    func testSessionWaitTimeoutIsNotSignedOut() { XCTAssertEqual(sessionWaitOutcome(nil), .NOT_READY) }

    func testIgnoresNonPositiveAmounts() {
        XCTAssertEqual(resolveQuickBottleMl(defaultMl: 0, lastMl: 120), 120)
        XCTAssertNil(resolveQuickBottleMl(defaultMl: nil, lastMl: 0))
        XCTAssertNil(resolveQuickBottleMl(defaultMl: -5, lastMl: nil))
    }
}
