package com.lifestyle.nestly.data.supabase

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RefetchFlowTest {

    @Test
    fun failedRefetchKeepsLastGoodValueInsteadOfEmittingEmpty() = runTest {
        val table = "profile_test_keep_last"
        var attempt = 0
        val values = async {
            refetchFlow(table) {
                attempt++
                if (attempt == 2) throw RuntimeException("offline / expired token")
                listOf("child-$attempt")
            }.take(3).toList()
        }
        runCurrent() // initial fetch succeeds
        RefreshBus.invalidate(table) // MainActivity.onStart -> refreshAll()
        runCurrent() // refetch fails: must re-emit last good, not emptyList()
        RefreshBus.invalidate(table) // manual retry / next foreground
        runCurrent() // refetch succeeds again

        assertEquals(
            listOf(listOf("child-1"), listOf("child-1"), listOf("child-3")),
            values.await(),
        )
        DataErrors.clear()
    }

    @Test
    fun failedFirstFetchEmitsNothingUntilARefetchSucceeds() = runTest {
        val table = "profile_test_first_fails"
        var attempt = 0
        val values = async {
            refetchFlow(table) {
                attempt++
                if (attempt == 1) throw RuntimeException("offline / session not restored yet")
                listOf("child-$attempt")
            }.take(1).toList()
        }
        runCurrent() // first fetch fails

        // No successful fetch yet: nothing may be emitted. Emitting an empty
        // fallback here is what made NestlyApp flash onboarding on cold start
        // before the real (authenticated) fetch landed.
        assertFalse(values.isCompleted)

        RefreshBus.invalidate(table) // retry / session restored -> refetch
        runCurrent()

        assertEquals(listOf(listOf("child-2")), values.await())
        DataErrors.clear()
    }

    @Test
    fun tickDuringFetchDoesNotCancelTheRequest() = runTest {
        val table = "activity_test_no_cancel"
        var calls = 0
        val values = async {
            refetchFlow(table) {
                calls++
                // Same thing MainActivity.onStart and the network callback do
                // while the first read is still on the wire.
                if (calls == 1) RefreshBus.invalidate(table)
                "v$calls"
            }.take(2).toList()
        }
        runCurrent()

        assertEquals(listOf("v1", "v2"), values.await())
        assertEquals(2, calls)
        DataErrors.clear()
    }
}
