import Foundation

public struct Milestone: Equatable, Hashable, Sendable, Codable {
    public let key: String
    public let title: String

    public init(key: String, title: String) {
        self.key = key
        self.title = title
    }
}

public struct MilestoneGroup: Equatable, Sendable, Codable {
    public let label: String
    public let ageMonths: Int
    public let items: [Milestone]
}

enum ResourceLoader {
    static func data(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing bundled resource \(name).json")
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T {
        do {
            return try JSONDecoder().decode(type, from: data(name))
        } catch {
            fatalError("Bad bundled resource \(name).json: \(error)")
        }
    }
}

public enum MilestoneCatalog {
    private struct File: Decodable { let groups: [MilestoneGroup] }

    public static let groups: [MilestoneGroup] = ResourceLoader.decode(File.self, "milestones").groups

    public static var all: [Milestone] { groups.flatMap(\.items) }

    public static var totalCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    public static func byKey(_ key: String?) -> Milestone? {
        guard let key else { return nil }
        return all.first { $0.key == key }
    }

    public static func normalizeTitle(_ title: String) -> String {
        String(title.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    public static func findByTitle(_ title: String) -> Milestone? {
        let n = normalizeTitle(title)
        return all.first { normalizeTitle($0.title) == n }
    }
}

public struct VitaminDDefault: Decodable, Sendable {
    public let dose: Double
    public let unit: String
    public let medicationName: String
}

public struct CatalogFile: Decodable, Sendable {
    public let vaccines: [String]
    public let routines: [String]
    public let foods: [String]
    public let medicationDoseUnits: [String]
    public let vitaminDDoseUnits: [String]
    public let vitaminDDefault: VitaminDDefault
    public let appointmentTitleHints: [String]
}

public enum Catalogs {
    public static let file: CatalogFile = ResourceLoader.decode(CatalogFile.self, "catalogs")
    public static var vaccines: [String] { file.vaccines }
    public static var routines: [String] { file.routines }
    public static var foods: [String] { file.foods }
    public static var medicationDoseUnits: [String] { file.medicationDoseUnits }
    public static var vitaminDDoseUnits: [String] { file.vitaminDDoseUnits }
    public static var appointmentTitleHints: [String] { file.appointmentTitleHints }
}

public typealias VaccineCatalog = Catalogs
