@testable import NestlyCore
import XCTest

final class PhotoPromptTests: XCTestCase {
    let birth = LocalDate.of(2026, 1, 15)

    func testNoPromptTheDayBeforeOneMonth() {
        XCTAssertNil(PhotoPrompt.current(birth: birth, today: birth.plusMonths(1).minusDays(1)))
    }

    func testEveryMonthOfTheFirstYear() {
        for month in 1...12 {
            let today = birth.plusMonths(month)
            let milestone = PhotoPrompt.current(birth: birth, today: today)
            XCTAssertEqual(milestone?.id, "m\(month)", "month \(month)")
            XCTAssertEqual(milestone?.date, today)
            let dayBefore = today.minusDays(1)
            if month == 1 {
                XCTAssertNil(PhotoPrompt.current(birth: birth, today: dayBefore))
            } else {
                XCTAssertEqual(PhotoPrompt.current(birth: birth, today: dayBefore)?.id, "m\(month - 1)")
            }
        }
        XCTAssertEqual(PhotoPrompt.current(birth: birth, today: birth.plusMonths(8))?.phrase, "8 months")
    }

    func testTwelveMonthsIsTheFirstBirthdayAndTheSecondBirthdayIsNext() {
        let first = PhotoPrompt.current(birth: birth, today: birth.plusMonths(12))
        XCTAssertEqual(first?.id, "m12")
        XCTAssertEqual(first?.date, birth.plusYears(1))

        let stillFirst = PhotoPrompt.current(birth: birth, today: birth.plusMonths(12).plusDays(1))
        XCTAssertEqual(stillFirst?.id, "m12")

        let second = PhotoPrompt.current(birth: birth, today: birth.plusYears(2))
        XCTAssertEqual(second?.id, "y2")
        XCTAssertEqual(second?.phrase, "2 years")
        XCTAssertNotEqual(second?.id, "m12")
    }

    func testDismissHidesThisAgeUntilTheNextOne() {
        let during = birth.plusMonths(8)
        XCTAssertNil(PhotoPrompt.due(birth: birth, photoUpdatedOn: nil, dismissedMilestoneId: "m8", today: during))

        let next = birth.plusMonths(9)
        XCTAssertEqual(PhotoPrompt.due(birth: birth, photoUpdatedOn: nil, dismissedMilestoneId: "m8", today: next)?.id, "m9")
    }

    func testPhotoOnTheMilestoneDayIsCurrent() {
        let milestone = birth.plusMonths(8)
        let today = birth.plusMonths(8).plusDays(10)
        XCTAssertNil(PhotoPrompt.due(birth: birth, photoUpdatedOn: milestone, dismissedMilestoneId: nil, today: today))
        XCTAssertEqual(PhotoPrompt.due(birth: birth, photoUpdatedOn: milestone.minusDays(1), dismissedMilestoneId: nil, today: today)?.id, "m8")
        XCTAssertEqual(PhotoPrompt.due(birth: birth, photoUpdatedOn: nil, dismissedMilestoneId: nil, today: today)?.id, "m8")
    }

    func testSelectedChildWinsAndOtherwiseTheLatestMilestone() {
        let older = PhotoPrompt.Child(id: "older", name: "Ada", birthDate: birth)
        let younger = PhotoPrompt.Child(id: "younger", name: "Bea", birthDate: birth.plusMonths(4).plusDays(10))
        let today = birth.plusMonths(6).plusDays(5)

        let selectedYounger = PhotoPrompt.choose([older, younger], selectedId: "younger", today: today)
        XCTAssertEqual(selectedYounger?.profileId, "younger")
        XCTAssertEqual(selectedYounger?.milestone.id, "m1")

        let latest = PhotoPrompt.choose([younger, older], selectedId: "nobody", today: today)
        XCTAssertEqual(latest?.profileId, "older")
        XCTAssertEqual(latest?.milestone.id, "m6")
    }

    func testChildWithoutABirthDateIsSkipped() {
        let child = PhotoPrompt.Child(id: "a", name: "No Date", birthDate: nil)
        XCTAssertNil(PhotoPrompt.choose([child], selectedId: "a", today: birth.plusYears(2)))
    }
}
