package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ProfileEntity
import java.time.LocalDate
import java.util.UUID

/**
 * Deterministic UUIDs for Nara rows. Nara keys (e.g. `t-abc123`) are not UUIDs
 * and cannot be used as Supabase primary keys, so each key is hashed into a
 * stable UUID: re-importing the same export produces the same ids and upserts
 * update in place instead of duplicating.
 */
object NaraIds {
    private fun uuid(namespace: String, key: String): String =
        UUID.nameUUIDFromBytes("nara:$namespace:$key".toByteArray(Charsets.UTF_8)).toString()

    fun profile(profileKey: String): String = uuid("profile", profileKey)

    fun activity(activityKey: String): String = uuid("activity", activityKey)

    /** Scoped to the family so the same name in two families never collides. */
    fun caregiver(familyId: String, name: String): String =
        uuid("caregiver", "$familyId:${normalizeName(name)}")

    fun normalizeName(name: String): String =
        name.trim().lowercase().replace(Regex("\\s+"), " ")
}

/** Decides whether a Nara child is the same as an existing Nestly profile. */
object NaraProfileMatcher {
    /**
     * Matches on normalized name, preferring an equal birth date. Returns null
     * when there is no safe match (caller creates a new profile):
     * - Nara has a birth date: match a profile with that date, or the single
     *   same-named profile if none carries that date.
     * - Nara has no birth date: match only when exactly one profile has the name.
     */
    fun match(name: String, birthDate: LocalDate?, existing: List<ProfileEntity>): ProfileEntity? {
        val candidates = existing.filter { NaraIds.normalizeName(it.name) == NaraIds.normalizeName(name) }
        if (candidates.isEmpty()) return null
        if (birthDate != null) {
            candidates.firstOrNull { it.birthDate == birthDate }?.let { return it }
            return candidates.singleOrNull()
        }
        return candidates.singleOrNull()
    }
}
