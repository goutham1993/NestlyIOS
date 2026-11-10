import Compression
@testable import NestlyCore
import XCTest

// MARK: - Zip writer for fixtures (stored or deflated entries, with central directory)

private func crc32(_ data: [UInt8]) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        table[i] = c
    }
    var crc: UInt32 = 0xFFFF_FFFF
    for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFF_FFFF
}

private func deflate(_ data: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: data.count + 1024)
    let n = data.withUnsafeBufferPointer { src in
        out.withUnsafeMutableBufferPointer { dst in
            compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    return Array(out.prefix(n))
}

private func makeZip(_ files: [(String, String)], deflated: Bool = false) -> Data {
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }
    var out: [UInt8] = []
    var central: [UInt8] = []
    for (name, content) in files {
        let raw = Array(content.utf8)
        let body = deflated ? deflate(raw) : raw
        let method = deflated ? 8 : 0
        let nameBytes = Array(name.utf8)
        let crc = crc32(raw)
        let offset = UInt32(out.count)
        let local: [[UInt8]] = [
            [0x50, 0x4B, 0x03, 0x04], le16(20), le16(0), le16(method), le16(0), le16(0),
            le32(crc), le32(UInt32(body.count)), le32(UInt32(raw.count)), le16(nameBytes.count), le16(0), nameBytes, body,
        ]
        let entry: [[UInt8]] = [
            [0x50, 0x4B, 0x01, 0x02], le16(20), le16(20), le16(0), le16(method), le16(0), le16(0),
            le32(crc), le32(UInt32(body.count)), le32(UInt32(raw.count)), le16(nameBytes.count), le16(0), le16(0),
            le16(0), le16(0), le32(0), le32(offset), nameBytes,
        ]
        out.append(contentsOf: local.joined())
        central.append(contentsOf: entry.joined())
    }
    let cdOffset = UInt32(out.count)
    let end: [[UInt8]] = [
        central, [0x50, 0x4B, 0x05, 0x06], le16(0), le16(0), le16(files.count), le16(files.count),
        le32(UInt32(central.count)), le32(cdOffset), le16(0),
    ]
    out.append(contentsOf: end.joined())
    return Data(out)
}

final class CsvParserTests: XCTestCase {
    func testParsesQuotedFieldsEmptyFieldsAndEscapedQuotes() {
        XCTAssertEqual(CsvParser.parse("\"a\",,\"say \"\"hi\"\"\",3\n"), [["a", "", "say \"hi\"", "3"]])
    }

    func testKeepsNewlinesInsideQuotedFields() {
        let rows = CsvParser.parse("\"Type\",\"Note\"\r\n\"Pump\",\"line one \nline two\"\r\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1][1], "line one \nline two")
    }

    func testParseRecordsDropsBlankValuesAndBom() {
        XCTAssertEqual(CsvParser.parseRecords("\u{FEFF}\"Type\",\"Note\"\n\"Diaper\",\n"), [["Type": "Diaper"]])
    }
}

final class SpreadsheetReaderTests: XCTestCase {
    private func xlsxBytes(deflated: Bool = false) -> Data {
        let sheet = """
        <?xml version="1.0" encoding="UTF-8"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1">
        <c r="A1" t="inlineStr"><is><t>Type</t></is></c>
        <c r="B1" t="inlineStr"><is><t>Profile Name</t></is></c>
        <c r="C1" t="inlineStr"><is><t>Start Date/time (Epoch)</t></is></c>
        <c r="D1" t="inlineStr"><is><t>[Bottle Feed] Type</t></is></c>
        <c r="E1" t="inlineStr"><is><t>[Bottle Feed] Volume</t></is></c>
        <c r="F1" t="inlineStr"><is><t>_familyKey</t></is></c>
        <c r="G1" t="inlineStr"><is><t>_profileKey</t></is></c>
        <c r="H1" t="inlineStr"><is><t>_activityKey</t></is></c>
        </row>
        <row r="2">
        <c r="A2" t="inlineStr"><is><t>Bottle Feed</t></is></c>
        <c r="B2" t="inlineStr"><is><t>Rithan</t></is></c>
        <c r="C2"><v>1790896458000</v></c>
        <c r="D2" t="inlineStr"><is><t>Breast Milk</t></is></c>
        <c r="E2"><v>150</v></c>
        <c r="F2" t="inlineStr"><is><t>fam-1</t></is></c>
        <c r="G2" t="inlineStr"><is><t>prof-1</t></is></c>
        <c r="H2" t="inlineStr"><is><t>act-1</t></is></c>
        </row>
        </sheetData></worksheet>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
        """
        return makeZip([("xl/workbook.xml", workbook), ("xl/_rels/workbook.xml.rels", rels), ("xl/worksheets/sheet1.xml", sheet)], deflated: deflated)
    }

    func testReadsXlsxIntoRecords() throws {
        let records = try SpreadsheetReader.parseRecords(xlsxBytes())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["Type"], "Bottle Feed")
        XCTAssertEqual(records[0]["Start Date/time (Epoch)"], "1790896458000")
    }

    func testReadsDeflatedXlsx() throws {
        let records = try SpreadsheetReader.parseRecords(xlsxBytes(deflated: true))
        XCTAssertEqual(records.first?["Profile Name"], "Rithan")
    }

    func testXlsxBottleRowMapsToNaraRecord() throws {
        let mapped = try SpreadsheetReader.parseRecords(xlsxBytes()).compactMap(NaraRowMapper.map)
        XCTAssertEqual(mapped.count, 1)
        let a = try XCTUnwrap(mapped[0].asActivity)
        XCTAssertEqual(a.startTime, 1_790_896_458_000)
        XCTAssertEqual(a.bottle?.totalMl, 150)
    }

    func testSharedStringsResolve() throws {
        let sheet = """
        <?xml version="1.0"?><worksheet><sheetData>
        <row><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
        <row><c r="A2" t="s"><v>2</v></c><c r="B2"><v>42</v></c></row>
        </sheetData></worksheet>
        """
        let shared = #"<?xml version="1.0"?><sst><si><t>Type</t></si><si><t>Name</t></si><si><t>Diaper</t></si></sst>"#
        let records = try SpreadsheetReader.parseRecords(makeZip([("xl/sharedStrings.xml", shared), ("xl/worksheets/sheet1.xml", sheet)]))
        XCTAssertEqual(records, [["Type": "Diaper", "Name": "42"]])
    }

    func testReadsTsvAndHtmlAndCsv() throws {
        XCTAssertEqual(try SpreadsheetReader.parseRecords(Data("Type\tProfile Name\nDiaper\tRithan\n".utf8))[0]["Type"], "Diaper")
        let html = "<html><table><tr><td>Type</td><td>Profile Name</td></tr><tr><td>Diaper</td><td>Rithan</td></tr></table></html>"
        XCTAssertEqual(try SpreadsheetReader.parseRecords(Data(html.utf8))[0]["Profile Name"], "Rithan")
        XCTAssertEqual(try SpreadsheetReader.parseRecords(Data("Type,Profile Name\nDiaper,Rithan\n".utf8))[0]["Type"], "Diaper")
    }

    func testReadsSpreadsheetMl() throws {
        let xml = """
        <?xml version="1.0"?>
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
        <Worksheet ss:Name="Sheet1"><Table>
        <Row><Cell><Data ss:Type="String">Type</Data></Cell><Cell><Data ss:Type="String">Profile Name</Data></Cell></Row>
        <Row><Cell><Data ss:Type="String">Diaper</Data></Cell><Cell><Data ss:Type="String">Rithan</Data></Cell></Row>
        </Table></Worksheet></Workbook>
        """
        XCTAssertEqual(try SpreadsheetReader.parseRecords(Data(xml.utf8)), [["Type": "Diaper", "Profile Name": "Rithan"]])
    }

    func testReadsUtf16Csv() throws {
        var data = Data([0xFF, 0xFE])
        data.append("Type,Profile Name\nDiaper,Rithan\n".data(using: .utf16LittleEndian)!)
        XCTAssertEqual(try SpreadsheetReader.parseRecords(data)[0]["Profile Name"], "Rithan")
    }

    func testLegacyBinaryXlsGetsActionableError() {
        XCTAssertThrowsError(try SpreadsheetReader.parseRecords(Data([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0]))) { error in
            XCTAssertTrue((error as? ImportError)?.message.contains(".xlsx or .csv") == true)
        }
    }

    func testFlexibleLongParsing() {
        XCTAssertEqual("1790896458000".toLongFlexible(), 1_790_896_458_000)
        XCTAssertEqual("1790896458000.0".toLongFlexible(), 1_790_896_458_000)
        XCTAssertEqual("3600.0".toLongFlexible(), 3600)
        XCTAssertEqual("1.790896458E12".toLongFlexible(), 1_790_896_458_000)
    }
}

final class NaraRowMapperTests: XCTestCase {
    private func row(_ type: String, _ fields: [String: String] = [:], without: String? = nil) -> [String: String] {
        var r = [
            "Type": type, "Start Date/time (Epoch)": "1790896458000", "Time Zone": "America/Chicago",
            "Created By Caregiver": "Pravalika", "_familyKey": "f-1", "_profileKey": "c-1", "_activityKey": "t-1",
        ]
        r.merge(fields) { _, new in new }
        if let without { r[without] = nil }
        return r
    }

    private func activity(_ row: [String: String]) -> NaraRecord.Activity { NaraRowMapper.map(row)!.asActivity! }

    func testBottleBreastMilk() {
        let a = activity(row("Bottle Feed", ["[Bottle Feed] Type": "Breast Milk", "[Bottle Feed] Breast Milk Volume": "150", "[Bottle Feed] Breast Milk Volume Unit": "ML"]))
        XCTAssertEqual(a.type, .BOTTLE_FEED)
        XCTAssertEqual(a.bottle?.milkType, .BREAST_MILK)
        XCTAssertEqual(a.bottle?.totalMl, 150)
        XCTAssertEqual(a.updatedBy, "Pravalika")
    }

    func testBottleWithOnlyGenericVolumeHasUnknownMilkType() {
        let a = activity(row("Bottle Feed", ["[Bottle Feed] Volume": "60", "[Bottle Feed] Volume Unit": "ML"]))
        XCTAssertNil(a.bottle?.milkType)
        XCTAssertEqual(a.bottle?.totalMl, 60)
    }

    func testPumpClampsNegativeDurationAndEndBeforeStart() {
        let a = activity(row("Pump", ["[Pump] Duration (Seconds)": "-83820", "[Pump] End Date/time (Epoch)": "1790800000000", "[Pump] Total Volume": "130", "[Pump] Total Volume Unit": "ML"], without: "_profileKey"))
        XCTAssertNil(a.profileKey)
        XCTAssertEqual(a.pump?.durationSec, 0)
        XCTAssertEqual(a.endTime, a.startTime)
        XCTAssertEqual(a.pump?.totalMl, 130)
    }

    func testPumpConvertsFlozAndSumsSides() {
        let a = activity(row("Pump", ["[Pump] Left Volume": "3", "[Pump] Left Volume Unit": "FLOZ", "[Pump] Right Volume": "3", "[Pump] Right Volume Unit": "FLOZ"]))
        XCTAssertClose(a.pump?.leftMl, 88.72, 0.01)
        XCTAssertClose(a.pump?.totalMl, 177.44, 0.01)
    }

    func testBreastfeedNonTimerIsManual() {
        let a = activity(row("Breastfeed", ["[Breastfeed] Begin Side": "LEFT", "[Breastfeed] End Side": "RIGHT.nonTimer", "[Breastfeed] Left Duration (Seconds)": "600", "[Breastfeed] Right Duration (Seconds)": "300"]))
        XCTAssertEqual(a.breastfeed?.beginSide, .LEFT)
        XCTAssertEqual(a.breastfeed?.endSide, .RIGHT)
        XCTAssertEqual(a.breastfeed?.isManualEntry, true)
        XCTAssertEqual(a.endTime, a.startTime + 900_000)
    }

    func testBreastfeedTimerIsNotManual() {
        XCTAssertEqual(activity(row("Breastfeed", ["[Breastfeed] End Side": "LEFT"])).breastfeed?.isManualEntry, false)
    }

    func testDiaperDirtyWetIsMixed() {
        let a = activity(row("Diaper", ["[Diaper] Type": "Dirty Wet", "[Diaper] Dirty Color": "YELLOW", "[Diaper] Dirty Texture": "MUCOUS"]))
        XCTAssertEqual(a.diaper?.diaperType, .MIXED)
        XCTAssertEqual(a.diaper?.color, .YELLOW)
        XCTAssertEqual(a.diaper?.texture, .MUCOUS)
    }

    func testGrowthConvertsInchesToCm() {
        let a = activity(row("Growth", ["[Growth] Height": "22", "[Growth] Height Unit": "IN", "[Growth] Weight": "7.6", "[Growth] Weight Unit": "KG"]))
        XCTAssertClose(a.growth?.heightCm, 55.88, 0.001)
        XCTAssertEqual(a.growth?.weightKg, 7.6)
        XCTAssertNil(a.growth?.headCm)
    }

    func testProfileRow() {
        let p = NaraRowMapper.map(["Type": "Profile", "Profile Name": "Rithan", "[Profile] Birth Date": "2026-05-04", "[Profile] Sex": "MALE", "[Profile] Type": "CHILD", "_familyKey": "f-1", "_profileKey": "c-1"])!.asProfile!
        XCTAssertEqual(p.birthDate, LocalDate.of(2026, 5, 4))
        XCTAssertEqual(p.sex, .MALE)
    }

    func testUnknownTypeIsSkipped() {
        XCTAssertNil(NaraRowMapper.map(row("Sleep")))
    }
}

final class NaraImportMappingTests: XCTestCase {
    func testIdsAreDeterministicAndNamespaced() {
        XCTAssertEqual(NaraIds.activity("t-abc"), NaraIds.activity("t-abc"))
        XCTAssertNotEqual(NaraIds.activity("t-abc"), NaraIds.profile("t-abc"))
        XCTAssertNotEqual(NaraIds.activity("t-abc"), NaraIds.activity("t-def"))
        XCTAssertEqual(NaraIds.activity("t-abc").count, 36)
    }

    /// Fixed vectors from Java's `UUID.nameUUIDFromBytes`, so imports upsert identically on both platforms.
    func testIdsMatchJavaNameUuidFromBytes() {
        XCTAssertEqual(NaraIds.profile("c-1"), "6b12227c-4764-3461-b740-9cdd5ecc7db9")
        XCTAssertEqual(NaraIds.activity("t-1"), "2b7a2906-111a-3bda-bcfa-09a79e7bd4a3")
    }

    func testCaregiverIdsIgnoreNameSpacingAndCase() {
        XCTAssertEqual(NaraIds.caregiver("fam-1", "  Jane   Doe "), NaraIds.caregiver("fam-1", "jane doe"))
        XCTAssertNotEqual(NaraIds.caregiver("fam-1", "Jane Doe"), NaraIds.caregiver("fam-2", "Jane Doe"))
    }

    private func profile(_ name: String, _ birthDate: LocalDate?, id: String? = nil) -> ProfileEntity {
        ProfileEntity(id: id ?? "\(name)\(birthDate?.description ?? "null")", familyId: "fam", name: name, birthDate: birthDate, createdAt: 0, updatedAt: 0)
    }

    func testMatchesByNameAndBirthDate() {
        let dob = LocalDate.of(2026, 1, 15)
        let existing = [profile("Rithan", dob), profile("Rithan", dob.plusMonths(3), id: "other")]
        XCTAssertEqual(NaraProfileMatcher.match(" rithan ", dob, existing), existing[0])
    }

    func testMatchesSingleSameNamedProfileWhenDatesDiffer() {
        let dob = LocalDate.of(2026, 1, 15)
        let existing = [profile("Rithan", dob.plusMonths(3))]
        XCTAssertEqual(NaraProfileMatcher.match("Rithan", dob, existing), existing[0])
    }

    func testNoMatchWhenAmbiguousOrUnknown() {
        let dob = LocalDate.of(2026, 1, 15)
        let twins = [profile("Alex", dob.plusMonths(1), id: "a"), profile("Alex", dob.plusMonths(2), id: "b")]
        XCTAssertNil(NaraProfileMatcher.match("Alex", dob, twins))
        XCTAssertNil(NaraProfileMatcher.match("Alex", nil, twins))
        XCTAssertNil(NaraProfileMatcher.match("Sam", dob, twins))
    }
}

final class NestlyCsvRoundTripTests: XCTestCase {
    func testActivityFieldsSurviveExportAndParse() throws {
        let bottle = ActivityEntity(id: "act-bottle", familyId: "fam-1", profileId: "child-1", type: .BOTTLE_FEED, startTime: 1_700_000_000_000, timeZone: "America/Chicago", note: "evening feed", bottle: BottleDetails(.BREAST_MILK, breastMilkMl: 120, totalMl: 120), createdAt: 1_700_000_000_100, updatedAt: 1_700_000_000_200)
        let pump = ActivityEntity(id: "act-pump", familyId: "fam-1", profileId: nil, type: .PUMP, startTime: 1_700_000_100_000, endTime: 1_700_000_160_000, timeZone: "America/Chicago", pump: PumpDetails(durationSec: 600, leftMl: 40, rightMl: 35, totalMl: 75), createdAt: 1_700_000_100_100, updatedAt: 1_700_000_100_200)
        let diaper = ActivityEntity(id: "act-diaper", familyId: "fam-1", profileId: "child-1", type: .DIAPER, startTime: 1_700_000_200_000, timeZone: "America/Chicago", diaper: DiaperDetails(.WET), createdAt: 1_700_000_200_100, updatedAt: 1_700_000_200_200)

        let csv = NestlyCsv.document(families: [], caregivers: [], profiles: [], activities: [bottle, pump, diaper])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}record,id,familyId"))
        let rows = CsvParser.parseRecords(csv)
        XCTAssertEqual(rows.count, 3)

        let parsedBottle = try NestlyCsv.parseActivity(rows[0], now: 0)
        XCTAssertEqual(parsedBottle.id, bottle.id)
        XCTAssertEqual(parsedBottle.familyId, bottle.familyId)
        XCTAssertEqual(parsedBottle.profileId, bottle.profileId)
        XCTAssertEqual(parsedBottle.type, bottle.type)
        XCTAssertEqual(parsedBottle.startTime, bottle.startTime)
        XCTAssertEqual(parsedBottle.note, bottle.note)
        XCTAssertEqual(parsedBottle.bottle, bottle.bottle)

        let parsedPump = try NestlyCsv.parseActivity(rows[1], now: 0)
        XCTAssertEqual(parsedPump.pump, pump.pump)
        XCTAssertEqual(parsedPump.endTime, pump.endTime)

        let parsedDiaper = try NestlyCsv.parseActivity(rows[2], now: 0)
        XCTAssertEqual(parsedDiaper.diaper?.diaperType, .WET)
    }

    func testValuesUseAndroidFormatting() {
        let a = ActivityEntity(id: "x", familyId: "f", profileId: "p", type: .SOLIDS, startTime: 5, timeZone: "UTC", note: "a, \"b\"", solids: SolidsDetails(.LUNCH, ["Rice", "Peas"], resetsFeedSchedule: false), createdAt: 1, updatedAt: 2)
        let row = NestlyCsv.activityRow(a)
        XCTAssertTrue(row.contains("\"a, \"\"b\"\"\""))
        XCTAssertTrue(row.contains("LUNCH,Rice|Peas,false"))
        XCTAssertEqual(NestlyCsv.num(120), "120.0")
    }

    func testSolidsResetsFeedScheduleSurvivesExportAndParse() throws {
        let keep = ActivityEntity(id: "s1", familyId: "f", profileId: "p", type: .SOLIDS, startTime: 10, timeZone: "UTC", solids: SolidsDetails(.SNACK, ["Banana"], resetsFeedSchedule: false), createdAt: 1, updatedAt: 2)
        let replace = ActivityEntity(id: "s2", familyId: "f", profileId: "p", type: .SOLIDS, startTime: 20, timeZone: "UTC", solids: SolidsDetails(.LUNCH, ["Peas"], resetsFeedSchedule: true), createdAt: 1, updatedAt: 2)
        let rows = CsvParser.parseRecords(NestlyCsv.document(families: [], caregivers: [], profiles: [], activities: [keep, replace]))
        XCTAssertEqual(try NestlyCsv.parseActivity(rows[0], now: 0).solids?.resetsFeedSchedule, false)
        XCTAssertEqual(try NestlyCsv.parseActivity(rows[1], now: 0).solids?.resetsFeedSchedule, true)
    }
}

/// Runs the real Nara export (personal data, not in the repo) through the mapper when present.
final class NaraSampleImportTests: XCTestCase {
    func testSampleExportMapsWithUniqueDeterministicIds() throws {
        let candidates = [
            ProcessInfo.processInfo.environment["NARA_SAMPLE_CSV"],
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/nara_export.csv").path,
        ].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw XCTSkip("sample export not present")
        }
        let rows = CsvParser.parseRecords(try String(contentsOfFile: path, encoding: .utf8))
        let records = rows.compactMap(NaraRowMapper.map)
        let activities = records.compactMap(\.asActivity)
        let profiles = records.compactMap(\.asProfile)

        XCTAssertEqual(rows.count, records.count)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(Dictionary(grouping: activities, by: \.type).mapValues(\.count), [.BOTTLE_FEED: 1125, .PUMP: 1107, .BREASTFEED: 65, .GROWTH: 22, .DIAPER: 9, .MILESTONE: 3])

        let ids = activities.map { NaraIds.activity($0.activityKey) }
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertEqual(ids, activities.map { NaraIds.activity($0.activityKey) })
        XCTAssertTrue(ids.allSatisfy { $0.count == 36 })
        let keys = Set(profiles.map(\.profileKey))
        XCTAssertTrue(activities.allSatisfy { $0.profileKey == nil || keys.contains($0.profileKey!) })
    }
}

private actor FakeImportTarget: NaraImportTarget {
    var familyId: String? = "fam"
    var profiles: [ProfileEntity] = []
    var caregivers: [CaregiverEntity] = []
    var activities: [ActivityEntity] = []

    init(profiles: [ProfileEntity] = []) { self.profiles = profiles }

    func currentFamilyId() async throws -> String? { familyId }
    func fetchProfiles() async throws -> [ProfileEntity] { profiles }
    func fetchCaregivers(_ familyId: String) async throws -> [CaregiverEntity] { caregivers.filter { $0.familyId == familyId } }
    func importProfile(_ profile: ProfileEntity) async throws {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
    }
    func importCaregiver(_ caregiver: CaregiverEntity) async throws { caregivers.append(caregiver) }
    func importActivities(_ list: [ActivityEntity]) async throws { activities += list }
}

final class NaraCsvImporterTests: XCTestCase {
    let csv = """
    Type,Profile Name,[Profile] Birth Date,Start Date/time (Epoch),[Bottle Feed] Volume,Created By Caregiver,_familyKey,_profileKey,_activityKey
    Profile,Rithan,2026-05-04,,,,f-1,c-1,
    Bottle Feed,Rithan,,1790896458000,120,Pravalika,f-1,c-1,t-1
    Sleep,Rithan,,1790896458000,,,f-1,c-1,t-2
    """

    func testImportsIntoCurrentFamilyAndMatchesExistingChild() async throws {
        let existing = ProfileEntity(id: "existing", familyId: "fam", name: "rithan", createdAt: 5, updatedAt: 5, version: 3)
        let target = FakeImportTarget(profiles: [existing])
        let result = try await NaraCsvImporter(target: target, clock: { 1000 }).importData(Data(csv.utf8))

        XCTAssertEqual(result.activityCounts, [.BOTTLE_FEED: 1])
        XCTAssertEqual(result.profiles, 1)
        XCTAssertEqual(result.caregivers, 1)
        XCTAssertEqual(result.skippedRows, 1)

        let profiles = await target.profiles
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].id, "existing")
        XCTAssertEqual(profiles[0].birthDate, LocalDate.of(2026, 5, 4))
        XCTAssertEqual(profiles[0].version, 3)

        let activities = await target.activities
        XCTAssertEqual(activities.map(\.id), [NaraIds.activity("t-1")])
        XCTAssertEqual(activities[0].familyId, "fam")
        XCTAssertEqual(activities[0].profileId, "existing")
        XCTAssertEqual(activities[0].createdById, NaraIds.caregiver("fam", "Pravalika"))
    }

    func testUnrecognizedFileExplainsColumns() async {
        do {
            _ = try await NaraCsvImporter(target: FakeImportTarget()).importData(Data("Foo,Bar\n1,2\n".utf8))
            XCTFail("expected error")
        } catch {
            XCTAssertEqual((error as? ImportError)?.message, "No recognizable Nara rows found in this file (columns: Foo, Bar). Make sure it's a Baby Nara export (.csv, .xls or .xlsx), not a different app's file.")
        }
    }
}
