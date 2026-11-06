package com.lifestyle.nestly.data.units

import org.junit.Assert.assertEquals
import org.junit.Test

class UnitsTest {
    @Test
    fun volumeRoundTrip() {
        val ml = 150.0
        val oz = Units.mlToDisplay(ml, VolumeUnit.OZ)
        assertEquals(ml, Units.displayToMl(oz, VolumeUnit.OZ), 0.001)
        assertEquals(ml, Units.mlToDisplay(ml, VolumeUnit.ML), 0.0)
    }

    @Test
    fun weightRoundTrip() {
        val kg = 4.5
        val lb = Units.kgToDisplay(kg, WeightUnit.LB)
        assertEquals(kg, Units.displayToKg(lb, WeightUnit.LB), 0.001)
    }

    @Test
    fun lengthRoundTrip() {
        val cm = 55.0
        val inches = Units.cmToDisplay(cm, LengthUnit.IN)
        assertEquals(cm, Units.displayToCm(inches, LengthUnit.IN), 0.001)
    }

    @Test
    fun tempRoundTrip() {
        val c = 37.0
        val f = Units.cToDisplay(c, TempUnit.F)
        assertEquals(98.6, f, 0.01)
        assertEquals(c, Units.displayToC(f, TempUnit.F), 0.01)
        assertEquals(c, Units.cToDisplay(c, TempUnit.C), 0.0)
    }

    @Test
    fun labels() {
        assertEquals("mL", Units.volumeLabel(VolumeUnit.ML))
        assertEquals("oz", Units.volumeLabel(VolumeUnit.OZ))
        assertEquals("kg", Units.weightLabel(WeightUnit.KG))
        assertEquals("lb", Units.weightLabel(WeightUnit.LB))
        assertEquals("cm", Units.lengthLabel(LengthUnit.CM))
        assertEquals("in", Units.lengthLabel(LengthUnit.IN))
        assertEquals("°C", Units.tempLabel(TempUnit.C))
        assertEquals("°F", Units.tempLabel(TempUnit.F))
    }
}
