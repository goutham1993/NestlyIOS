import Foundation

public enum VolumeUnit: String, Codable, CaseIterable, Sendable { case ML, OZ }
public enum WeightUnit: String, Codable, CaseIterable, Sendable { case KG, LB }
public enum LengthUnit: String, Codable, CaseIterable, Sendable { case CM, IN }
public enum TempUnit: String, Codable, CaseIterable, Sendable { case C, F }

public struct UnitPrefs: Equatable, Sendable {
    public var volume: VolumeUnit
    public var weight: WeightUnit
    public var length: LengthUnit
    public var temp: TempUnit

    public init(volume: VolumeUnit = .ML, weight: WeightUnit = .KG, length: LengthUnit = .CM, temp: TempUnit = .F) {
        self.volume = volume
        self.weight = weight
        self.length = length
        self.temp = temp
    }

    public static let DEFAULT = UnitPrefs()
}

/// Conversions for display/entry. Storage stays mL, kg, cm, °C.
public enum Units {
    static let ML_PER_OZ = 29.5735
    static let LB_PER_KG = 2.2046226218
    static let IN_PER_CM = 0.3937007874

    public static func mlToDisplay(_ ml: Double, _ unit: VolumeUnit) -> Double { unit == .ML ? ml : ml / ML_PER_OZ }
    public static func displayToMl(_ value: Double, _ unit: VolumeUnit) -> Double { unit == .ML ? value : value * ML_PER_OZ }
    public static func kgToDisplay(_ kg: Double, _ unit: WeightUnit) -> Double { unit == .KG ? kg : kg * LB_PER_KG }
    public static func displayToKg(_ value: Double, _ unit: WeightUnit) -> Double { unit == .KG ? value : value / LB_PER_KG }
    public static func cmToDisplay(_ cm: Double, _ unit: LengthUnit) -> Double { unit == .CM ? cm : cm * IN_PER_CM }
    public static func displayToCm(_ value: Double, _ unit: LengthUnit) -> Double { unit == .CM ? value : value / IN_PER_CM }
    public static func cToDisplay(_ c: Double, _ unit: TempUnit) -> Double { unit == .C ? c : c * 9 / 5 + 32 }
    public static func displayToC(_ value: Double, _ unit: TempUnit) -> Double { unit == .C ? value : (value - 32) * 5 / 9 }

    public static func volumeLabel(_ unit: VolumeUnit) -> String { unit == .ML ? "mL" : "oz" }
    public static func weightLabel(_ unit: WeightUnit) -> String { unit == .KG ? "kg" : "lb" }
    public static func lengthLabel(_ unit: LengthUnit) -> String { unit == .CM ? "cm" : "in" }
    public static func tempLabel(_ unit: TempUnit) -> String { unit == .C ? "°C" : "°F" }
}
