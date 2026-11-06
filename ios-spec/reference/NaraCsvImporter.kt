package com.lifestyle.nestly.data.importer

import com.lifestyle.nestly.data.model.ActivityEntity
import com.lifestyle.nestly.data.model.ActivityType
import com.lifestyle.nestly.data.model.CaregiverEntity
import com.lifestyle.nestly.data.model.ProfileEntity
import com.lifestyle.nestly.data.model.ProfileType
import com.lifestyle.nestly.data.repository.ActivityRepository
import com.lifestyle.nestly.data.repository.FamilyRepository
import java.io.InputStream

data class ImportResult(
    val activityCounts: Map<ActivityType, Int>,
    val profiles: Int,
    val caregivers: Int,
    val skippedRows: Int,
) {
    val totalActivities: Int get() = activityCounts.values.sum()
}

/**
 * Imports a Nara Baby CSV export as a one-time load into the signed-in user's
 * current Supabase family. Nara's own family/profile/activity keys are never
 * used as database ids: everything is remapped into the target family with
 * deterministic UUIDs (see [NaraIds]), so importing the same file again
 * updates the imported rows instead of duplicating them.
 */
class NaraCsvImporter(
    private val activities: ActivityRepository,
    private val family: FamilyRepository,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    suspend fun import(input: InputStream): ImportResult {
        // Nara exports arrive as CSV or Excel (.xls/.xlsx); detect by content.
        val rows = SpreadsheetReader.parseRecords(input)
        val records = rows.mapNotNull(NaraRowMapper::map)
        val naraProfiles = records.filterIsInstance<NaraRecord.Profile>()
        val naraActivities = records.filterIsInstance<NaraRecord.Activity>()
        if (naraProfiles.isEmpty() && naraActivities.isEmpty()) {
            val columns = rows.firstOrNull()?.keys?.take(6)?.joinToString(", ")
            error(
                "No recognizable Nara rows found in this file" +
                    (columns?.let { " (columns: $it)" } ?: "") +
                    ". Make sure it's a Baby Nara export (.csv, .xls or .xlsx), not a different app's file.",
            )
        }
        val now = clock()

        val familyId = family.currentFamilyId()
            ?: error("Create or join a family before importing from Nara.")

        // --- Profiles: match existing children where possible, else create. ---
        val knownProfiles = family.fetchProfiles().filter { it.familyId == familyId }.toMutableList()
        val profileIdByKey = mutableMapOf<String, String>()

        suspend fun mapProfile(naraKey: String, name: String, create: suspend (String) -> ProfileEntity) {
            if (naraKey in profileIdByKey) return
            val matched = NaraProfileMatcher.match(name, null, knownProfiles)
            val id = matched?.id ?: NaraIds.profile(naraKey)
            profileIdByKey[naraKey] = id
            if (matched == null) {
                val created = create(id)
                family.importProfile(created)
                knownProfiles += created
            }
        }

        naraProfiles.forEach { p ->
            val matched = NaraProfileMatcher.match(p.name, p.birthDate, knownProfiles)
            val id = matched?.id ?: NaraIds.profile(p.profileKey)
            profileIdByKey[p.profileKey] = id
            val merged = ProfileEntity(
                id = id,
                familyId = familyId,
                name = p.name,
                birthDate = p.birthDate ?: matched?.birthDate,
                adjustedBirthDate = p.adjustedBirthDate ?: matched?.adjustedBirthDate,
                sex = p.sex ?: matched?.sex,
                profileType = p.profileType,
                createdAt = matched?.createdAt ?: now,
                updatedAt = now,
                version = matched?.version ?: 1,
            )
            family.importProfile(merged)
            if (matched == null) knownProfiles += merged
        }

        // Profiles referenced only by activities (no Profile row in the export).
        naraActivities.mapNotNull { a -> a.profileKey?.let { it to (a.profileName ?: "Baby") } }
            .distinct()
            .forEach { (key, name) ->
                mapProfile(key, name) { id ->
                    ProfileEntity(
                        id = id,
                        familyId = familyId,
                        name = name,
                        birthDate = null,
                        sex = null,
                        profileType = ProfileType.CHILD,
                        createdAt = now,
                        updatedAt = now,
                    )
                }
            }

        // --- Caregivers: reuse by normalized name, else create name-only rows. ---
        val existingCaregivers = family.fetchCaregivers(familyId)
        val caregiverIdByName = existingCaregivers
            .associateBy({ NaraIds.normalizeName(it.name) }, { it.id })
            .toMutableMap()
        val caregiverNames = naraActivities
            .flatMap { listOfNotNull(it.createdBy, it.updatedBy) }
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinctBy { NaraIds.normalizeName(it) }
        caregiverNames.forEach { name ->
            val key = NaraIds.normalizeName(name)
            if (key !in caregiverIdByName) {
                val caregiver = CaregiverEntity(
                    id = NaraIds.caregiver(familyId, name),
                    familyId = familyId,
                    name = name,
                    createdAt = now,
                    updatedAt = now,
                )
                family.importCaregiver(caregiver)
                caregiverIdByName[key] = caregiver.id
            }
        }
        fun caregiverId(name: String?): String? =
            name?.trim()?.takeIf { it.isNotEmpty() }?.let { caregiverIdByName[NaraIds.normalizeName(it)] }

        // --- Activities: deterministic ids, target family, remapped references. ---
        activities.importAll(
            naraActivities.map { a ->
                ActivityEntity(
                    id = NaraIds.activity(a.activityKey),
                    familyId = familyId,
                    profileId = a.profileKey?.let { profileIdByKey[it] },
                    type = a.type,
                    startTime = a.startTime,
                    endTime = a.endTime,
                    timeZone = a.timeZone,
                    note = a.note,
                    createdById = caregiverId(a.createdBy),
                    updatedById = caregiverId(a.updatedBy),
                    bottle = a.bottle,
                    pump = a.pump,
                    breastfeed = a.breastfeed,
                    diaper = a.diaper,
                    growth = a.growth,
                    milestone = a.milestone,
                    createdAt = a.startTime,
                    updatedAt = now,
                )
            },
        )

        return ImportResult(
            activityCounts = naraActivities.groupingBy { it.type }.eachCount(),
            profiles = profileIdByKey.size,
            caregivers = caregiverNames.size,
            skippedRows = rows.size - records.size,
        )
    }
}
