package com.lifestyle.nestly.data.timer

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

enum class TimerKey { BREAST_LEFT, BREAST_RIGHT, PUMP, SLEEP }

/**
 * A stopwatch that survives process death. [accumulatedMs] holds time from earlier runs;
 * [runningSince] is set while the timer is ticking. [sessionStart] is when it was first started.
 */
data class TimerState(
    val accumulatedMs: Long = 0,
    val runningSince: Long? = null,
    val sessionStart: Long? = null,
) {
    val isRunning: Boolean get() = runningSince != null
    val isIdle: Boolean get() = accumulatedMs == 0L && runningSince == null

    fun elapsedMs(now: Long): Long = accumulatedMs + (runningSince?.let { (now - it).coerceAtLeast(0) } ?: 0)

    fun start(now: Long) = if (isRunning) this else copy(runningSince = now, sessionStart = sessionStart ?: now)

    fun pause(now: Long) = if (!isRunning) this else copy(accumulatedMs = elapsedMs(now), runningSince = null)

    fun toggle(now: Long) = if (isRunning) pause(now) else start(now)
}

private val Context.timerStore: DataStore<Preferences> by preferencesDataStore(name = "active_timers")

class ActiveTimerStore(context: Context) {
    private val store = context.applicationContext.timerStore

    val timers: Flow<Map<TimerKey, TimerState>> = store.data.map { prefs ->
        TimerKey.entries.associateWith { key ->
            TimerState(
                accumulatedMs = prefs[accumulatedKey(key)] ?: 0,
                runningSince = prefs[runningKey(key)],
                sessionStart = prefs[sessionKey(key)],
            )
        }
    }

    suspend fun update(key: TimerKey, transform: (TimerState) -> TimerState) {
        store.edit { prefs ->
            val current = TimerState(
                accumulatedMs = prefs[accumulatedKey(key)] ?: 0,
                runningSince = prefs[runningKey(key)],
                sessionStart = prefs[sessionKey(key)],
            )
            val next = transform(current)
            prefs[accumulatedKey(key)] = next.accumulatedMs
            next.runningSince?.let { prefs[runningKey(key)] = it } ?: prefs.remove(runningKey(key))
            next.sessionStart?.let { prefs[sessionKey(key)] = it } ?: prefs.remove(sessionKey(key))
        }
    }

    suspend fun clear(vararg keys: TimerKey) {
        store.edit { prefs ->
            keys.forEach { key ->
                prefs.remove(accumulatedKey(key))
                prefs.remove(runningKey(key))
                prefs.remove(sessionKey(key))
            }
        }
    }

    private fun accumulatedKey(key: TimerKey) = longPreferencesKey("${key.name}_accumulated")
    private fun runningKey(key: TimerKey) = longPreferencesKey("${key.name}_running_since")
    private fun sessionKey(key: TimerKey) = longPreferencesKey("${key.name}_session_start")
}
