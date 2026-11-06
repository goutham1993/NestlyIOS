package com.lifestyle.nestly.widget

import io.github.jan.supabase.auth.status.RefreshFailureCause
import io.github.jan.supabase.auth.status.SessionStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QuickBottleLogTest {

    @Test
    fun prefersStoredDefaultOverLastAmount() {
        assertEquals(150.0, resolveQuickBottleMl(defaultMl = 150.0, lastMl = 120.0)!!, 0.0)
    }

    @Test
    fun fallsBackToLastAmountWhenNoDefaultSet() {
        assertEquals(120.0, resolveQuickBottleMl(defaultMl = null, lastMl = 120.0)!!, 0.0)
    }

    @Test
    fun noAmountWhenNeitherDefaultNorLastExists() {
        assertNull(resolveQuickBottleMl(defaultMl = null, lastMl = null))
    }

    // The widget's intermittent false "sign in first": only a definitive
    // NotAuthenticated may be reported as signed out. A cold process sits in
    // Initializing (or RefreshFailure while Supabase retries a token refresh),
    // and a wait that times out there must not be misread as a sign-out.
    @Test
    fun onlyNotAuthenticatedCountsAsSignedOut() {
        assertEquals(
            SessionWaitOutcome.SIGNED_OUT,
            sessionWaitOutcome(SessionStatus.NotAuthenticated()),
        )
    }

    @Test
    fun transientSessionStatesAreNotSignedOut() {
        assertEquals(SessionWaitOutcome.NOT_READY, sessionWaitOutcome(SessionStatus.Initializing))
        assertEquals(
            SessionWaitOutcome.NOT_READY,
            sessionWaitOutcome(
                SessionStatus.RefreshFailure(RefreshFailureCause.NetworkError(Exception("offline"))),
            ),
        )
    }

    @Test
    fun sessionWaitTimeoutIsNotSignedOut() {
        assertEquals(SessionWaitOutcome.NOT_READY, sessionWaitOutcome(null))
    }

    @Test
    fun ignoresNonPositiveAmounts() {
        assertEquals(120.0, resolveQuickBottleMl(defaultMl = 0.0, lastMl = 120.0)!!, 0.0)
        assertNull(resolveQuickBottleMl(defaultMl = null, lastMl = 0.0))
        assertNull(resolveQuickBottleMl(defaultMl = -5.0, lastMl = null))
    }
}
