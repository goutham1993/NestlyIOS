@testable import NestlyCore
import XCTest

final class FormatTests: XCTestCase {
    let minute: EpochMs = 60_000

    func testAgo() {
        let now = 1_000 * minute
        XCTAssertEqual(Format.ago(now - 30_000, now: now), "Just now")
        XCTAssertEqual(Format.ago(now - 5 * minute, now: now), "5m ago")
        XCTAssertEqual(Format.ago(now - 113 * minute, now: now), "1h 53m ago")
        XCTAssertEqual(Format.ago(now - 2 * 24 * 60 * minute, now: now), "2d ago")
        XCTAssertEqual(Format.ago(now + minute, now: now), "Just now")
    }

    func testAge() {
        let birth = LocalDate.of(2026, 1, 15)
        XCTAssertEqual(Format.age(birth, today: birth), "Born today")
        XCTAssertEqual(Format.age(birth, today: birth.plusDays(1)), "1 day old")
        XCTAssertEqual(Format.age(birth, today: birth.plusDays(5)), "5 days old")
        XCTAssertEqual(Format.age(birth, today: birth.plusWeeks(1)), "1 week old")
        XCTAssertEqual(Format.age(birth, today: birth.plusDays(17)), "2 weeks, 3 days old")
        XCTAssertEqual(Format.age(birth, today: birth.plusMonths(1)), "1 month old")
        XCTAssertEqual(Format.age(birth, today: birth.plusMonths(4).plusDays(14)), "4 months, 2 weeks old")
        XCTAssertEqual(Format.age(birth, today: birth.plusYears(1)), "1 year old")
        XCTAssertEqual(Format.age(birth, today: birth.plusYears(1).plusMonths(3)), "1 year, 3 months old")
        XCTAssertEqual(Format.age(birth, today: birth.plusYears(2)), "2 years old")
        XCTAssertNil(Format.age(birth, today: birth.minusDays(1)))
    }

    func testCountdown() {
        let zone = TimeZone.current
        let today = LocalDate.of(2026, 11, 4)
        let now = today.atTimeMs(12, 0, zone: zone)
        func at(_ date: LocalDate, _ hour: Int = 9) -> EpochMs { date.atTimeMs(hour, 0, zone: zone) }
        XCTAssertEqual(Format.countdown(at(today, 9), now: now), "Today")
        XCTAssertEqual(Format.countdown(at(today, 18), now: now), "Today")
        XCTAssertEqual(Format.countdown(at(today.plusDays(1)), now: now), "Tomorrow")
        XCTAssertEqual(Format.countdown(at(today.minusDays(1)), now: now), "Yesterday")
        XCTAssertEqual(Format.countdown(at(today.plusDays(2)), now: now), "in 2 days")
        XCTAssertEqual(Format.countdown(at(today.plusDays(13)), now: now), "in 13 days")
        XCTAssertEqual(Format.countdown(at(today.plusDays(16)), now: now), "in 2 weeks")
        XCTAssertEqual(Format.countdown(at(today.plusDays(29)), now: now), "in 4 weeks")
        XCTAssertEqual(Format.countdown(at(today.minusDays(14)), now: now), "2 weeks ago")
        XCTAssertEqual(Format.countdown(at(today.minusDays(33)), now: now), "1 month ago")
        XCTAssertEqual(Format.countdown(at(today.plusMonths(3)), now: now), "in 3 months")
        XCTAssertEqual(Format.countdown(at(today.plusYears(1)), now: now), "in 1 year")
        XCTAssertEqual(Format.countdown(at(today.minusYears(2)), now: now), "2 years ago")
    }

    func testNextFeeding() {
        let due = LocalDate.of(2026, 11, 3).atTimeMs(19, 18, zone: .current)
        XCTAssertEqual(Format.nextFeeding(.upcoming(dueMs: due, remainingMs: 85 * minute)), "Next feeding in 1h 25m at 7:18pm")
        XCTAssertEqual(Format.nextFeeding(.upcoming(dueMs: due, remainingMs: 77 * minute)), "Next feeding in 1h 17m at 7:18pm")
        XCTAssertEqual(Format.nextFeeding(.upcoming(dueMs: due, remainingMs: 60 * minute)), "Next feeding in 1h at 7:18pm")
        XCTAssertEqual(Format.nextFeeding(.upcoming(dueMs: due, remainingMs: minute)), "Next feeding in 1m at 7:18pm")
        XCTAssertEqual(Format.nextFeeding(.upcoming(dueMs: due, remainingMs: 30_000)), "Next feeding in 1m at 7:18pm")
        XCTAssertEqual(Format.nextFeeding(.dueNow(dueMs: due)), "Next feeding due now")
        XCTAssertEqual(Format.nextFeeding(.overdue(dueMs: due, overdueMs: 42 * minute)), "Next feeding overdue by 42m · due 7:18pm")
        XCTAssertNil(Format.nextFeeding(.noFeed))
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(0), "0s")
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(12 * 60), "12m")
        XCTAssertEqual(Format.duration(12 * 60 + 5), "12m 5s")
        XCTAssertEqual(Format.duration(3600 + 5 * 60 + 30), "1h 5m")
    }

    func testDurationUnderOneMinuteShowsSeconds() {
        XCTAssertEqual(Format.duration(0), "0s")
        XCTAssertEqual(Format.duration(45), "45s")
        XCTAssertEqual(Format.duration(59), "59s")
    }

    func testVolumeRespectsUnitPrefs() {
        let ml = UnitPrefs()
        var oz = ml
        oz.volume = .OZ
        XCTAssertEqual(Format.volume(150, ml), "150 mL")
        XCTAssertEqual(Format.volume(150, oz), "5.1 oz")
    }

    func testNumber() {
        XCTAssertEqual(Format.number(150), "150")
        XCTAssertEqual(Format.number(7.3412), "7.34")
        XCTAssertEqual(Format.number(7.5), "7.5")
        XCTAssertEqual(Format.ml(149.6), "150 mL")
    }
}

final class UnitsTests: XCTestCase {
    func testVolumeRoundTrip() {
        let oz = Units.mlToDisplay(150, .OZ)
        XCTAssertEqual(Units.displayToMl(oz, .OZ), 150, accuracy: 0.001)
        XCTAssertEqual(Units.mlToDisplay(150, .ML), 150)
    }

    func testWeightRoundTrip() {
        XCTAssertEqual(Units.displayToKg(Units.kgToDisplay(4.5, .LB), .LB), 4.5, accuracy: 0.001)
    }

    func testLengthRoundTrip() {
        XCTAssertEqual(Units.displayToCm(Units.cmToDisplay(55, .IN), .IN), 55, accuracy: 0.001)
    }

    func testTempRoundTrip() {
        let f = Units.cToDisplay(37, .F)
        XCTAssertEqual(f, 98.6, accuracy: 0.01)
        XCTAssertEqual(Units.displayToC(f, .F), 37, accuracy: 0.01)
        XCTAssertEqual(Units.cToDisplay(37, .C), 37)
    }

    func testLabels() {
        XCTAssertEqual(Units.volumeLabel(.ML), "mL")
        XCTAssertEqual(Units.volumeLabel(.OZ), "oz")
        XCTAssertEqual(Units.weightLabel(.KG), "kg")
        XCTAssertEqual(Units.weightLabel(.LB), "lb")
        XCTAssertEqual(Units.lengthLabel(.CM), "cm")
        XCTAssertEqual(Units.lengthLabel(.IN), "in")
        XCTAssertEqual(Units.tempLabel(.C), "°C")
        XCTAssertEqual(Units.tempLabel(.F), "°F")
    }
}

final class ReminderLogicTests: XCTestCase {
    func testNextFireFromLastActivity() {
        let last: EpochMs = 1_000_000
        XCTAssertEqual(ReminderLogic.nextFireMs(last, 180, now: last + 60_000), last + 180 * 60_000)
    }

    func testPastDueFiresOneMinuteFromNow() {
        let last: EpochMs = 1_000_000
        let now = last + 5 * 60 * 60_000
        XCTAssertEqual(ReminderLogic.nextFireMs(last, 180, now: now), now + 60_000)
    }

    func testNoActivityMeansNoFire() {
        XCTAssertNil(ReminderLogic.nextFireMs(nil, 180, now: 1_000))
    }

    func testNextFeedDueIsLastPlusInterval() {
        XCTAssertEqual(ReminderLogic.nextFeedDueMs(1_000_000, 180), 1_000_000 + 180 * 60_000)
        XCTAssertNil(ReminderLogic.nextFeedDueMs(nil, 180))
    }

    func testNextFeedUpcomingReportsRemaining() {
        let last: EpochMs = 1_000_000
        XCTAssertEqual(ReminderLogic.nextFeedState(last, 180, now: last + 60 * 60_000), .upcoming(dueMs: last + 180 * 60_000, remainingMs: 120 * 60_000))
    }

    func testNextFeedDueNowWithinOneMinutePastDue() {
        let last: EpochMs = 1_000_000
        let due = last + 180 * 60_000
        XCTAssertEqual(ReminderLogic.nextFeedState(last, 180, now: due), .dueNow(dueMs: due))
        XCTAssertEqual(ReminderLogic.nextFeedState(last, 180, now: due + 59_000), .dueNow(dueMs: due))
    }

    func testNextFeedOverdueIsNotClampedLikeNotification() {
        let last: EpochMs = 1_000_000
        XCTAssertEqual(ReminderLogic.nextFeedState(last, 180, now: last + 5 * 60 * 60_000), .overdue(dueMs: last + 180 * 60_000, overdueMs: 2 * 60 * 60_000))
    }

    func testNextFeedNoFeedWithoutHistory() {
        XCTAssertEqual(ReminderLogic.nextFeedState(nil, 180, now: 1_000), .noFeed)
    }
}

final class GrowthPercentilesTests: XCTestCase {
    func testMedianMeasurementIsThe50thPercentile() {
        XCTAssertClose(GrowthPercentiles.percentile(.WEIGHT, .MALE, 6.0, 7.934), 50, 1)
        XCTAssertClose(GrowthPercentiles.valueAtPercentile(.WEIGHT, .MALE, 6.0, 50), 7.934, 0.01)
    }

    func testScreenshotExampleLandsNearThe75thPercentile() {
        let p = GrowthPercentiles.percentile(.WEIGHT, .MALE, 5.55, 8.35)!
        XCTAssertTrue((70.0...80.0).contains(p), "was \(p)")
    }

    func testPercentileCurvesIncreaseWithPercentileAndAge() {
        let ages = [0.0, 6, 12, 24]
        for age in ages {
            let values = GrowthPercentiles.CHART_PERCENTILES.map { GrowthPercentiles.valueAtPercentile(.HEIGHT, .FEMALE, age, $0)! }
            XCTAssertEqual(values.sorted(), values)
        }
        let medians = ages.map { GrowthPercentiles.valueAtPercentile(.HEIGHT, .FEMALE, $0, 50)! }
        XCTAssertEqual(medians.sorted(), medians)
    }

    func testNoPercentileWithoutSexBirthRange() {
        XCTAssertNil(GrowthPercentiles.percentile(.WEIGHT, nil, 6, 8))
        XCTAssertNil(GrowthPercentiles.percentile(.WEIGHT, .OTHER, 6, 8))
        XCTAssertNil(GrowthPercentiles.percentile(.WEIGHT, .MALE, 61, 18))
        XCTAssertNil(GrowthPercentiles.valueAtPercentile(.HEAD, .FEMALE, -1, 50))
    }

    func testAgeLabelMatchesScreenshotFormat() {
        let birth = LocalDate.of(2026, 5, 4)
        XCTAssertEqual(GrowthPercentiles.ageLabel(birth, LocalDate.of(2026, 10, 20)), "5m 2w 2d")
        XCTAssertEqual(GrowthPercentiles.ageLabel(birth, LocalDate.of(2026, 9, 25)), "4m 3w")
        XCTAssertEqual(GrowthPercentiles.ageLabel(birth, birth), "0d")
    }
}

final class DtoMappingTests: XCTestCase {
    func testActivityRoundTripsThroughDto() throws {
        let original = ActivityEntity(
            id: "11111111-1111-1111-1111-111111111111",
            familyId: "22222222-2222-2222-2222-222222222222",
            profileId: "33333333-3333-3333-3333-333333333333",
            type: .BOTTLE_FEED,
            startTime: 1_700_000_000_000,
            endTime: 1_700_000_600_000,
            timeZone: "America/Chicago",
            note: "test",
            createdById: "44444444-4444-4444-4444-444444444444",
            bottle: BottleDetails(.FORMULA, formulaMl: 120, formulaName: "Gentle", totalMl: 120),
            createdAt: 1_700_000_000_000,
            updatedAt: 1_700_000_100_000,
            version: 3
        )
        XCTAssertEqual(try original.toDto().toEntity(), original)

        // Survives a JSON round trip too, as PostgREST would see it.
        let json = try JSONEncoder().encode(original.toDto())
        XCTAssertEqual(try JSONDecoder().decode(ActivityDto.self, from: json).toEntity(), original)
    }

    func testEmptyDetailsStayNull() throws {
        let dto = ActivityEntity(id: "11111111-1111-1111-1111-111111111111", familyId: "22222222-2222-2222-2222-222222222222", profileId: nil, type: .SLEEP, startTime: 1_700_000_000_000, timeZone: "UTC", createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000).toDto()
        XCTAssertNil(dto.bottleTotalMl)
        XCTAssertNil(dto.pumpDurationSec)
        let restored = try dto.toEntity()
        XCTAssertNil(restored.bottle)
        XCTAssertNil(restored.pump)
        XCTAssertNil(restored.breastfeed)
    }

    func testNullsAreEncodedExplicitly() throws {
        let dto = ActivityEntity(id: "a", familyId: "f", profileId: nil, type: .SLEEP, startTime: 0, timeZone: "UTC", createdAt: 0, updatedAt: 0).toDto()
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as! [String: Any]
        XCTAssertTrue(object["note"] is NSNull)
        XCTAssertTrue(object["end_time"] is NSNull)
        XCTAssertEqual(object["version"] as? Int, 1)
    }

    func testAppointmentRoundTripsThroughDto() throws {
        let original = AppointmentEntity(
            id: "11111111-1111-1111-1111-111111111111", familyId: "22222222-2222-2222-2222-222222222222", profileId: "33333333-3333-3333-3333-333333333333",
            title: "2-month checkup", doctorName: "Dr. Patel", location: "Sunny Pediatrics", startsAt: 1_700_000_000_000, timeZone: "America/Chicago",
            notes: "Bring vaccine record", reminderLead: .ONE_DAY, createdAt: 1_700_000_000_000, updatedAt: 1_700_000_100_000, version: 2
        )
        XCTAssertEqual(try original.toDto().toEntity(), original)
        XCTAssertEqual(original.toDto().reminderLeadMinutes, 1440)
    }

    func testAppointmentNullableFieldsStayNull() throws {
        let dto = AppointmentEntity(id: "1", familyId: "2", profileId: "3", title: "Checkup", startsAt: 1_700_000_000_000, timeZone: "UTC", createdAt: 1_700_000_000_000, updatedAt: 1_700_000_000_000).toDto()
        XCTAssertNil(dto.doctorName)
        XCTAssertNil(dto.location)
        XCTAssertNil(dto.notes)
        XCTAssertNil(dto.reminderLeadMinutes)
        XCTAssertEqual(try dto.toEntity().reminderLead, .NONE)
    }

    func testAppointmentQuestionRoundTripsThroughDto() throws {
        let original = AppointmentQuestionEntity(id: "1", appointmentId: "2", familyId: "3", text: "Is this rash normal?", isDone: true, sortOrder: 2, createdAt: 1_700_000_000_000, updatedAt: 1_700_000_100_000, version: 3)
        XCTAssertEqual(try original.toDto().toEntity(), original)
    }

    func testNoteRoundTripsThroughDto() throws {
        let original = NoteEntity(id: "1", familyId: "3", profileId: "4", title: "Bedtime routine", body: "1. Bath\n2. Feed\n☑ Lay out pajamas\n☐ Buy diapers\n• White noise on", createdAt: 1_700_000_000_000, updatedAt: 1_700_000_100_000, deletedAt: 1_700_000_200_000, version: 4)
        XCTAssertEqual(try original.toDto().toEntity(), original)
    }

    func testIsoConversionRoundTrips() throws {
        let millis: EpochMs = 1_700_000_123_000
        XCTAssertEqual(try millis.toIso().isoToMillis(), millis)
        XCTAssertEqual(try "2023-11-14T22:15:23.123+00:00".isoToMillis(), millis + 123)
        XCTAssertEqual(try "2023-11-14T22:15:23.123456+00:00".isoToMillis(), millis + 123)
        XCTAssertEqual(try "2023-11-14T16:15:23-06:00".isoToMillis(), millis)
        XCTAssertEqual(millis.toIso(), "2023-11-14T22:15:23.000Z")
    }
}

final class EntryBuilderTests: XCTestCase {
    private var ids = 0
    private lazy var ctx = EntryContext(familyId: "f", profileId: "p", caregiverId: "c", timeZone: "UTC", now: 1_000_000) { [unowned self] in
        ids += 1
        return "id\(ids)"
    }

    func testComboWithBothPartsProducesTwoLinkedRows() {
        let draft = EntryDraft(startTime: 500_000, milkType: .BREAST_MILK, bottleMl: 60, leftSec: 300, rightSec: 120, beginSide: .LEFT, endSide: .RIGHT)
        let rows = EntryBuilder.build(.COMBO, draft, ctx)
        XCTAssertEqual(rows.map(\.type), [.BREASTFEED, .BOTTLE_FEED])
        let group = rows[0].comboGroupId
        XCTAssertNotNil(group)
        XCTAssertTrue(rows.allSatisfy { $0.comboGroupId == group })
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        XCTAssertEqual(rows[0].endTime, 500_000 + 420_000)
        XCTAssertEqual(rows[1].bottle?.breastMilkMl, 60)
    }

    func testVitaminDRoundTripsThroughDraft() {
        let draft = EntryDraft(startTime: 500_000, note: "with feed", dose: 400, doseUnit: "IU")
        XCTAssertTrue(EntryBuilder.canSave(.VITAMIN_D, draft))
        let rows = EntryBuilder.build(.VITAMIN_D, draft, ctx)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.type, .VITAMIN_D)
        XCTAssertEqual(row.profileId, "p")
        XCTAssertEqual(row.medical?.medicationName, EntryBuilder.VITAMIN_D_NAME)
        XCTAssertEqual(row.medical?.dose, 400)
        XCTAssertEqual(row.medical?.doseUnit, "IU")
        XCTAssertEqual(EntryKind.of(row.type), .VITAMIN_D)

        let back = EntryBuilder.draftOf(row)
        XCTAssertEqual(back.dose, 400)
        XCTAssertEqual(back.doseUnit, "IU")
        XCTAssertEqual(back.note, "with feed")
    }

    func testVitaminDWithoutDoseDropsUnit() {
        let draft = EntryDraft(startTime: 500_000, dose: nil, doseUnit: "IU")
        XCTAssertTrue(EntryBuilder.canSave(.VITAMIN_D, draft))
        let row = EntryBuilder.build(.VITAMIN_D, draft, ctx)[0]
        XCTAssertNil(row.medical?.dose)
        XCTAssertNil(row.medical?.doseUnit)
    }

    func testComboWithOnlyBottleProducesOneUnlinkedRow() {
        let rows = EntryBuilder.build(.COMBO, EntryDraft(startTime: 500_000, milkType: .FORMULA, bottleMl: 90), ctx)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].type, .BOTTLE_FEED)
        XCTAssertNil(rows[0].comboGroupId)
        XCTAssertEqual(rows[0].bottle?.formulaMl, 90)
    }

    func testPumpBelongsToCaregiverNotChild() {
        let row = EntryBuilder.build(.PUMP, EntryDraft(startTime: 0, pumpMode: .LEFT_RIGHT, pumpLeftMl: 40, pumpRightMl: 35), ctx)[0]
        XCTAssertNil(row.profileId)
        XCTAssertEqual(row.pump?.totalMl, 75)
    }

    func testTemperatureRoundTripsThroughCelsius() {
        let row = EntryBuilder.build(.MEDICAL, EntryDraft(startTime: 0, temperatureF: 100.4), ctx)[0]
        XCTAssertClose(row.medical?.temperatureC, 38, 1e-9)
        XCTAssertClose(EntryBuilder.draftOf(row).temperatureF, 100.4, 1e-9)
    }

    func testCanSaveRequiresContent() {
        XCTAssertFalse(EntryBuilder.canSave(.DIAPER, EntryDraft(startTime: 0)))
        XCTAssertTrue(EntryBuilder.canSave(.DIAPER, EntryDraft(startTime: 0, dry: true)))
        XCTAssertFalse(EntryBuilder.canSave(.SLEEP, EntryDraft(startTime: 10, startTimeSet: false)))
        XCTAssertFalse(EntryBuilder.canSave(.SLEEP, EntryDraft(startTime: 10, endTime: 5)))
        XCTAssertTrue(EntryBuilder.canSave(.SLEEP, EntryDraft(startTime: 10, startTimeSet: true)))
        XCTAssertTrue(EntryBuilder.canSave(.SLEEP, EntryDraft(startTime: 10, endTime: 20)))
        XCTAssertFalse(EntryBuilder.canSave(.PUMP, EntryDraft(startTime: 0, startTimeSet: false)))
        XCTAssertTrue(EntryBuilder.canSave(.PUMP, EntryDraft(startTime: 0, startTimeSet: true)))
        XCTAssertTrue(EntryBuilder.canSave(.PUMP, EntryDraft(startTime: 0, startTimeSet: false, pumpTotalMl: 40)))
        let openPump = EntryBuilder.build(.PUMP, EntryDraft(startTime: 1_000, startTimeSet: true), ctx)[0]
        XCTAssertNil(openPump.endTime)
        XCTAssertEqual(openPump.pump?.durationSec, 0)
    }

    func testEditKeepsIdAndCreatedFields() {
        let original = EntryBuilder.build(.BABY_FIRST, EntryDraft(startTime: 0, babyFirstTitle: "First smile"), ctx)[0]
        let edited = EntryBuilder.build(
            .BABY_FIRST,
            EntryBuilder.draftOf(original).with { $0.babyFirstTitle = "First laugh" },
            ctx.with { $0.now = 2_000_000 },
            existing: original
        )[0]
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.createdAt, original.createdAt)
        XCTAssertEqual(edited.babyFirst?.title, "First laugh")
    }

    func testComboEditKeepsBothRowsAndRemovesDroppedPart() {
        let rows = EntryBuilder.build(.COMBO, EntryDraft(startTime: 500_000, milkType: .BREAST_MILK, bottleMl: 60, leftSec: 300), ctx)
        let draft = EntryBuilder.draftOfCombo(rows)
        XCTAssertEqual(draft.leftSec, 300)
        XCTAssertEqual(draft.bottleMl, 60)

        let kept = EntryBuilder.buildComboEdit(draft.with { $0.bottleMl = 90 }, ctx, existing: rows)
        XCTAssertEqual(Set(kept.rows.map(\.id)), Set(rows.map(\.id)))
        XCTAssertTrue(kept.removed.isEmpty)

        let dropped = EntryBuilder.buildComboEdit(draft.with { $0.bottleMl = nil; $0.milkType = nil }, ctx, existing: rows)
        XCTAssertEqual(dropped.rows.map(\.type), [.BREASTFEED])
        XCTAssertEqual(dropped.removed.map(\.type), [.BOTTLE_FEED])
    }
}
