import Foundation

/// When to ask for a new shared child photo. Every month of the first year,
/// then each birthday. Twelve months is the first birthday, so it is not asked twice.
public enum PhotoPrompt {
    public struct Milestone: Equatable, Sendable {
        public let id: String
        public let date: LocalDate
        /// "6 months" or "2 years", for "Rithan is 6 months old".
        public let phrase: String
    }

    public struct Child: Sendable {
        public let id: String
        public let name: String
        public let birthDate: LocalDate?
        public let photoPath: String?
        /// Calendar day of `photo_updated_at`. Nil when the photo has never been saved.
        public let photoUpdatedOn: LocalDate?
        /// Milestone id this device already skipped.
        public let dismissedMilestoneId: String?

        public init(id: String, name: String, birthDate: LocalDate?, photoPath: String? = nil, photoUpdatedOn: LocalDate? = nil, dismissedMilestoneId: String? = nil) {
            self.id = id
            self.name = name
            self.birthDate = birthDate
            self.photoPath = photoPath
            self.photoUpdatedOn = photoUpdatedOn
            self.dismissedMilestoneId = dismissedMilestoneId
        }
    }

    public struct Due: Equatable, Identifiable, Sendable {
        public let profileId: String
        public let name: String
        public let photoPath: String?
        public let milestone: Milestone

        public var id: String { "\(profileId)|\(milestone.id)" }
        public var hasPhoto: Bool { photoPath != nil }
        public var title: String { "\(name) is \(milestone.phrase) old" }
        public var message: String {
            hasPhoto
                ? "Add a new photo so the family can see the latest \(name)."
                : "Add a photo of \(name) for the family."
        }
    }

    private static let monthMarks = Array(1...12)

    /// Latest milestone on or before `today`. Nil before the first month, and nil without a usable birth date.
    public static func current(birth: LocalDate, today: LocalDate) -> Milestone? {
        var best: Milestone?
        for months in monthMarks {
            let date = birth.plusMonths(months)
            guard !date.isAfter(today) else { continue }
            best = Milestone(id: "m\(months)", date: date, phrase: months == 1 ? "1 month" : "\(months) months")
        }
        var year = 2
        while year < 150 {
            let date = birth.plusYears(year)
            if date.isAfter(today) { break }
            best = Milestone(id: "y\(year)", date: date, phrase: "\(year) years")
            year += 1
        }
        return best
    }

    /// The milestone to ask about, or nil when it is too early, already dismissed, or the photo is current.
    public static func due(birth: LocalDate, photoUpdatedOn: LocalDate?, dismissedMilestoneId: String?, today: LocalDate) -> Milestone? {
        guard let milestone = current(birth: birth, today: today) else { return nil }
        if dismissedMilestoneId == milestone.id { return nil }
        if let photoUpdatedOn, !photoUpdatedOn.isBefore(milestone.date) { return nil }
        return milestone
    }

    /// One child. The selected child wins when they are due; otherwise the most recent milestone.
    public static func choose(_ children: [Child], selectedId: String?, today: LocalDate) -> Due? {
        let ready = children.compactMap { child -> Due? in
            guard let birth = child.birthDate,
                  let milestone = Self.due(birth: birth, photoUpdatedOn: child.photoUpdatedOn, dismissedMilestoneId: child.dismissedMilestoneId, today: today) else { return nil }
            return Due(profileId: child.id, name: child.name, photoPath: child.photoPath, milestone: milestone)
        }
        if let selected = ready.first(where: { $0.profileId == selectedId }) { return selected }
        return ready.max(by: { $0.milestone.date < $1.milestone.date })
    }
}
