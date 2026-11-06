package com.lifestyle.nestly.widget

import com.lifestyle.nestly.AppContainer
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.ui.entry.EntryBuilder
import com.lifestyle.nestly.ui.entry.EntryContext
import com.lifestyle.nestly.ui.entry.EntryDraft
import com.lifestyle.nestly.ui.entry.EntryKind
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

sealed interface QuickVitaminDResult {
    data class Saved(val atMs: Long) : QuickVitaminDResult
    data class AlreadyGiven(val atMs: Long) : QuickVitaminDResult
    data object NotSignedIn : QuickVitaminDResult
    data object SessionNotReady : QuickVitaminDResult
    data object NoChild : QuickVitaminDResult
    data object Failed : QuickVitaminDResult
}

/**
 * Saves today's Vitamin D with no UI, reusing the last dose (or the default). Used by the
 * nightstand screensaver. Never logs a second dose for the same local day.
 */
class QuickVitaminDLog(
    private val container: AppContainer,
    private val sessionWaitMs: Long = QuickBottleLog.SESSION_WAIT_MS,
) {

    suspend fun save(now: Long = System.currentTimeMillis()): QuickVitaminDResult {
        val status = withTimeoutOrNull(sessionWaitMs) {
            container.auth.sessionStatus.first {
                it is SessionStatus.Authenticated || it is SessionStatus.NotAuthenticated
            }
        }
        when (sessionWaitOutcome(status)) {
            SessionWaitOutcome.SIGNED_OUT -> return QuickVitaminDResult.NotSignedIn
            SessionWaitOutcome.NOT_READY -> return QuickVitaminDResult.SessionNotReady
            SessionWaitOutcome.SIGNED_IN -> Unit
        }

        return try {
            val profile = container.family.selectedProfile.first()
                ?: return QuickVitaminDResult.NoChild
            val zone = ZoneId.systemDefault()
            val startOfToday = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
            val last = container.activities.getLatest(profile.familyId, profile.id, ActivityType.VITAMIN_D)
            if (last != null && last.startTime >= startOfToday) {
                return QuickVitaminDResult.AlreadyGiven(last.startTime)
            }
            val draft = EntryDraft(
                startTime = now,
                dose = last?.medical?.dose ?: EntryBuilder.VITAMIN_D_DEFAULT_DOSE,
                doseUnit = last?.medical?.doseUnit ?: EntryBuilder.VITAMIN_D_DEFAULT_UNIT,
            )
            val ctx = EntryContext(
                familyId = profile.familyId,
                profileId = profile.id,
                caregiverId = container.family.currentCaregiverId(),
                timeZone = zone.id,
                now = now,
                newId = { UUID.randomUUID().toString() },
            )
            container.activities.saveAll(EntryBuilder.build(EntryKind.VITAMIN_D, draft, ctx))
            QuickVitaminDResult.Saved(now)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            QuickVitaminDResult.Failed
        }
    }
}
