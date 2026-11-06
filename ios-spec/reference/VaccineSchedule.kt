package com.lifestyle.nestly.data.catalog

import com.lifestyle.nestly.data.model.ActivityEntity
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** One scheduled dose in the CDC child immunization schedule. Ages are whole months since birth. */
data class VaccineDose(
    val key: String,
    /** Must match a name in [VaccineCatalog.vaccines] so chart taps can pre-fill the entry form. */
    val vaccineName: String,
    val doseNumber: Int,
    /** First month of the recommended window, e.g. 12 for "12–15 months". */
    val dueStartMonths: Int,
    /** Last month of the recommended window (inclusive), e.g. 15 for "12–15 months". */
    val dueEndMonths: Int,
    /** True when whether this dose is needed depends on the vaccine brand used (RV / Hib). */
    val brandDependent: Boolean = false,
    val note: String? = null,
) {
    val label: String get() = "$vaccineName · Dose $doseNumber"
}

data class VaccineAgeGroup(
    val label: String,
    val doses: List<VaccineDose>,
)

data class VaccineInfo(
    val title: String,
    val detail: String,
)

enum class DoseState { GIVEN, OVERDUE, DUE, UPCOMING }

data class DoseStatus(
    val dose: VaccineDose,
    val groupLabel: String,
    val state: DoseState,
    /** Entry that supplied this dose, so a given row can be opened for editing. */
    val givenEntryId: String? = null,
    val givenDate: LocalDate? = null,
    /** When the dose window opens (birth + [VaccineDose.dueStartMonths]); null without a birth date. */
    val dueDate: LocalDate? = null,
    /** First day the dose counts as overdue (birth + dueEndMonths + 1 month); null without a birth date. */
    val overdueDate: LocalDate? = null,
) {
    /** Brand-dependent doses a child may not need never count against completion. */
    val countsTowardCompletion: Boolean
        get() = !(dose.brandDependent && state != DoseState.GIVEN)
}

/**
 * CDC (US) recommended immunization schedule, birth through 6 years, plus the
 * logic that turns a child's logged vaccine activities into per-dose status.
 *
 * Logged activities carry vaccine *names only* — no dose number, brand or lot —
 * so a dose is inferred by chronology: the n-th time a vaccine name appears
 * (oldest first) is taken to be its n-th scheduled dose. This is a tracking
 * aid, not a medical record: brand-dependent series (Rotarix vs RotaTeq,
 * Hib brands) can shift dose counts, and catch-up timing differs when doses
 * are late. The screen says so and defers to the pediatrician.
 */
object VaccineSchedule {

    // Canonical names, identical to VaccineCatalog entries.
    const val HEP_B = "Hepatitis B (HepB)"
    const val ROTAVIRUS = "Rotavirus (RV)"
    const val DTAP = "Diphtheria, Tetanus, Pertussis (DTaP)"
    const val HIB = "Haemophilus influenzae type b (Hib)"
    const val PCV = "Pneumococcal (PCV)"
    const val IPV = "Polio (IPV)"
    const val MMR = "Measles, Mumps, Rubella (MMR)"
    const val VAR = "Varicella (VAR)"
    const val HEP_A = "Hepatitis A (HepA)"

    val groups: List<VaccineAgeGroup> = listOf(
        group(
            "Birth",
            dose("hepb1", HEP_B, 1, 0, 0),
        ),
        group(
            "1–2 months",
            dose("hepb2", HEP_B, 2, 1, 2),
        ),
        group(
            "2 months",
            dose("rv1", ROTAVIRUS, 1, 2, 2),
            dose("dtap1", DTAP, 1, 2, 2),
            dose("hib1", HIB, 1, 2, 2),
            dose("pcv1", PCV, 1, 2, 2),
            dose("ipv1", IPV, 1, 2, 2),
        ),
        group(
            "4 months",
            dose("rv2", ROTAVIRUS, 2, 4, 4),
            dose("dtap2", DTAP, 2, 4, 4),
            dose("hib2", HIB, 2, 4, 4),
            dose("pcv2", PCV, 2, 4, 4),
            dose("ipv2", IPV, 2, 4, 4),
        ),
        group(
            "6 months",
            dose("hepb3", HEP_B, 3, 6, 18),
            dose("rv3", ROTAVIRUS, 3, 6, 6, brandDependent = true, note = "Only for the 3-dose rotavirus brand"),
            dose("dtap3", DTAP, 3, 6, 6),
            dose("hib3", HIB, 3, 6, 6, brandDependent = true, note = "Depends on the Hib brand used"),
            dose("pcv3", PCV, 3, 6, 6),
            dose("ipv3", IPV, 3, 6, 18),
        ),
        group(
            "12 months",
            dose("hib4", HIB, 4, 12, 15, note = "Booster dose"),
            dose("pcv4", PCV, 4, 12, 15),
            dose("mmr1", MMR, 1, 12, 15),
            dose("var1", VAR, 1, 12, 15),
            dose("hepa1", HEP_A, 1, 12, 23),
        ),
        group(
            "15 months",
            dose("dtap4", DTAP, 4, 15, 18),
        ),
        group(
            "18 months",
            dose("hepa2", HEP_A, 2, 18, 23, note = "At least 6 months after dose 1"),
        ),
        group(
            "4–6 years",
            dose("dtap5", DTAP, 5, 48, 71),
            dose("ipv4", IPV, 4, 48, 71),
            dose("mmr2", MMR, 2, 48, 71),
            dose("var2", VAR, 2, 48, 71),
        ),
    )

    val doses: List<VaccineDose> = groups.flatMap { it.doses }

    /** Seasonal / risk-based recommendations kept out of the dose counts. */
    val alsoRecommended: List<VaccineInfo> = listOf(
        VaccineInfo(
            "Influenza (Flu)",
            "Every year from 6 months old, during flu season.",
        ),
        VaccineInfo(
            "COVID-19",
            "From 6 months old; the number of doses depends on age and previous vaccination.",
        ),
        VaccineInfo(
            "RSV (Nirsevimab)",
            "One dose for babies under 8 months during their first RSV season, if the mother wasn't vaccinated in pregnancy.",
        ),
        VaccineInfo(
            "Rotavirus & Hib dose counts",
            "Some brands need one fewer dose. If the chart shows a 3rd rotavirus or 3rd/4th Hib dose you may not need it — check with your pediatrician.",
        ),
    )

    private val dosesByVaccine: Map<String, List<VaccineDose>> =
        doses.groupBy { it.vaccineName }

    private fun group(
        label: String,
        vararg doses: VaccineDose,
    ) = VaccineAgeGroup(label, doses.toList())

    private fun dose(
        key: String,
        vaccineName: String,
        doseNumber: Int,
        dueStartMonths: Int,
        dueEndMonths: Int,
        brandDependent: Boolean = false,
        note: String? = null,
    ) = VaccineDose(key, vaccineName, doseNumber, dueStartMonths, dueEndMonths, brandDependent, note)

    /**
     * Maps a logged vaccine name to its canonical [VaccineCatalog] name, or null
     * when it isn't a scheduled vaccine. Matching ignores case and punctuation
     * and accepts common abbreviations/codes ("DTaP", "PCV13", "Hep B"), so
     * names arriving via CSV import still count.
     */
    fun canonicalVaccineName(raw: String): String? {
        val normalized = normalize(raw)
        if (normalized.isEmpty()) return null
        VaccineCatalog.vaccines.firstOrNull { normalize(it) == normalized }?.let { exact ->
            return exact.takeIf { it in dosesByVaccine }
        }
        return when {
            normalized.contains("hepatitisb") || normalized == "hepb" -> HEP_B
            normalized.contains("hepatitisa") || normalized == "hepa" -> HEP_A
            normalized.contains("rotavirus") || normalized == "rv" -> ROTAVIRUS
            normalized.contains("diphtheria") || normalized.contains("dtap") -> DTAP
            normalized.contains("haemophilus") || normalized.contains("hemophilus") ||
                normalized == "hib" -> HIB
            normalized.contains("pneumococcal") || normalized.startsWith("pcv") -> PCV
            normalized.contains("polio") || normalized == "ipv" -> IPV
            normalized.contains("measles") || normalized == "mmr" -> MMR
            normalized.contains("varicella") || normalized.contains("chickenpox") ||
                normalized == "var" -> VAR
            else -> null
        }
    }

    /**
     * Per-dose status for a child. [entries] are the child's VACCINE activities
     * in any order. [birthDate] is the child's actual birth date — CDC vaccinates
     * preterm infants by chronological age, so the adjusted birth date is not used.
     * Without a birth date, logged doses still show as given; the rest are upcoming.
     */
    fun doseStatuses(
        birthDate: LocalDate?,
        entries: List<ActivityEntity>,
        today: LocalDate,
        zone: ZoneId = ZoneId.systemDefault(),
    ): List<DoseStatus> {
        val given = givenDoses(entries, zone)
        return groups.flatMap { group ->
            group.doses.map { dose ->
                val match = given[dose.key]
                val dueDate = birthDate?.plusMonths(dose.dueStartMonths.toLong())
                val overdueDate = birthDate?.plusMonths(dose.dueEndMonths.toLong() + 1)
                val state = when {
                    match != null -> DoseState.GIVEN
                    birthDate == null || dueDate == null || overdueDate == null -> DoseState.UPCOMING
                    // A brand-dependent dose the child may never need is never "overdue".
                    !today.isBefore(overdueDate) && !dose.brandDependent -> DoseState.OVERDUE
                    !today.isBefore(dueDate) -> DoseState.DUE
                    else -> DoseState.UPCOMING
                }
                DoseStatus(
                    dose = dose,
                    groupLabel = group.label,
                    state = state,
                    givenEntryId = match?.first,
                    givenDate = match?.second,
                    dueDate = dueDate,
                    overdueDate = overdueDate,
                )
            }
        }
    }

    /**
     * "Up next" shortlist: overdue first (longest overdue first), then doses due
     * now, then the soonest upcoming. Brand-dependent doses are excluded — whether
     * they're needed depends on the brand already used.
     */
    fun recommendations(statuses: List<DoseStatus>, limit: Int = 5): List<DoseStatus> {
        val actionable = statuses.filter { it.state != DoseState.GIVEN && !it.dose.brandDependent }
        val overdue = actionable.filter { it.state == DoseState.OVERDUE }
            .sortedBy { it.overdueDate }
        val due = actionable.filter { it.state == DoseState.DUE }
            .sortedBy { it.dueDate }
        val upcoming = actionable.filter { it.state == DoseState.UPCOMING }
            .sortedBy { it.dueDate }
        return (overdue + due + upcoming).take(limit)
    }

    /** Dose key -> (entry id, date given), inferred by chronological occurrence per vaccine. */
    private fun givenDoses(
        entries: List<ActivityEntity>,
        zone: ZoneId,
    ): Map<String, Pair<String, LocalDate>> {
        // Oldest first; a vaccine listed twice in one entry still counts once that day.
        val occurrences = mutableMapOf<String, MutableList<Pair<String, LocalDate>>>()
        entries.sortedBy { it.startTime }.forEach { entry ->
            val date = Instant.ofEpochMilli(entry.startTime).atZone(zone).toLocalDate()
            entry.vaccine?.vaccines.orEmpty()
                .mapNotNull(::canonicalVaccineName)
                .distinct()
                .forEach { name -> occurrences.getOrPut(name) { mutableListOf() }.add(entry.id to date) }
        }
        val result = mutableMapOf<String, Pair<String, LocalDate>>()
        occurrences.forEach { (name, hits) ->
            val scheduled = dosesByVaccine[name].orEmpty()
            hits.forEachIndexed { index, hit ->
                scheduled.getOrNull(index)?.let { dose -> result[dose.key] = hit }
            }
        }
        return result
    }

    private fun normalize(name: String) = name.lowercase().filter { it.isLetterOrDigit() }
}
