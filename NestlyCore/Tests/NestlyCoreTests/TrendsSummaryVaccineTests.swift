@testable import NestlyCore
import XCTest

final class TrendsAggregatorTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!
    let day0 = LocalDate.of(2026, 10, 1)

    private func ms(_ day: LocalDate, _ hour: Int = 12) -> EpochMs { day.atTimeMs(hour, 0, zone: utc) }

    private func bottle(_ day: LocalDate, _ ml: Double) -> ActivityEntity {
        activity(id: "b\(ml)\(day)", type: .BOTTLE_FEED, start: ms(day), bottle: BottleDetails(.BREAST_MILK, breastMilkMl: ml, totalMl: ml))
    }

    private func pump(_ day: LocalDate, _ ml: Double) -> ActivityEntity {
        activity(id: "p\(ml)\(day)", profileId: nil, type: .PUMP, start: ms(day), pump: PumpDetails(durationSec: 600, totalMl: ml))
    }

    private func diaper(_ day: LocalDate) -> ActivityEntity {
        activity(id: "d\(day)", type: .DIAPER, start: ms(day), diaper: DiaperDetails(.WET))
    }

    private func sleep(_ id: String, _ start: EpochMs, _ end: EpochMs) -> ActivityEntity {
        activity(id: id, type: .SLEEP, start: start, end: end)
    }

    private func compute(_ metric: TrendMetric, _ entries: [ActivityEntity], days: Int = 7) -> MetricResult {
        TrendsAggregator.compute(metric, entries, from: day0, days: days, zone: utc)
    }

    func testSevenDayAveragesAndBarCounts() {
        let entries = [
            bottle(day0, 150), bottle(day0.plusDays(1), 100), pump(day0, 80), diaper(day0), diaper(day0.plusDays(2)),
            diaper(day0).with { $0.id = "d2" },
        ]
        let sessions = compute(.FEED_SESSIONS, entries)
        XCTAssertEqual(sessions.value, 2.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(sessions.days.count, 7)

        let bottlefed = compute(.AMOUNT_BOTTLEFED, entries)
        XCTAssertEqual(bottlefed.value, 250.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(bottlefed.days[0].total, 150)
        XCTAssertEqual(bottlefed.days[1].total, 100)
        XCTAssertEqual(bottlefed.days[2].total, 0)
        XCTAssertEqual(bottlefed.breakdown.map(\.series), [.BREAST_MILK])

        XCTAssertEqual(compute(.BOTTLE_SIZE, entries).value, 125, accuracy: 1e-9)
        XCTAssertEqual(compute(.AMOUNT_PUMPED, entries).value, 80.0 / 7, accuracy: 1e-9)

        let diapers = compute(.TOTAL_DIAPERS, entries)
        XCTAssertEqual(diapers.sampleCount, 3)
        XCTAssertEqual(diapers.value, 3.0 / 7, accuracy: 1e-9)
        XCTAssertEqual(diapers.days[0].total, 2)
        XCTAssertEqual(compute(.NIGHT_DIAPERS, entries).value, 0)
    }

    func testOvernightSleepSplitsAcrossDaysAndBands() {
        let entries = [sleep("s", ms(day0, 21), ms(day0.plusDays(1), 7))]
        let total = compute(.TOTAL_SLEEP, entries, days: 2)
        XCTAssertEqual(total.days[0].total, 3 * 3600)
        XCTAssertEqual(total.days[1].total, 7 * 3600)
        XCTAssertEqual(total.value, 5 * 3600)
        XCTAssertEqual(compute(.DAY_SLEEP, entries, days: 2).days[1].total, 3600)
        XCTAssertEqual(compute(.NIGHT_SLEEP, entries, days: 2).days.reduce(0) { $0 + $1.total }, 9 * 3600)
    }

    func testComboFeedCountsAsOneSessionAndGapsAverage() {
        let combo = [
            bottle(day0, 60).with { $0.id = "c1"; $0.comboGroupId = "g" },
            bottle(day0, 0).with { $0.id = "c2"; $0.type = .BREASTFEED; $0.bottle = nil; $0.comboGroupId = "g" },
        ]
        let later = bottle(day0, 90).with { $0.id = "late"; $0.startTime = ms(day0, 15) }
        let sessions = compute(.FEED_SESSIONS, combo + [later])
        XCTAssertEqual(sessions.sampleCount, 2)
        XCTAssertEqual(sessions.breakdown.map(\.series), [.BOTTLE, .COMBO])
        XCTAssertEqual(compute(.TIME_BETWEEN_FEEDS, combo + [later]).value, 3 * 3600)
    }

    func testTrendsUiText() {
        XCTAssertEqual(TrendMetric.FEED_SESSIONS.summary(6.5, .DEFAULT), "6.5 sessions per day")
        XCTAssertEqual(TrendMetric.AMOUNT_BOTTLEFED.summary(980, .DEFAULT), "980 mL per day")
        XCTAssertEqual(TrendMetric.BF_LENGTH.summary(12_600, .DEFAULT), "3h 30m average")
        XCTAssertEqual(TrendMetric.FEED_SESSIONS.comparison(-1, .FOURTEEN_DAYS), "Fewer sessions than the previous 14 days")
        XCTAssertEqual(TrendMetric.BF_LENGTH.comparison(5, .ONE_DAY), "Longer than the previous day")
        XCTAssertFalse(TrendMetric.FEED_SESSIONS.isMeaningful(0.04))
        XCTAssertTrue(TrendMetric.AMOUNT_PUMPED.isMeaningful(-2))
    }
}

final class SummaryTests: XCTestCase {
    let hour: EpochMs = 3_600_000
    var now: EpochMs { 100 * hour }
    var startOfToday: EpochMs { now - 10 * hour }

    var entries: [ActivityEntity] {
        [
            activity(id: "b1", type: .BOTTLE_FEED, start: now - 2 * hour, bottle: BottleDetails(.BREAST_MILK, breastMilkMl: 120, totalMl: 120)),
            activity(id: "b2", type: .BOTTLE_FEED, start: now - 12 * hour, bottle: BottleDetails(.FORMULA, formulaMl: 90, totalMl: 90)),
            activity(id: "b3", type: .BOTTLE_FEED, start: now - 30 * hour, bottle: BottleDetails(.FORMULA, formulaMl: 60, totalMl: 60)),
            activity(id: "d1", type: .DIAPER, start: now - hour, diaper: DiaperDetails(.MIXED)),
            activity(id: "d2", type: .DIAPER, start: now - 3 * hour, diaper: DiaperDetails(.WET), deletedAt: now - 3 * hour),
        ]
    }

    func testTodayCountsOnlyEntriesSinceMidnight() {
        let lines = Summary.summarize(entries, from: startOfToday, to: now + 1)
        XCTAssertEqual(lines.map(\.type), [.BOTTLE_FEED, .DIAPER])
        XCTAssertEqual(lines[0].count, 1)
        XCTAssertEqual(lines[0].details, ["120 mL total", "120 mL breast milk"])
        XCTAssertEqual(lines[1].details, ["1 wet, 1 dirty"])
    }

    func testLast24HoursIncludesYesterdayEvening() {
        let bottle = Summary.summarize(entries, from: now - 24 * hour, to: now + 1).first { $0.type == .BOTTLE_FEED }!
        XCTAssertEqual(bottle.count, 2)
        XCTAssertEqual(bottle.details, ["210 mL total", "120 mL breast milk", "90 mL formula"])
    }

    func testDeletedEntriesAreIgnored() {
        XCTAssertEqual(Summary.summarize(entries, from: startOfToday, to: now + 1).first { $0.type == .DIAPER }?.count, 1)
    }
}

final class VaccineScheduleTests: XCTestCase {
    let birth = LocalDate.of(2026, 1, 1)
    let utc = TimeZone(identifier: "UTC")!

    private func entry(_ id: String, _ date: LocalDate, _ vaccines: String...) -> ActivityEntity {
        activity(id: id, familyId: "family", profileId: "child", type: .VACCINE, start: date.startOfDayMs(utc), vaccine: VaccineDetails(vaccines))
    }

    private func statuses(_ today: LocalDate, _ entries: ActivityEntity..., birthDate: LocalDate?? = .none) -> [DoseStatus] {
        let b: LocalDate? = birthDate ?? birth
        return VaccineSchedule.doseStatuses(b, entries, today: today, zone: utc)
    }

    private func dose(_ list: [DoseStatus], _ key: String) -> DoseStatus { list.first { $0.dose.key == key }! }

    func testScheduleCoversCdcSeriesThroughSixYears() {
        let counts = Dictionary(grouping: VaccineSchedule.doses, by: \.vaccineName).mapValues(\.count)
        XCTAssertEqual(counts[VaccineSchedule.HEP_B], 3)
        XCTAssertEqual(counts[VaccineSchedule.DTAP], 5)
        XCTAssertEqual(counts[VaccineSchedule.HIB], 4)
        XCTAssertEqual(counts[VaccineSchedule.PCV], 4)
        XCTAssertEqual(counts[VaccineSchedule.IPV], 4)
        XCTAssertEqual(counts[VaccineSchedule.MMR], 2)
        XCTAssertEqual(counts[VaccineSchedule.VAR], 2)
        XCTAssertEqual(counts[VaccineSchedule.HEP_A], 2)
    }

    func testScheduleMatchesBundledJson() throws {
        struct File: Decodable {
            struct Group: Decodable { let label: String; let doses: [Dose] }
            struct Dose: Decodable { let key: String; let vaccineName: String; let doseNumber: Int; let dueStartMonths: Int; let dueEndMonths: Int }
            let groups: [Group]
        }
        let file = ResourceLoader.decode(File.self, "vaccine_schedule")
        XCTAssertEqual(file.groups.map(\.label), VaccineSchedule.groups.map(\.label))
        let json = file.groups.flatMap(\.doses).map { "\($0.key)|\($0.vaccineName)|\($0.doseNumber)|\($0.dueStartMonths)|\($0.dueEndMonths)" }
        let code = VaccineSchedule.doses.map { "\($0.key)|\($0.vaccineName)|\($0.doseNumber)|\($0.dueStartMonths)|\($0.dueEndMonths)" }
        XCTAssertEqual(json, code)
        for name in Set(VaccineSchedule.doses.map(\.vaccineName)) {
            XCTAssertTrue(VaccineCatalog.vaccines.contains(name), name)
        }
    }

    func testDosesAreInferredByChronologyFromNamesOnly() {
        let result = statuses(LocalDate.of(2026, 5, 10), entry("second", LocalDate.of(2026, 5, 1), VaccineSchedule.DTAP), entry("first", LocalDate.of(2026, 3, 1), VaccineSchedule.DTAP))
        XCTAssertEqual(dose(result, "dtap1").state, .GIVEN)
        XCTAssertEqual(dose(result, "dtap1").givenEntryId, "first")
        XCTAssertEqual(dose(result, "dtap1").givenDate, LocalDate.of(2026, 3, 1))
        XCTAssertEqual(dose(result, "dtap2").state, .GIVEN)
        XCTAssertEqual(dose(result, "dtap2").givenEntryId, "second")
        XCTAssertEqual(dose(result, "dtap3").state, .UPCOMING)
    }

    func testMultiVaccineEntryCountsOncePerVaccine() {
        let result = statuses(LocalDate.of(2026, 3, 5), entry("visit", LocalDate.of(2026, 3, 1), VaccineSchedule.DTAP, VaccineSchedule.PCV, VaccineSchedule.DTAP))
        XCTAssertEqual(dose(result, "dtap1").state, .GIVEN)
        XCTAssertEqual(dose(result, "pcv1").state, .GIVEN)
        XCTAssertEqual(dose(result, "dtap2").state, .UPCOMING)
    }

    func testDueAndOverdueBoundariesFollowTheWindow() {
        XCTAssertEqual(dose(statuses(LocalDate.of(2026, 2, 28)), "dtap1").state, .UPCOMING)
        XCTAssertEqual(dose(statuses(LocalDate.of(2026, 3, 1)), "dtap1").state, .DUE)
        XCTAssertEqual(dose(statuses(LocalDate.of(2026, 3, 31)), "dtap1").state, .DUE)
        XCTAssertEqual(dose(statuses(LocalDate.of(2026, 4, 1)), "dtap1").state, .OVERDUE)
        let hepb3 = dose(statuses(LocalDate.of(2027, 7, 31)), "hepb3")
        XCTAssertEqual(hepb3.state, .DUE)
        XCTAssertEqual(hepb3.dueDate, LocalDate.of(2026, 7, 1))
        XCTAssertEqual(dose(statuses(LocalDate.of(2027, 8, 1)), "hepb3").state, .OVERDUE)
    }

    func testBrandDependentDosesAreNeverOverdueOrRecommended() {
        let result = statuses(LocalDate.of(2026, 9, 1))
        XCTAssertEqual(dose(result, "rv3").state, .DUE)
        XCTAssertEqual(dose(result, "hib3").state, .DUE)
        XCTAssertFalse(dose(result, "rv3").countsTowardCompletion)
        XCTAssertFalse(VaccineSchedule.recommendations(result).contains { $0.dose.brandDependent })
    }

    func testImportedAndAbbreviatedNamesStillMatch() {
        XCTAssertEqual(VaccineSchedule.canonicalVaccineName("DTaP"), VaccineSchedule.DTAP)
        XCTAssertEqual(VaccineSchedule.canonicalVaccineName("PCV13"), VaccineSchedule.PCV)
        XCTAssertEqual(VaccineSchedule.canonicalVaccineName("Hep B"), VaccineSchedule.HEP_B)
        XCTAssertEqual(VaccineSchedule.canonicalVaccineName("mmr"), VaccineSchedule.MMR)
        XCTAssertNil(VaccineSchedule.canonicalVaccineName("Influenza (Flu)"))
        XCTAssertNil(VaccineSchedule.canonicalVaccineName("Vitamin K"))
        let result = statuses(LocalDate.of(2026, 1, 20), entry("birth-dose", LocalDate.of(2026, 1, 1), "Hep B", "Vitamin K"))
        XCTAssertEqual(dose(result, "hepb1").state, .GIVEN)
    }

    func testExtraDosesBeyondTheScheduleAreIgnoredByTheChart() {
        let entries = [2, 4, 6, 12].map { entry("m\($0)", birth.plusMonths($0), VaccineSchedule.PCV) }
        let result = VaccineSchedule.doseStatuses(birth, entries, today: LocalDate.of(2027, 3, 1), zone: utc)
        XCTAssertTrue(["pcv1", "pcv2", "pcv3", "pcv4"].allSatisfy { dose(result, $0).state == .GIVEN })
    }

    func testNoBirthDateStillShowsGivenDoses() {
        let result = statuses(LocalDate.of(2026, 3, 5), entry("first", LocalDate.of(2026, 3, 1), VaccineSchedule.DTAP), birthDate: .some(nil))
        XCTAssertEqual(dose(result, "dtap1").state, .GIVEN)
        XCTAssertEqual(dose(result, "dtap2").state, .UPCOMING)
        XCTAssertNil(dose(result, "dtap2").dueDate)
    }

    func testRecommendationsOrderOverdueThenDueThenUpcoming() {
        let atFiveMonths = statuses(LocalDate.of(2026, 6, 1))
        let recs = VaccineSchedule.recommendations(atFiveMonths, limit: 20)
        XCTAssertFalse(recs.isEmpty)
        XCTAssertEqual(recs.first?.state, .OVERDUE)
        let states = recs.map(\.state)
        XCTAssertEqual(states.sorted(), states)
        let upcoming = recs.filter { $0.state == .UPCOMING }
        XCTAssertEqual(upcoming.map { $0.dueDate!.epochDay }, upcoming.map { $0.dueDate!.epochDay }.sorted())
        XCTAssertLessThanOrEqual(VaccineSchedule.recommendations(atFiveMonths).count, 5)
    }
}
