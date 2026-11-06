package com.lifestyle.nestly.ui.entry

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultBottleAmountTest {

    @Test
    fun offersToSetDefaultWhenNoneStored() {
        assertTrue(shouldOfferDefaultBottleUpdate(isEditing = false, newMl = 120.0, defaultMl = null))
    }

    @Test
    fun offersToUpdateDefaultWhenAmountChanged() {
        assertTrue(shouldOfferDefaultBottleUpdate(isEditing = false, newMl = 150.0, defaultMl = 120.0))
    }

    @Test
    fun noOfferWhenAmountMatchesDefault() {
        assertFalse(shouldOfferDefaultBottleUpdate(isEditing = false, newMl = 120.0, defaultMl = 120.0))
    }

    @Test
    fun noOfferForOzRoundingDrift() {
        // 120 mL shown as 4.06 oz converts back to ~120.06 mL; reopening the dialog
        // and tapping OK unchanged must not prompt.
        assertFalse(shouldOfferDefaultBottleUpdate(isEditing = false, newMl = 120.06, defaultMl = 120.0))
    }

    @Test
    fun noOfferWhenEditingExistingEntryOrClearingAmount() {
        assertFalse(shouldOfferDefaultBottleUpdate(isEditing = true, newMl = 150.0, defaultMl = 120.0))
        assertFalse(shouldOfferDefaultBottleUpdate(isEditing = false, newMl = null, defaultMl = 120.0))
    }
}
