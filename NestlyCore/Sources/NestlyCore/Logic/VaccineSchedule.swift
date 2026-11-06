import Foundation

/// One scheduled dose in the CDC child immunization schedule. Ages are whole months since birth.
public struct VaccineDose: Equatable, Hashable, Sendable {
    public let key: String
    /// Must match a name in `VaccineCatalog.vaccines` so chart taps can pre-fill the entry form.
    public let vaccineName: String
    public let doseNumber: Int
    public let dueStartMonths: Int
    /// Last month of the recommended window (inclusive).
    public let dueEndMonths: Int
    /// True when whether this dose is needed depends on the vaccine brand used (RV / Hib).
    public let brandDependent: Bool
    public let note: String?

    public var label: String { "\(vaccineName) · Dose \(doseNumber)" }
}

public struct VaccineAgeGroup: Equatable, Sendable {
    public let label: String
    public let doses: [VaccineDose]
}

public struct VaccineInfo: Equatable, Sendable {
    public let title: String
    public let detail: String
}

public enum DoseState: Int, Comparable, Sendable {
    case GIVEN, OVERDUE, DUE, UPCOMING

    public static func < (a: DoseState, b: DoseState) -> Bool { a.rawValue < b.rawValue }
}

public struct DoseStatus: Equatable, Sendable {
    public let dose: VaccineDose
    public let groupLabel: String
    public let state: DoseState
    /// Entry that supplied this dose, so a given row can be opened for editing.
    public let givenEntryId: String?
    public let givenDate: LocalDate?
    /// When the dose window opens; nil without a birth date.
    public let dueDate: LocalDate?
    /// First day the dose counts as overdue (birth + dueEndMonths + 1 month); nil without a birth date.
    public let overdueDate: LocalDate?

    /// Brand-dependent doses a child may not need never count against completion.
    public var countsTowardCompletion: Bool { !(dose.brandDependent && state != .GIVEN) }
}

/// CDC (US) recommended immunization schedule, birth through 6 years, plus the logic that turns a
/// child's logged vaccine activities into per-dose status. The n-th time a vaccine name appears
/// (oldest first) is taken to be its n-th scheduled dose.
public enum VaccineSchedule {
    public static let HEP_B = "Hepatitis B (HepB)"
    public static let ROTAVIRUS = "Rotavirus (RV)"
    public static let DTAP = "Diphtheria, Tetanus, Pertussis (DTaP)"
    public static let HIB = "Haemophilus influenzae type b (Hib)"
    public static let PCV = "Pneumococcal (PCV)"
    public static let IPV = "Polio (IPV)"
    public static let MMR = "Measles, Mumps, Rubella (MMR)"
    public static let VAR = "Varicella (VAR)"
    public static let HEP_A = "Hepatitis A (HepA)"

    private static func dose(_ key: String, _ name: String, _ n: Int, _ start: Int, _ end: Int, brandDependent: Bool = false, note: String? = nil) -> VaccineDose {
        VaccineDose(key: key, vaccineName: name, doseNumber: n, dueStartMonths: start, dueEndMonths: end, brandDependent: brandDependent, note: note)
    }

    public static let groups: [VaccineAgeGroup] = [
        VaccineAgeGroup(label: "Birth", doses: [dose("hepb1", HEP_B, 1, 0, 0)]),
        VaccineAgeGroup(label: "1–2 months", doses: [dose("hepb2", HEP_B, 2, 1, 2)]),
        VaccineAgeGroup(label: "2 months", doses: [
            dose("rv1", ROTAVIRUS, 1, 2, 2),
            dose("dtap1", DTAP, 1, 2, 2),
            dose("hib1", HIB, 1, 2, 2),
            dose("pcv1", PCV, 1, 2, 2),
            dose("ipv1", IPV, 1, 2, 2),
        ]),
        VaccineAgeGroup(label: "4 months", doses: [
            dose("rv2", ROTAVIRUS, 2, 4, 4),
            dose("dtap2", DTAP, 2, 4, 4),
            dose("hib2", HIB, 2, 4, 4),
            dose("pcv2", PCV, 2, 4, 4),
            dose("ipv2", IPV, 2, 4, 4),
        ]),
        VaccineAgeGroup(label: "6 months", doses: [
            dose("hepb3", HEP_B, 3, 6, 18),
            dose("rv3", ROTAVIRUS, 3, 6, 6, brandDependent: true, note: "Only for the 3-dose rotavirus brand"),
            dose("dtap3", DTAP, 3, 6, 6),
            dose("hib3", HIB, 3, 6, 6, brandDependent: true, note: "Depends on the Hib brand used"),
            dose("pcv3", PCV, 3, 6, 6),
            dose("ipv3", IPV, 3, 6, 18),
        ]),
        VaccineAgeGroup(label: "12 months", doses: [
            dose("hib4", HIB, 4, 12, 15, note: "Booster dose"),
            dose("pcv4", PCV, 4, 12, 15),
            dose("mmr1", MMR, 1, 12, 15),
            dose("var1", VAR, 1, 12, 15),
            dose("hepa1", HEP_A, 1, 12, 23),
        ]),
        VaccineAgeGroup(label: "15 months", doses: [dose("dtap4", DTAP, 4, 15, 18)]),
        VaccineAgeGroup(label: "18 months", doses: [dose("hepa2", HEP_A, 2, 18, 23, note: "At least 6 months after dose 1")]),
        VaccineAgeGroup(label: "4–6 years", doses: [
            dose("dtap5", DTAP, 5, 48, 71),
            dose("ipv4", IPV, 4, 48, 71),
            dose("mmr2", MMR, 2, 48, 71),
            dose("var2", VAR, 2, 48, 71),
        ]),
    ]

    public static let doses: [VaccineDose] = groups.flatMap(\.doses)

    /// Seasonal / risk-based recommendations kept out of the dose counts.
    public static let alsoRecommended: [VaccineInfo] = [
        VaccineInfo(title: "Influenza (Flu)", detail: "Every year from 6 months old, during flu season."),
        VaccineInfo(title: "COVID-19", detail: "From 6 months old; the number of doses depends on age and previous vaccination."),
        VaccineInfo(title: "RSV (Nirsevimab)", detail: "One dose for babies under 8 months during their first RSV season, if the mother wasn't vaccinated in pregnancy."),
        VaccineInfo(title: "Rotavirus & Hib dose counts", detail: "Some brands need one fewer dose. If the chart shows a 3rd rotavirus or 3rd/4th Hib dose you may not need it — check with your pediatrician."),
    ]

    private static let dosesByVaccine: [String: [VaccineDose]] = Dictionary(grouping: doses, by: \.vaccineName)

    /// Maps a logged vaccine name to its canonical catalog name, or nil when it isn't a scheduled vaccine.
    public static func canonicalVaccineName(_ raw: String) -> String? {
        let n = normalize(raw)
        if n.isEmpty { return nil }
        if let exact = VaccineCatalog.vaccines.first(where: { normalize($0) == n }) {
            return dosesByVaccine[exact] != nil ? exact : nil
        }
        if n.contains("hepatitisb") || n == "hepb" { return HEP_B }
        if n.contains("hepatitisa") || n == "hepa" { return HEP_A }
        if n.contains("rotavirus") || n == "rv" { return ROTAVIRUS }
        if n.contains("diphtheria") || n.contains("dtap") { return DTAP }
        if n.contains("haemophilus") || n.contains("hemophilus") || n == "hib" { return HIB }
        if n.contains("pneumococcal") || n.hasPrefix("pcv") { return PCV }
        if n.contains("polio") || n == "ipv" { return IPV }
        if n.contains("measles") || n == "mmr" { return MMR }
        if n.contains("varicella") || n.contains("chickenpox") || n == "var" { return VAR }
        return nil
    }

    /// Per-dose status for a child. `birthDate` is the actual birth date (never the adjusted one).
    public static func doseStatuses(_ birthDate: LocalDate?, _ entries: [ActivityEntity], today: LocalDate, zone: TimeZone = .current) -> [DoseStatus] {
        let given = givenDoses(entries, zone)
        return groups.flatMap { group in
            group.doses.map { dose in
                let match = given[dose.key]
                let dueDate = birthDate?.plusMonths(dose.dueStartMonths)
                let overdueDate = birthDate?.plusMonths(dose.dueEndMonths + 1)
                let state: DoseState
                if match != nil {
                    state = .GIVEN
                } else if let dueDate, let overdueDate {
                    if !today.isBefore(overdueDate) && !dose.brandDependent {
                        state = .OVERDUE
                    } else if !today.isBefore(dueDate) {
                        state = .DUE
                    } else {
                        state = .UPCOMING
                    }
                } else {
                    state = .UPCOMING
                }
                return DoseStatus(dose: dose, groupLabel: group.label, state: state, givenEntryId: match?.0, givenDate: match?.1, dueDate: dueDate, overdueDate: overdueDate)
            }
        }
    }

    /// "Up next": overdue first (longest overdue first), then due now, then soonest upcoming.
    public static func recommendations(_ statuses: [DoseStatus], limit: Int = 5) -> [DoseStatus] {
        let actionable = statuses.filter { $0.state != .GIVEN && !$0.dose.brandDependent }
        let overdue = actionable.filter { $0.state == .OVERDUE }.sortedStable { $0.overdueDate?.epochDay ?? Int.min }
        let due = actionable.filter { $0.state == .DUE }.sortedStable { $0.dueDate?.epochDay ?? Int.min }
        let upcoming = actionable.filter { $0.state == .UPCOMING }.sortedStable { $0.dueDate?.epochDay ?? Int.min }
        return Array((overdue + due + upcoming).prefix(limit))
    }

    private static func givenDoses(_ entries: [ActivityEntity], _ zone: TimeZone) -> [String: (String, LocalDate)] {
        var order: [String] = []
        var occurrences: [String: [(String, LocalDate)]] = [:]
        for entry in entries.sortedStable(by: { $0.startTime }) {
            let date = LocalDate.of(ms: entry.startTime, zone: zone)
            let names = (entry.vaccine?.vaccines ?? []).compactMap(canonicalVaccineName).distinctBy { $0 }
            for name in names {
                if occurrences[name] == nil { order.append(name) }
                occurrences[name, default: []].append((entry.id, date))
            }
        }
        var result: [String: (String, LocalDate)] = [:]
        for name in order {
            let scheduled = dosesByVaccine[name] ?? []
            for (index, hit) in occurrences[name]!.enumerated() where index < scheduled.count {
                result[scheduled[index].key] = hit
            }
        }
        return result
    }

    private static func normalize(_ name: String) -> String {
        String(name.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
