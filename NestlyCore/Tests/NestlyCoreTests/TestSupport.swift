import Foundation
@testable import NestlyCore
import XCTest

let chicago = TimeZone(identifier: "America/Chicago")!

func activity(
    id: String = "1",
    familyId: String = "f",
    profileId: String? = "p",
    type: ActivityType,
    start: EpochMs,
    end: EpochMs? = nil,
    timeZone: String = "UTC",
    note: String? = nil,
    photo: String? = nil,
    bottle: BottleDetails? = nil,
    pump: PumpDetails? = nil,
    breastfeed: BreastfeedDetails? = nil,
    diaper: DiaperDetails? = nil,
    solids: SolidsDetails? = nil,
    medical: MedicalDetails? = nil,
    vaccine: VaccineDetails? = nil,
    comboGroupId: String? = nil,
    deletedAt: EpochMs? = nil
) -> ActivityEntity {
    ActivityEntity(
        id: id, familyId: familyId, profileId: profileId, type: type, startTime: start, endTime: end,
        timeZone: timeZone, note: note, bottle: bottle, pump: pump, breastfeed: breastfeed, diaper: diaper,
        solids: solids, medical: medical, vaccine: vaccine, photoUri: photo, comboGroupId: comboGroupId,
        createdAt: start, updatedAt: start, deletedAt: deletedAt
    )
}

func XCTAssertClose(_ a: Double?, _ b: Double, _ accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    guard let a else { return XCTFail("nil value", file: file, line: line) }
    XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line)
}
