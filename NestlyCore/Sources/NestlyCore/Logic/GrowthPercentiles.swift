import Foundation

/// The three measurements tracked on the Growth card / screen.
public enum GrowthMetric: String, CaseIterable, Sendable, Identifiable {
    case WEIGHT, HEIGHT, HEAD

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .WEIGHT: "Weight"
        case .HEIGHT: "Height"
        case .HEAD: "Head Size"
        }
    }

    public func valueOf(_ details: GrowthDetails?) -> Double? {
        switch self {
        case .WEIGHT: details?.weightKg
        case .HEIGHT: details?.heightCm
        case .HEAD: details?.headCm
        }
    }
}

public struct Lms: Equatable, Sendable, Decodable {
    public let l: Double
    public let m: Double
    public let s: Double

    public init(l: Double, m: Double, s: Double) {
        self.l = l
        self.m = m
        self.s = s
    }
}

public enum WhoGrowthTables {
    private struct File: Decodable { let tables: [String: [Lms]] }

    private static let tables: [String: [Lms]] = ResourceLoader.decode(File.self, "who_growth_lms").tables

    public static let weightBoys = tables["weightBoys"]!
    public static let weightGirls = tables["weightGirls"]!
    public static let lengthBoys = tables["lengthBoys"]!
    public static let lengthGirls = tables["lengthGirls"]!
    public static let headBoys = tables["headBoys"]!
    public static let headGirls = tables["headGirls"]!
}

/// WHO percentile maths: converts a measurement to a percentile (via its z-score) and generates
/// the percentile curves drawn on the Growth chart. Ages are fractional months; LMS parameters are
/// interpolated linearly between the monthly table rows.
public enum GrowthPercentiles {
    public static let CHART_PERCENTILES: [Double] = [2, 5, 10, 25, 50, 75, 90, 95, 98]

    public static let MAX_AGE_MONTHS = 60.0

    private static func table(_ metric: GrowthMetric, _ sex: Sex?) -> [Lms]? {
        switch sex {
        case .MALE:
            switch metric {
            case .WEIGHT: WhoGrowthTables.weightBoys
            case .HEIGHT: WhoGrowthTables.lengthBoys
            case .HEAD: WhoGrowthTables.headBoys
            }
        case .FEMALE:
            switch metric {
            case .WEIGHT: WhoGrowthTables.weightGirls
            case .HEIGHT: WhoGrowthTables.lengthGirls
            case .HEAD: WhoGrowthTables.headGirls
            }
        default: nil
        }
    }

    /// Interpolated LMS at `ageMonths`, or nil when no curve applies.
    public static func lms(_ metric: GrowthMetric, _ sex: Sex?, _ ageMonths: Double) -> Lms? {
        guard let rows = table(metric, sex) else { return nil }
        if ageMonths < 0 || ageMonths > MAX_AGE_MONTHS { return nil }
        let lower = Int(ageMonths).clamped(0, rows.count - 1)
        let upper = min(lower + 1, rows.count - 1)
        let fraction = (ageMonths - Double(lower)).clamped(0, 1)
        let a = rows[lower], b = rows[upper]
        return Lms(l: a.l + (b.l - a.l) * fraction, m: a.m + (b.m - a.m) * fraction, s: a.s + (b.s - a.s) * fraction)
    }

    /// Percentile (0-100) of `value` at `ageMonths`, or nil when it can't be computed.
    public static func percentile(_ metric: GrowthMetric, _ sex: Sex?, _ ageMonths: Double, _ value: Double) -> Double? {
        guard let lms = lms(metric, sex, ageMonths) else { return nil }
        if value <= 0 { return nil }
        let z = abs(lms.l) < 1e-9
            ? log(value / lms.m) / lms.s
            : (pow(value / lms.m, lms.l) - 1) / (lms.l * lms.s)
        return normalCdf(z) * 100
    }

    /// The measurement value sitting on the `percentile` curve at `ageMonths`.
    public static func valueAtPercentile(_ metric: GrowthMetric, _ sex: Sex?, _ ageMonths: Double, _ percentile: Double) -> Double? {
        guard let lms = lms(metric, sex, ageMonths) else { return nil }
        let z = inverseNormalCdf(percentile / 100)
        if abs(lms.l) < 1e-9 { return lms.m * exp(lms.s * z) }
        let base = 1 + lms.l * lms.s * z
        return base <= 0 ? nil : lms.m * pow(base, 1 / lms.l)
    }

    /// Fractional age in months at `date`; negative when before birth.
    public static func ageMonths(_ birthDate: LocalDate, _ date: LocalDate) -> Double {
        Double(LocalDate.daysBetween(birthDate, date)) / 30.4375
    }

    /// Compact age as on the Growth list: "5m 2w 2d", "4m 3w", "0d".
    public static func ageLabel(_ birthDate: LocalDate, _ date: LocalDate) -> String {
        if date.isBefore(birthDate) { return "Not born yet" }
        let period = LocalDate.period(birthDate, date)
        if period.years > 0 { return "\(period.years)y \(period.months)m" }
        let weeks = period.days / 7
        let days = period.days % 7
        var parts: [String] = []
        if period.months > 0 { parts.append("\(period.months)m") }
        if weeks > 0 { parts.append("\(weeks)w") }
        if days > 0 { parts.append("\(days)d") }
        return parts.isEmpty ? "0d" : parts.joined(separator: " ")
    }

    /// Standard normal CDF via the Abramowitz–Stegun erf approximation.
    private static func normalCdf(_ z: Double) -> Double { 0.5 * (1 + erfApprox(z / 2.0.squareRoot())) }

    private static func erfApprox(_ x: Double) -> Double {
        let t = 1 / (1 + 0.3275911 * abs(x))
        let poly = (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t
        let sign: Double = x > 0 ? 1 : (x < 0 ? -1 : 0)
        return sign * (1 - poly * exp(-x * x))
    }

    /// Inverse standard normal CDF (Acklam's rational approximation).
    private static func inverseNormalCdf(_ p: Double) -> Double {
        precondition(p >= 0 && p <= 1)
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        let pLow = 0.02425
        if p < pLow {
            let q = (-2 * log(p)).squareRoot()
            let num = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
            let den = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1
            return num / den
        } else if p <= 1 - pLow {
            let q = p - 0.5
            let r = q * q
            let num = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
            let den = ((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1
            return num / den
        } else {
            let q = (-2 * log(1 - p)).squareRoot()
            let num = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
            let den = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1
            return -(num / den)
        }
    }
}
