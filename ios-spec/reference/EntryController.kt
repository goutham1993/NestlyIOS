package com.lifestyle.nestly.ui.entry

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.lifestyle.nestly.AppContainer
import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.BreastSide
import com.lifestyle.nestly.data.timer.TimerKey
import com.lifestyle.nestly.data.timer.TimerState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs

/**
 * Whether manually entering [newMl] in a new (not edited) entry should offer to update the
 * stored default. Tolerates the small drift from mL ⇄ oz display rounding, so simply opening
 * the amount dialog and tapping OK never prompts.
 */
fun shouldOfferDefaultBottleUpdate(isEditing: Boolean, newMl: Double?, defaultMl: Double?): Boolean =
    !isEditing && newMl != null && (defaultMl == null || abs(newMl - defaultMl) > 0.5)

/**
 * State and actions for one open entry sheet. New Breastfeed, Pump and Sleep entries keep their
 * durations in [com.lifestyle.nestly.data.timer.ActiveTimerStore] so timers survive the sheet closing.
 */
class EntryController(
    private val container: AppContainer,
    val request: EntryRequest,
    private val scope: CoroutineScope,
) {
    var kind by mutableStateOf((request as? EntryRequest.New)?.kind ?: EntryKind.BOTTLE)
        private set
    var draft by mutableStateOf(initialDraft(request))
        private set
    var existing by mutableStateOf<ActivityEntity?>(null)
        private set
    var loaded by mutableStateOf(request is EntryRequest.New)
        private set
    var lastBottleMl by mutableStateOf<Double?>(null)
        private set
    /** Stored default bottle amount (mL) pre-filled into new entries; null when unset/not loaded. */
    var defaultBottleMl by mutableStateOf<Double?>(null)
        private set
    var lastSide by mutableStateOf<BreastSide?>(null)
        private set
    var saving by mutableStateOf(false)
        private set
    var saveError by mutableStateOf<String?>(null)
        private set

    val isEditing: Boolean get() = request is EntryRequest.Edit

    /** True when durations come from the persistent timers rather than the draft. */
    val usesTimers: Boolean
        get() = !isEditing && kind in setOf(EntryKind.BREASTFEED, EntryKind.COMBO, EntryKind.PUMP, EntryKind.SLEEP)

    init {
        scope.launch { load() }
    }

    fun update(transform: (EntryDraft) -> EntryDraft) {
        draft = transform(draft)
    }

    /** Persists [ml] as the default bottle amount for future entries (null clears it). */
    fun updateDefaultBottleMl(ml: Double?) {
        defaultBottleMl = ml
        scope.launch { container.preferences.setDefaultBottleMl(ml) }
    }

    /** Starting one breast side pauses the other, as in Nara. */
    fun toggleTimer(key: TimerKey) = scope.launch {
        val now = System.currentTimeMillis()
        val timers = container.timers
        val other = when (key) {
            TimerKey.BREAST_LEFT -> TimerKey.BREAST_RIGHT
            TimerKey.BREAST_RIGHT -> TimerKey.BREAST_LEFT
            else -> null
        }
        timers.update(key) { it.toggle(now) }
        if (other != null) timers.update(other) { it.pause(now) }
    }

    fun setTimerDuration(key: TimerKey, seconds: Long) = scope.launch {
        if (usesTimers) {
            container.timers.update(key) {
                it.copy(
                    accumulatedMs = seconds * 1000,
                    runningSince = null,
                    sessionStart = it.sessionStart ?: (System.currentTimeMillis() - seconds * 1000),
                )
            }
        } else {
            update {
                when (key) {
                    TimerKey.BREAST_LEFT -> it.copy(leftSec = seconds)
                    TimerKey.BREAST_RIGHT -> it.copy(rightSec = seconds)
                    TimerKey.PUMP -> it.copy(pumpSec = seconds)
                    TimerKey.SLEEP -> it.copy(endTime = it.startTime + seconds * 1000)
                }
            }
        }
    }

    /** The draft with any running timers folded in, as it would be saved right now. */
    fun effectiveDraft(timers: Map<TimerKey, TimerState>, now: Long): EntryDraft {
        if (!usesTimers) return draft
        val d = draft
        return when (kind) {
            EntryKind.BREASTFEED, EntryKind.COMBO -> {
                val left = timers[TimerKey.BREAST_LEFT] ?: TimerState()
                val right = timers[TimerKey.BREAST_RIGHT] ?: TimerState()
                val leftSec = left.elapsedMs(now) / 1000
                val rightSec = right.elapsedMs(now) / 1000
                val starts = listOfNotNull(left.sessionStart, right.sessionStart)
                val begin = when {
                    left.sessionStart == null -> right.sessionStart?.let { BreastSide.RIGHT }
                    right.sessionStart == null -> BreastSide.LEFT
                    left.sessionStart <= right.sessionStart -> BreastSide.LEFT
                    else -> BreastSide.RIGHT
                }
                val end = when {
                    left.isRunning -> BreastSide.LEFT
                    right.isRunning -> BreastSide.RIGHT
                    begin == BreastSide.LEFT && right.sessionStart != null -> BreastSide.RIGHT
                    begin == BreastSide.RIGHT && left.sessionStart != null -> BreastSide.LEFT
                    else -> begin
                }
                d.copy(
                    leftSec = leftSec,
                    rightSec = rightSec,
                    beginSide = begin,
                    endSide = end,
                    startTime = if (d.startTimeSet) d.startTime else starts.minOrNull() ?: d.startTime,
                )
            }
            EntryKind.PUMP -> {
                val t = timers[TimerKey.PUMP] ?: TimerState()
                if (t.isIdle) d
                else d.copy(
                    pumpSec = t.elapsedMs(now) / 1000,
                    startTime = if (d.startTimeSet) d.startTime else t.sessionStart ?: d.startTime,
                )
            }
            EntryKind.SLEEP -> {
                val t = timers[TimerKey.SLEEP] ?: TimerState()
                if (t.isIdle) d
                else {
                    val start = if (d.startTimeSet) d.startTime else t.sessionStart ?: d.startTime
                    d.copy(startTime = start, endTime = start + t.elapsedMs(now))
                }
            }
            else -> d
        }
    }

    fun save(timers: Map<TimerKey, TimerState>, onDone: () -> Unit) {
        if (saving) return
        saving = true
        saveError = null
        scope.launch {
            try {
                val now = System.currentTimeMillis()
                val d = effectiveDraft(timers, now)
                val profile = container.family.selectedProfile.first()
                if (profile == null || !EntryBuilder.canSave(kind, d)) {
                    saving = false
                    if (profile == null) saveError = "No child selected. Check your connection and try again."
                    return@launch
                }
                val ctx = EntryContext(
                    familyId = profile.familyId,
                    profileId = profile.id,
                    caregiverId = container.family.currentCaregiverId(),
                    timeZone = ZoneId.systemDefault().id,
                    now = now,
                    newId = { UUID.randomUUID().toString() },
                )
                container.activities.saveAll(EntryBuilder.build(kind, d, ctx, existing), existing = existing)
                if (usesTimers) {
                    when (kind) {
                        EntryKind.BREASTFEED, EntryKind.COMBO -> container.timers.clear(TimerKey.BREAST_LEFT, TimerKey.BREAST_RIGHT)
                        EntryKind.PUMP -> container.timers.clear(TimerKey.PUMP)
                        EntryKind.SLEEP -> container.timers.clear(TimerKey.SLEEP)
                        else -> Unit
                    }
                }
                onDone()
                // Best-effort and several network round trips: run it on the
                // app scope (this sheet's scope may be cancelled by dismissal)
                // instead of making the user watch Save wait for it.
                container.applicationScope.launch {
                    runCatching { container.scheduler.rescheduleAll(container) }
                }
            } catch (e: Exception) {
                // Strict online-only: nothing is queued; the sheet stays open for retry.
                saveError = if (e is com.lifestyle.nestly.data.supabase.ConflictException) {
                    // Reload the newest version so the next save can succeed.
                    existing?.id?.let { id -> runCatching { container.activities.get(id) }.getOrNull() }?.let { fresh ->
                        existing = fresh
                        draft = EntryBuilder.draftOf(fresh)
                    }
                    e.message
                } else {
                    "Couldn't save. Check your connection and tap Save to retry."
                }
            } finally {
                saving = false
            }
        }
    }

    fun delete(onDone: () -> Unit) {
        val id = existing?.id ?: return
        scope.launch {
            try {
                container.activities.delete(id)
                onDone()
                container.applicationScope.launch {
                    runCatching { container.scheduler.rescheduleAll(container) }
                }
            } catch (e: Exception) {
                saveError = "Couldn't delete. Check your connection and try again."
            }
        }
    }

    /** Clears running timers for this sheet without saving. */
    fun discardTimers() = scope.launch {
        when (kind) {
            EntryKind.BREASTFEED, EntryKind.COMBO -> container.timers.clear(TimerKey.BREAST_LEFT, TimerKey.BREAST_RIGHT)
            EntryKind.PUMP -> container.timers.clear(TimerKey.PUMP)
            EntryKind.SLEEP -> container.timers.clear(TimerKey.SLEEP)
            else -> Unit
        }
    }

    private suspend fun load() {
        val editId = (request as? EntryRequest.Edit)?.activityId
        when {
            editId != null -> {
                val row = runCatching { container.activities.get(editId) }.getOrNull() ?: run {
                    saveError = "Couldn't load this entry. Check your connection."
                    loaded = true
                    return
                }
                val resolved = runCatching { container.activities.resolvePhoto(row) }.getOrDefault(row)
                existing = resolved
                kind = EntryKind.of(resolved.type)
                draft = EntryBuilder.draftOf(resolved)
                loaded = true
            }
            else -> Unit
        }
        // Pre-fill new bottle/combo feeds with the stored default amount. Done before the
        // profile lookup so it lands quickly, and never overwrites an amount the user has
        // already typed if they beat this load to it.
        if (editId == null && kind in setOf(EntryKind.BOTTLE, EntryKind.COMBO)) {
            runCatching { container.preferences.defaultBottleMl.first() }.getOrNull()?.let { default ->
                defaultBottleMl = default
                if (draft.bottleMl == null) draft = draft.copy(bottleMl = default)
            }
        }
        val profile = container.family.selectedProfile.first() ?: return
        if (kind == EntryKind.BOTTLE || kind == EntryKind.COMBO) {
            lastBottleMl = container.activities.getLatest(profile.familyId, profile.id, ActivityType.BOTTLE_FEED)?.bottle?.totalMl
        }
        if (kind == EntryKind.BREASTFEED || kind == EntryKind.COMBO) {
            lastSide = container.activities.getLatest(profile.familyId, profile.id, ActivityType.BREASTFEED)?.breastfeed?.endSide
        }
        if (editId == null && kind == EntryKind.VITAMIN_D) {
            val last = runCatching {
                container.activities.getLatest(profile.familyId, profile.id, ActivityType.VITAMIN_D)?.medical
            }.getOrNull()
            val untouched = draft.dose == EntryBuilder.VITAMIN_D_DEFAULT_DOSE &&
                draft.doseUnit == EntryBuilder.VITAMIN_D_DEFAULT_UNIT
            if (last?.dose != null && untouched) {
                draft = draft.copy(dose = last.dose, doseUnit = last.doseUnit ?: draft.doseUnit)
            }
        }
    }

    private fun initialDraft(request: EntryRequest): EntryDraft {
        val now = System.currentTimeMillis()
        if (request !is EntryRequest.New) return EntryDraft(startTime = now)
        val timed = request.kind in setOf(EntryKind.BREASTFEED, EntryKind.COMBO, EntryKind.PUMP, EntryKind.SLEEP)
        val vitaminD = request.kind == EntryKind.VITAMIN_D
        return EntryDraft(
            startTime = now,
            startTimeSet = !timed,
            milestoneKey = request.milestone?.key,
            milestoneTitle = request.milestone?.title.orEmpty(),
            vaccines = request.vaccines,
            dose = if (vitaminD) EntryBuilder.VITAMIN_D_DEFAULT_DOSE else null,
            doseUnit = if (vitaminD) EntryBuilder.VITAMIN_D_DEFAULT_UNIT else null,
        )
    }
}
