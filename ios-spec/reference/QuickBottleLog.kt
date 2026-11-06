package com.lifestyle.nestly.widget

import android.content.Context
import android.widget.Toast
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.lifestyle.nestly.AppContainer
import com.lifestyle.nestly.appContainer
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.units.UnitPrefs
import com.lifestyle.nestly.ui.components.Format
import com.lifestyle.nestly.ui.entry.EntryBuilder
import com.lifestyle.nestly.ui.entry.EntryContext
import com.lifestyle.nestly.ui.entry.EntryDraft
import com.lifestyle.nestly.ui.entry.EntryKind
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.time.ZoneId
import java.util.UUID

/**
 * Amount for a one-tap bottle feed: the stored default wins, otherwise the most
 * recent bottle amount (mirroring the sheet's "use last amount"). Null when there
 * is nothing sensible to save.
 */
fun resolveQuickBottleMl(defaultMl: Double?, lastMl: Double?): Double? =
    listOf(defaultMl, lastMl).firstOrNull { it != null && it > 0 }

sealed interface QuickBottleResult {
    data class Saved(val ml: Double, val atMs: Long) : QuickBottleResult
    data object NotSignedIn : QuickBottleResult

    /**
     * A stored session exists (or may exist) but Supabase was still restoring /
     * refreshing it when the wait gave up. This is NOT a sign-out — reporting it
     * as one produced the widget's intermittent "sign in first" toast on cold
     * starts while the signed-in screensaver, in a long-warm process, always worked.
     */
    data object SessionNotReady : QuickBottleResult
    data object NoChild : QuickBottleResult
    data object NoAmount : QuickBottleResult
    data object Failed : QuickBottleResult
}

internal enum class SessionWaitOutcome { SIGNED_IN, SIGNED_OUT, NOT_READY }

/**
 * Only [SessionStatus.Authenticated] and [SessionStatus.NotAuthenticated] are
 * verdicts. A cold process starts at [SessionStatus.Initializing]; if the stored
 * access token is past its refresh threshold, Supabase stays there (or moves to
 * [SessionStatus.RefreshFailure] and retries every ~10s) until a network refresh
 * lands. Treating those transient states — or a wait timeout, [status] == null —
 * as "signed out" is what made the widget falsely report a signed-in user as
 * logged out whenever that refresh took longer than the old 5s wait.
 */
internal fun sessionWaitOutcome(status: SessionStatus?): SessionWaitOutcome = when (status) {
    is SessionStatus.Authenticated -> SessionWaitOutcome.SIGNED_IN
    is SessionStatus.NotAuthenticated -> SessionWaitOutcome.SIGNED_OUT
    else -> SessionWaitOutcome.NOT_READY
}

/**
 * Saves a bottle feed with no UI: default (or last) amount, current time, for the
 * currently selected child. Used by the widget's Bottle button (via
 * [QuickBottleLogWorker]) and by the nightstand screensaver, so tapping either
 * never has to open the app.
 */
class QuickBottleLog(
    private val container: AppContainer,
    private val sessionWaitMs: Long = SESSION_WAIT_MS,
) {

    suspend fun save(now: Long = System.currentTimeMillis()): QuickBottleResult {
        // A widget tap can start a fresh process, in which the stored Supabase
        // session is still being restored; querying before it lands returns no
        // profiles under RLS and would look like "no child selected". Wait for a
        // definitive status only — see [sessionWaitOutcome].
        val status = withTimeoutOrNull(sessionWaitMs) {
            container.auth.sessionStatus.first {
                it is SessionStatus.Authenticated || it is SessionStatus.NotAuthenticated
            }
        }
        when (sessionWaitOutcome(status)) {
            SessionWaitOutcome.SIGNED_OUT -> return QuickBottleResult.NotSignedIn
            SessionWaitOutcome.NOT_READY -> return QuickBottleResult.SessionNotReady
            SessionWaitOutcome.SIGNED_IN -> Unit
        }

        return try {
            val profile = container.family.selectedProfile.first()
                ?: return QuickBottleResult.NoChild
            val defaultMl = runCatching { container.preferences.defaultBottleMl.first() }.getOrNull()
            val lastMl = if (defaultMl != null && defaultMl > 0) {
                null
            } else {
                runCatching {
                    container.activities.getLatest(profile.familyId, profile.id, ActivityType.BOTTLE_FEED)
                        ?.bottle?.totalMl
                }.getOrNull()
            }
            val ml = resolveQuickBottleMl(defaultMl, lastMl)
                ?: return QuickBottleResult.NoAmount
            val draft = EntryDraft(startTime = now, bottleMl = ml)
            if (!EntryBuilder.canSave(EntryKind.BOTTLE, draft)) return QuickBottleResult.NoAmount
            val ctx = EntryContext(
                familyId = profile.familyId,
                profileId = profile.id,
                caregiverId = container.family.currentCaregiverId(),
                timeZone = ZoneId.systemDefault().id,
                now = now,
                newId = { UUID.randomUUID().toString() },
            )
            container.activities.saveAll(EntryBuilder.build(EntryKind.BOTTLE, draft, ctx))
            // Don't make the "saved" confirmation wait on reminder scheduling.
            container.applicationScope.launch {
                runCatching { container.scheduler.rescheduleAll(container) }
            }
            QuickBottleResult.Saved(ml, now)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            QuickBottleResult.Failed
        }
    }

    companion object {
        // Generous on purpose: a cold start may need a full token refresh over a
        // just-woken radio, plus one of Supabase's 10s-spaced refresh retries.
        // Callers must therefore not run this inside the widget's broadcast
        // receiver (see SaveBottleFeedCallback) — the screensaver's long-lived
        // scope and the worker below both can afford it.
        const val SESSION_WAIT_MS = 30_000L
    }
}

private suspend fun bottleResultMessage(container: AppContainer, result: QuickBottleResult): String =
    when (result) {
        is QuickBottleResult.Saved -> {
            val units = runCatching { container.preferences.units.first() }
                .getOrDefault(UnitPrefs.DEFAULT)
            "Bottle feed saved: ${Format.volume(result.ml, units)} at ${Format.time(result.atMs)}"
        }
        QuickBottleResult.NotSignedIn ->
            "Couldn't save bottle feed. Open Nestly and sign in first."
        QuickBottleResult.SessionNotReady ->
            "Couldn't save bottle feed yet — still restoring your sign-in. Check your connection and try again."
        QuickBottleResult.NoChild ->
            "Couldn't save bottle feed. Open Nestly and select a child first."
        QuickBottleResult.NoAmount ->
            "No default bottle amount set. Open Nestly to set one first."
        QuickBottleResult.Failed ->
            "Couldn't save bottle feed. Check your connection and try again."
    }

private suspend fun toast(context: Context, message: String) {
    withContext(Dispatchers.Main) {
        Toast.makeText(context.applicationContext, message, Toast.LENGTH_LONG).show()
    }
}

/**
 * Does the actual save for the widget. It must not run in
 * [SaveBottleFeedCallback] itself: Glance invokes callbacks from a broadcast
 * receiver (`goAsync`), which the system can kill after a few seconds — right
 * in the middle of a cold-start session refresh or the save request. That
 * kill-or-finish race, on top of the session wait, is why the widget only
 * failed sometimes. Expedited work keeps the process alive until the save and
 * its confirmation toast have actually happened.
 */
class QuickBottleLogWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val container = applicationContext.appContainer
        // The feed belongs at tap time, not whenever the worker/network got to it.
        val tappedAt = inputData.getLong(KEY_TAPPED_AT_MS, System.currentTimeMillis())
        val result = try {
            QuickBottleLog(container).save(now = tappedAt)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            QuickBottleResult.Failed
        }
        toast(applicationContext, bottleResultMessage(container, result))
        // No Result.retry(): a retry could re-save a feed the server already
        // accepted (or log it long after the tap), creating duplicates. The
        // toast tells the user to tap again instead.
        return Result.success()
    }

    companion object {
        const val UNIQUE_NAME = "quick_bottle_log"
        const val KEY_TAPPED_AT_MS = "tapped_at_ms"
    }
}

/**
 * Enqueues [QuickBottleLogWorker] with the current time as the feed timestamp.
 * Used by the widget Bottle button and by Google Assistant / App Actions
 * ([QuickBottleLogActivity]) so both paths share the same save behavior.
 *
 * KEEP: a second request while a save is in flight is dropped, replacing the
 * old in-process double-tap flag (which a cold start simply reset).
 */
suspend fun enqueueQuickBottleLog(context: Context, atMs: Long = System.currentTimeMillis()) {
    val request = OneTimeWorkRequestBuilder<QuickBottleLogWorker>()
        .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        .setInputData(workDataOf(QuickBottleLogWorker.KEY_TAPPED_AT_MS to atMs))
        .build()
    WorkManager.getInstance(context.applicationContext)
        .enqueueUniqueWork(QuickBottleLogWorker.UNIQUE_NAME, ExistingWorkPolicy.KEEP, request)
    toast(context, "Saving bottle feed…")
}

/**
 * Glance callback for the widget's Bottle button. Only enqueues
 * [QuickBottleLogWorker] and confirms with a toast — it never starts
 * [com.lifestyle.nestly.MainActivity], and the save itself happens in the
 * worker, outside this broadcast's short lifetime.
 */
class SaveBottleFeedCallback : ActionCallback {

    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        enqueueQuickBottleLog(context)
    }
}
