package com.lifestyle.nestly.ui.entry

import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.model.MealType
import com.lifestyle.nestly.data.model.MilkType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EntryBuilderTest {
    private var ids = 0
    private val ctx = EntryContext(
        familyId = "f",
        profileId = "p",
        caregiverId = "c",
        timeZone = "UTC",
        now = 1_000_000,
        newId = { "id${++ids}" },
    )

    @Test
    fun comboWithBothPartsProducesTwoLinkedRows() {
        val draft = EntryDraft(
            startTime = 500_000,
            leftSec = 300,
            rightSec = 120,
            beginSide = BreastSide.LEFT,
            endSide = BreastSide.RIGHT,
            milkType = MilkType.BREAST_MILK,
            bottleMl = 60.0,
        )
        val rows = EntryBuilder.build(EntryKind.COMBO, draft, ctx)
        assertEquals(listOf(ActivityType.BREASTFEED, ActivityType.BOTTLE_FEED), rows.map { it.type })
        val group = rows.first().comboGroupId
        assertNotNull(group)
        assertTrue(rows.all { it.comboGroupId == group })
        assertEquals(2, rows.map { it.id }.toSet().size)
        assertEquals(500_000L + 420_000L, rows[0].endTime)
        assertEquals(60.0, rows[1].bottle!!.breastMilkMl!!, 0.0)
    }

    @Test
    fun vitaminDRoundTripsThroughDraft() {
        val draft = EntryDraft(startTime = 500_000, dose = 400.0, doseUnit = "IU", note = "with feed")
        assertTrue(EntryBuilder.canSave(EntryKind.VITAMIN_D, draft))
        val row = EntryBuilder.build(EntryKind.VITAMIN_D, draft, ctx).single()
        assertEquals(ActivityType.VITAMIN_D, row.type)
        assertEquals("p", row.profileId)
        assertEquals(EntryBuilder.VITAMIN_D_NAME, row.medical!!.medicationName)
        assertEquals(400.0, row.medical!!.dose!!, 0.0)
        assertEquals("IU", row.medical!!.doseUnit)
        assertEquals(EntryKind.VITAMIN_D, EntryKind.of(row.type))

        val back = EntryBuilder.draftOf(row)
        assertEquals(400.0, back.dose!!, 0.0)
        assertEquals("IU", back.doseUnit)
        assertEquals("with feed", back.note)
    }

    @Test
    fun vitaminDWithoutDoseDropsUnit() {
        val draft = EntryDraft(startTime = 500_000, dose = null, doseUnit = "IU")
        assertTrue(EntryBuilder.canSave(EntryKind.VITAMIN_D, draft))
        val row = EntryBuilder.build(EntryKind.VITAMIN_D, draft, ctx).single()
        assertNull(row.medical!!.dose)
        assertNull(row.medical!!.doseUnit)
    }

    @Test
    fun comboWithOnlyBottleProducesOneUnlinkedRow() {
        val draft = EntryDraft(startTime = 500_000, milkType = MilkType.FORMULA, bottleMl = 90.0)
        val rows = EntryBuilder.build(EntryKind.COMBO, draft, ctx)
        assertEquals(1, rows.size)
        assertEquals(ActivityType.BOTTLE_FEED, rows[0].type)
        assertNull(rows[0].comboGroupId)
        assertEquals(90.0, rows[0].bottle!!.formulaMl!!, 0.0)
    }

    @Test
    fun pumpBelongsToCaregiverNotChild() {
        val draft = EntryDraft(startTime = 0, pumpMode = PumpMode.LEFT_RIGHT, pumpLeftMl = 40.0, pumpRightMl = 35.0)
        val row = EntryBuilder.build(EntryKind.PUMP, draft, ctx).single()
        assertNull(row.profileId)
        assertEquals(75.0, row.pump!!.totalMl!!, 0.0)
    }

    @Test
    fun temperatureRoundTripsThroughCelsius() {
        val row = EntryBuilder.build(EntryKind.MEDICAL, EntryDraft(startTime = 0, temperatureF = 100.4), ctx).single()
        assertEquals(38.0, row.medical!!.temperatureC!!, 1e-9)
        assertEquals(100.4, EntryBuilder.draftOf(row).temperatureF!!, 1e-9)
    }

    @Test
    fun canSaveRequiresContent() {
        assertFalse(EntryBuilder.canSave(EntryKind.DIAPER, EntryDraft(startTime = 0)))
        assertTrue(EntryBuilder.canSave(EntryKind.DIAPER, EntryDraft(startTime = 0, dry = true)))
        assertFalse(EntryBuilder.canSave(EntryKind.SLEEP, EntryDraft(startTime = 10, startTimeSet = false)))
        assertFalse(EntryBuilder.canSave(EntryKind.SLEEP, EntryDraft(startTime = 10, endTime = 5)))
        assertTrue(EntryBuilder.canSave(EntryKind.SLEEP, EntryDraft(startTime = 10, startTimeSet = true)))
        assertTrue(EntryBuilder.canSave(EntryKind.SLEEP, EntryDraft(startTime = 10, endTime = 20)))
        assertFalse(EntryBuilder.canSave(EntryKind.PUMP, EntryDraft(startTime = 0, startTimeSet = false)))
        assertTrue(EntryBuilder.canSave(EntryKind.PUMP, EntryDraft(startTime = 0, startTimeSet = true)))
        assertTrue(EntryBuilder.canSave(EntryKind.PUMP, EntryDraft(startTime = 0, startTimeSet = false, pumpTotalMl = 40.0)))
        val openPump = EntryBuilder.build(EntryKind.PUMP, EntryDraft(startTime = 1_000, startTimeSet = true), ctx).single()
        assertNull(openPump.endTime)
        assertEquals(0L, openPump.pump?.durationSec)
    }

    @Test
    fun solidsMilkScheduleChoiceRoundTrips() {
        val keep = EntryBuilder.build(
            EntryKind.SOLIDS,
            EntryDraft(startTime = 1_000, mealType = MealType.LUNCH, foods = listOf("Avocado"), solidsResetsFeedSchedule = false),
            ctx,
        ).single()
        assertEquals(false, keep.solids?.resetsFeedSchedule)
        assertEquals(false, EntryBuilder.draftOf(keep).solidsResetsFeedSchedule)

        val replace = EntryBuilder.build(
            EntryKind.SOLIDS,
            EntryDraft(startTime = 1_000, mealType = MealType.DINNER, foods = listOf("Rice"), solidsResetsFeedSchedule = true),
            ctx,
        ).single()
        assertEquals(true, replace.solids?.resetsFeedSchedule)
        assertEquals(true, EntryBuilder.draftOf(replace).solidsResetsFeedSchedule)
    }

    @Test
    fun editKeepsIdAndCreatedFields() {
        val original = EntryBuilder.build(EntryKind.BABY_FIRST, EntryDraft(startTime = 0, babyFirstTitle = "First smile"), ctx).single()
        val edited = EntryBuilder.build(
            EntryKind.BABY_FIRST,
            EntryBuilder.draftOf(original).copy(babyFirstTitle = "First laugh"),
            ctx.copy(now = 2_000_000),
            existing = original,
        ).single()
        assertEquals(original.id, edited.id)
        assertEquals(original.createdAt, edited.createdAt)
        assertEquals("First laugh", edited.babyFirst!!.title)
    }
}
