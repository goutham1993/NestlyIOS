package com.lifestyle.nestly.data.units

enum class VolumeUnit { ML, OZ }
enum class WeightUnit { KG, LB }
enum class LengthUnit { CM, IN }
enum class TempUnit { C, F }

data class UnitPrefs(
    val volume: VolumeUnit = VolumeUnit.ML,
    val weight: WeightUnit = WeightUnit.KG,
    val length: LengthUnit = LengthUnit.CM,
    val temp: TempUnit = TempUnit.F,
) {
    companion object {
        val DEFAULT = UnitPrefs()
    }
}

/** Conversions for display/entry. Storage stays mL, kg, cm, °C. */
object Units {
    private const val ML_PER_OZ = 29.5735
    private const val LB_PER_KG = 2.2046226218
    private const val IN_PER_CM = 0.3937007874

    fun mlToDisplay(ml: Double, unit: VolumeUnit): Double = when (unit) {
        VolumeUnit.ML -> ml
        VolumeUnit.OZ -> ml / ML_PER_OZ
    }

    fun displayToMl(value: Double, unit: VolumeUnit): Double = when (unit) {
        VolumeUnit.ML -> value
        VolumeUnit.OZ -> value * ML_PER_OZ
    }

    fun kgToDisplay(kg: Double, unit: WeightUnit): Double = when (unit) {
        WeightUnit.KG -> kg
        WeightUnit.LB -> kg * LB_PER_KG
    }

    fun displayToKg(value: Double, unit: WeightUnit): Double = when (unit) {
        WeightUnit.KG -> value
        WeightUnit.LB -> value / LB_PER_KG
    }

    fun cmToDisplay(cm: Double, unit: LengthUnit): Double = when (unit) {
        LengthUnit.CM -> cm
        LengthUnit.IN -> cm * IN_PER_CM
    }

    fun displayToCm(value: Double, unit: LengthUnit): Double = when (unit) {
        LengthUnit.CM -> value
        LengthUnit.IN -> value / IN_PER_CM
    }

    fun cToDisplay(c: Double, unit: TempUnit): Double = when (unit) {
        TempUnit.C -> c
        TempUnit.F -> c * 9 / 5 + 32
    }

    fun displayToC(value: Double, unit: TempUnit): Double = when (unit) {
        TempUnit.C -> value
        TempUnit.F -> (value - 32) * 5 / 9
    }

    fun volumeLabel(unit: VolumeUnit) = when (unit) {
        VolumeUnit.ML -> "mL"
        VolumeUnit.OZ -> "oz"
    }

    fun weightLabel(unit: WeightUnit) = when (unit) {
        WeightUnit.KG -> "kg"
        WeightUnit.LB -> "lb"
    }

    fun lengthLabel(unit: LengthUnit) = when (unit) {
        LengthUnit.CM -> "cm"
        LengthUnit.IN -> "in"
    }

    fun tempLabel(unit: TempUnit) = when (unit) {
        TempUnit.C -> "°C"
        TempUnit.F -> "°F"
    }
}
