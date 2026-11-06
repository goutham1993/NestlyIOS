# Nestly for iOS — Product & Engineering Spec

This spec describes **everything the iOS app must do** to reach feature parity with the shipping Android app (`com.lifestyle.nestly`). It covers behavior, data, flows, copy and business rules. **Visual design (layout, colors, typography, icons) is intentionally out of scope** — build plain, functional SwiftUI and the visual layer will be designed separately. Where this document gives a string in quotes, use that exact copy.

Android and iOS share **one backend**. A family can contain caregivers on both platforms at the same time, so every value written to the database must be byte-compatible with what Android writes (enum names, units, ID formats, timestamps).

## 0. How to use this folder

| Path | What it is |
|---|---|
| `SPEC.md` | This document. The source of truth for behavior. |
| `supabase-schema.sql` | All Supabase migrations concatenated, in order. **Already deployed — do not run.** Reference for columns, constraints, RLS, RPC. |
| `data/who_growth_lms.json` | WHO LMS growth tables (weight/length/head × boys/girls, months 0–60). Bundle as a resource. |
| `data/milestones.json` | CDC milestone checklist (8 groups, 100 items, with stable keys). Bundle as a resource. |
| `data/vaccine_schedule.json` | CDC dose schedule + "Also recommended" texts. Bundle as a resource. |
| `data/catalogs.json` | Vaccines, routines, foods, medication units, Vitamin D defaults, appointment title hints. |
| `reference/*.kt` | The Android source of the pure-logic pieces (formatting, entry building, trends, growth math, vaccine schedule, notes formatting, importers, DTOs). When this spec and the reference disagree on a detail, **the reference code wins**. Port these line-for-line into Swift. |
| `reference/tests/*.kt` | The Android unit tests. Port every one to XCTest/Swift Testing; they are the acceptance criteria for the logic layer. |
| `reference/ui-strings.md` | Every user-facing string literal in the Android UI, by file and line. Use it for exact copy (empty states, dialogs, labels, confirmations) not spelled out below. |

When handing to Cursor in the new iOS project: copy this whole `ios-spec/` folder into the iOS repo (e.g. `Docs/ios-spec/`), and build in the order in [§24 Build plan](#24-build-plan).

---

## 1. Product overview

Nestly is a shared baby tracker for a family of caregivers. Caregivers log feeds (breast, bottle, solids, combo), pumping, diapers, sleep, routines, baby firsts, growth, milestones, medical events, vaccines and a daily Vitamin D dose. The app shows a live dashboard, a weekly history timeline, trends with period-over-period comparisons, WHO growth percentiles, a CDC milestone checklist, a CDC vaccine schedule tracker, interval reminders, doctor appointments with checklists, shared notes, and import/export (including import from the "Nara Baby" app).

Every caregiver in a family sees the same data in real time.

### Glossary
- **Family** — the sharing unit. Has caregivers and profiles.
- **Caregiver** — a person in a family. Either linked to an auth user (`user_id` set; a "signed-in member") or **name-only** (`user_id` null; e.g. a grandparent who doesn't use the app, or a caregiver imported from another app).
- **Profile** — a child (`CHILD`) or pregnancy (`PREGNANCY`). The UI only creates `CHILD`.
- **Activity** — one logged event. Single table with a `type` discriminator and nullable per-type columns.
- **Selected profile** — the child currently shown everywhere. Stored locally.
- **Current caregiver** — who is using this device; stamped onto entries as `created_by_id` / `updated_by_id`.

---

## 2. Tech stack & architecture

- **iOS 17.0+**, Swift 5.9+/Swift 6 language mode where practical, **SwiftUI**, Swift Concurrency, `@Observable` (Observation framework).
- **supabase-swift** (`Supabase` package: Auth, PostgREST, Realtime V2, Storage). Pin a current 2.x version.
- No local database. **Online-only** (see §4). No SwiftData/Core Data.
- Local preferences: `UserDefaults(suiteName: "group.<bundle-id>")` — an **App Group** so the widget, Live Activity and App Intents read the same values.
- Auth session storage: supabase-swift `KeychainLocalStorage` configured with a **shared keychain access group** so the widget extension and App Intents can make authenticated calls (quick bottle log from widget / Siri).
- Targets:
  1. `Nestly` (app)
  2. `NestlyWidgets` (WidgetKit extension: home-screen Quick Log widget, StandBy "Next feed" widget, Live Activity UI)
  3. Shared Swift package / framework `NestlyCore` containing models, Supabase client, repositories, logic (Format, EntryBuilder, Trends, Growth, Vaccines, Reminders, Importers). Both app and extension link it.
- Suggested layering (mirror Android):
  - `Backend` — Supabase client singleton, DTOs, `RefreshBus`, `DataErrors`, `RealtimeSync`, `PhotoStore`.
  - `Repositories` — `AuthRepository`, `FamilyRepository`, `ActivityRepository`, `ReminderRepository`, `AppointmentRepository`, `NoteRepository`.
  - `Logic` — pure, synchronous, unit-tested; no Supabase imports.
  - `Features` — one folder per screen, each with an `@Observable` view model.

### 2.1 Supabase configuration
```
URL:              https://kuyskumyayiwpyiwhkup.supabase.co
Publishable key:  sb_publishable_zZmg34taTJm9k57PdYBEug_JGcRZ21_
Storage bucket:   activity-photos
```
Only the publishable (anon) key ships in the client. RLS is the security boundary. **Never** embed a service-role key.

Auth: email + password only. Email confirmation may be enabled on the project (handle "no session after sign-up", §9.1).

---

## 3. Backend contract

Full DDL is in `supabase-schema.sql`. Summary of what the client relies on:

### 3.1 Common row conventions
- `id uuid` — **generated client-side** (`UUID().uuidString.lowercased()`).
- `created_at`, `updated_at` — `timestamptz`. Client sets `updated_at = now` on every write. Send ISO-8601 with fractional seconds and `Z` (e.g. `2026-11-05T14:03:22.123Z`). Parse leniently (with/without fraction, with offset).
- `deleted_at timestamptz` — **soft delete**. Every query filters `deleted_at IS NULL`.
- `server_updated_at` — server-maintained; ignore.
- `version int` — optimistic lock (see §3.4). Present on activity, profile, caregiver, family, reminder, appointment, appointment_question, note.
- Server trigger `keep_newer_row` silently drops an update whose `updated_at` is older than the stored row.
- Enum columns store the **exact uppercase names** listed below.
- Storage units: **mL, kg, cm, °C** always. Display units are a local preference only.
- Internally use `Date` (or epoch ms where the reference code uses ms). Birth dates are `date` columns: `"YYYY-MM-DD"`, treated as a calendar date in the device time zone.

### 3.2 Tables

**family** — `id, name, created_by (default auth.uid()), created_at, updated_at, deleted_at, version`.

**caregiver** — `id, family_id, user_id (nullable), name (non-blank), role ('OWNER'|'MEMBER'), created_at, updated_at, deleted_at, version`.
Unique: `(family_id, name)`, `(family_id, user_id)`.

**profile** — `id, family_id, name, birth_date date?, adjusted_birth_date date?, sex ('MALE'|'FEMALE'|'OTHER')?, profile_type ('CHILD'|'PREGNANCY'), timestamps, version`.

**activity**

| Column | Notes |
|---|---|
| `id, family_id` | |
| `profile_id` | **null for `PUMP`** (pumping belongs to the parent, not a child). Non-null for all other types. |
| `type` | `BOTTLE_FEED, BREASTFEED, PUMP, DIAPER, GROWTH, MILESTONE, SLEEP, SOLIDS, ROUTINE, BABY_FIRST, MEDICAL, VACCINE, VITAMIN_D` |
| `start_time` | timestamptz, required |
| `end_time` | timestamptz?, must be ≥ start |
| `time_zone` | IANA id, e.g. `America/Chicago` (`TimeZone.current.identifier`) |
| `note` | text? |
| `created_by_id`, `updated_by_id` | caregiver ids? |
| `bottle_milk_type` | `BREAST_MILK, FORMULA, MIXED` |
| `bottle_breast_milk_ml, bottle_formula_ml, bottle_total_ml` | numeric |
| `bottle_formula_name` | text |
| `pump_duration_sec` | int |
| `pump_left_ml, pump_right_ml, pump_total_ml` | numeric |
| `breast_begin_side, breast_end_side` | `LEFT, RIGHT` |
| `breast_left_duration_sec, breast_right_duration_sec` | int |
| `breast_is_manual_entry` | bool |
| `diaper_type` | `WET, DIRTY, MIXED, DRY` |
| `diaper_color` | `YELLOW, GREEN, BROWN, BLACK, RED, WHITE, ORANGE` |
| `diaper_texture` | `RUN, MUSH, SOLID, MUCOUS, SEEDY, HARD` |
| `diaper_detail` | text |
| `diaper_has_rash` | bool |
| `growth_weight_kg, growth_height_cm, growth_head_cm` | numeric |
| `milestone_title, milestone_key` | text (key like `m6_3`, see milestones.json) |
| `solids_meal_type` | `BREAKFAST, LUNCH, DINNER, SNACK` |
| `solids_foods` | `text[]` |
| `routine_name` | text |
| `baby_first_title` | text |
| `medical_temperature_c` | numeric |
| `medical_medication_name, medical_dose, medical_dose_unit` | text (dose is text) |
| `vaccine_vaccines` | `text[]` (exact catalog names) |
| `photo_path` | storage object path `{family_id}/{activity_id}/{filename}` |
| `combo_group_id` | uuid? — shared by the two rows of a combo feed |
| timestamps, `version` | |

The exact DTO ↔ column mapping (including which nested "details" object each column belongs to) is in `reference/Dtos.kt`. Port it as `Codable` structs with `CodingKeys` in snake_case.

Vitamin D rows: `type = VITAMIN_D`, `medical_medication_name = "Vitamin D"`, `medical_dose` (e.g. `"400"`), `medical_dose_unit` (e.g. `"IU"`, only set if a dose is set).

**reminder** — `id, family_id, caregiver_id, profile_id?, kind ('FEED'|'PUMP'|'DIAPER'|'SLEEP'), interval_minutes > 0, enabled bool, timestamps, version`. Personal: each caregiver has their own reminders. Unique (nulls not distinct) on `(caregiver_id, profile_id, kind)`. PUMP reminders have `profile_id = null`.

**appointment** — `id, family_id, profile_id, title (non-blank), doctor_name?, location?, starts_at, time_zone, notes?, reminder_lead_minutes (null|0|60|1440), timestamps, version`.

**appointment_question** — exists, **unused by the UI**. Do not build UI for it. (Questions live as checkbox lines inside `appointment.notes`.)

**note** — `id, family_id, profile_id, title?, body?, timestamps, version`. Title or body must be non-blank.

**family_invite** — `id, family_id, code (DB default: 8 chars from ABCDEFGHJKLMNPQRSTUVWXYZ23456789), created_by, expires_at (now+7d), accepted_by, accepted_at, revoked_at`.

**user_settings** — exists, **unused**. Preferences are device-local.

### 3.3 RLS (what the client can do)
- Members of a family have full read/write on that family's rows.
- Reminders are only visible/writable by their owning caregiver's user.
- Caregiver insert is allowed for: a name-only MEMBER; upsert of an existing caregiver in my family; or the creator of a brand-new, still-empty family inserting themselves as `OWNER` with their `user_id`.
- A trigger prevents changing `family_id` or `user_id`, and only OWNERs may change roles or remove other signed-in members.

### 3.4 Optimistic locking (all updates)
```
UPDATE <table> SET ..., version = old.version + 1, updated_at = now
WHERE id = :id AND version = :old.version
```
Then **re-read** the row by id. If the re-read `version != old.version + 1` (i.e. our update didn't apply), throw `ConflictError` with message:
> "This entry was changed by someone else. Showing the latest version."

The editor then reloads the latest row and shows that message. Inserts send `version = 0` (or omit; DB default). Soft delete is a version-checked update setting `deleted_at = now`.

### 3.5 RPC
`public.accept_family_invite(code text, caregiver_name text) returns table(family_id uuid, caregiver_id uuid)`
- If the caller already has a caregiver row in that family → un-deletes it and returns it.
- Else if a name-only caregiver with the same name exists → links it to the caller (error if that name is linked to another account).
- Else inserts a new `MEMBER`.
- Marks the invite accepted.
- Errors (match on message substring): `invite is invalid or expired`, `that name is already used by another member`, `caregiver name is required`.

### 3.6 Storage
Bucket `activity-photos`: private, 10 MB max, `image/jpeg|png|webp|heic`. Path `{family_id}/{activity_id}/{filename}`; access limited to members of the family in the first path segment. Upload with `upsert: true`. Download with authenticated download (not public URL). On iOS, re-encode picked photos as JPEG (quality ~0.85, max ~2048px long edge) named `{uuid}.jpg`, `contentType: image/jpeg`.

### 3.7 Realtime
- Tables are in the `supabase_realtime` publication: activity, profile, caregiver, family, reminder, appointment, appointment_question, note.
- One channel per family: name `nestly-{familyId}`. Subscribe to postgres changes (`*`, schema `public`) for each table with filter `family_id=eq.{familyId}`; for `family` use `id=eq.{familyId}`.
- **Payloads are ignored.** Every event just bumps that table's refresh tick (§4).

---

## 4. Data layer: strict online-only model

There is no cache/DB. Every screen reads through a **refetch stream**.

### 4.1 RefreshBus
A singleton holding one monotonically increasing tick per table: `activity, profile, caregiver, family, reminder, appointment, appointmentQuestion, note`. API: `bump(_ table)`, `bumpAll()`, `ticks(for table) -> AsyncStream<Int>`.

Ticks are bumped by:
1. Every local write (insert/update/delete) to that table.
2. Realtime events for that table.
3. App foreground (`scenePhase == .active`) → `bumpAll()`.
4. Network reconnect (`NWPathMonitor` transition to satisfied) → `bumpAll()`.
5. Manual **Retry** in the error banner → `bumpAll()`.
6. Realtime (re)subscribe success → `bumpAll()`.

### 4.2 Refetch stream semantics (port `RefetchFlow` tests)
`func refetch<T>(tables: [Table], fetch: () async throws -> T) -> AsyncStream<T>`:
- Fetches once immediately, then again on every tick of any listed table (coalesce bursts; latest wins, cancel in-flight).
- On success: emit value, clear the global error.
- On failure: report to `DataErrors`; **re-emit the last good value** if there is one; if the *first* fetch fails, emit nothing (the consumer stays in its loading state).
- **Auth gating** (`refetchWhenAuthenticated`): do not fetch until the auth status is `.signedIn`. Anonymous reads during session restore return empty results and would wrongly route to onboarding. When the auth user changes, restart.

### 4.3 DataErrors (global banner)
Single observable `message: String?`. Default message: "Couldn't reach the server. Check your connection." The root view shows a dismissible banner with a **Retry** action (bumpAll) whenever it's non-nil.

### 4.4 RealtimeSync
- Starts after sign-in. Family id = selected profile's `family_id` (wait up to 20 s for profiles), else first fetched profile's family, else first fetched family's id.
- Subscribe with retry + exponential backoff: 2 s initial, ×2, max 60 s, 15 s subscribe timeout.
- On subscribe → `bumpAll()`.
- Resubscribe when the auth user changes or the selected profile's family changes. Unsubscribe on sign-out.

---

## 5. Domain models

Mirror the Android models (see `reference/Dtos.kt`, `reference/EntryModel.kt`).

```swift
enum ActivityType: String, Codable { case BOTTLE_FEED, BREASTFEED, PUMP, DIAPER, GROWTH, MILESTONE, SLEEP, SOLIDS, ROUTINE, BABY_FIRST, MEDICAL, VACCINE, VITAMIN_D }
enum MilkType: String { case BREAST_MILK, FORMULA, MIXED }
enum BreastSide: String { case LEFT, RIGHT }
enum DiaperType: String { case WET, DIRTY, MIXED, DRY }
enum DiaperColor: String { case YELLOW, GREEN, BROWN, BLACK, RED, WHITE, ORANGE }
enum DiaperTexture: String { case RUN, MUSH, SOLID, MUCOUS, SEEDY, HARD } // display: Runny, Mushy, Solid, Mucousy, Seedy, Hard
enum MealType: String { case BREAKFAST, LUNCH, DINNER, SNACK }
enum Sex: String { case MALE, FEMALE, OTHER }           // UI offers Boy/Girl only
enum ProfileType: String { case CHILD, PREGNANCY }
enum CaregiverRole: String { case OWNER, MEMBER }
enum ReminderKind: String { case FEED, PUMP, DIAPER, SLEEP }
enum AppointmentReminderLead: Int? { NONE=nil "No reminder", AT_TIME=0 "At appointment time", ONE_HOUR=60 "1 hour before", ONE_DAY=1440 "1 day before" }
```

`Activity` holds common fields + optional detail structs: `BottleDetails, PumpDetails, BreastfeedDetails, DiaperDetails, GrowthDetails, MilestoneDetails, SolidsDetails, RoutineDetails, BabyFirstDetails, MedicalDetails (also used by VITAMIN_D), VaccineDetails`, plus `comboGroupId`, `photoPath`, `version`.

### 5.1 Entry kinds (UI-level)
`EntryKind`: `BREASTFEED, BOTTLE, SOLIDS, COMBO` (Feed card) · `PUMP` · `DIAPER` · `SLEEP` · `ROUTINE` · `BABY_FIRST` · `GROWTH, MILESTONE` (Growth card) · `MEDICAL, VACCINE, VITAMIN_D` (Health card). `COMBO` = one breastfeed row + one bottle row sharing a `combo_group_id`.

---

## 6. Local preferences (App Group UserDefaults)

| Key | Type | Default | Notes |
|---|---|---|---|
| `selected_profile` | String? | nil | Falls back to the first profile (by `created_at` asc). |
| `current_caregiver` | String? | nil | See §8.2 for resolution. |
| `card_order` | [CardKind] | `FEED, PUMP, DIAPER, SLEEP, ROUTINE, BABY_FIRSTS, GROWTH, HEALTH` | Dashboard card order. |
| `disabled_toggles` | Set<ActivityToggle> | empty | See §11.6. |
| `filters` | Set<FilterOption> | empty (= show all) | `NOTES, PHOTOS, FEED, PUMP, DIAPER, SLEEP, ROUTINE, HEALTH`. |
| `unit_volume` | `ML`/`OZ` | `ML` | |
| `unit_weight` | `KG`/`LB` | `KG` | |
| `unit_length` | `CM`/`IN` | `CM` | |
| `unit_temperature` | `C`/`F` | **`F`** | |
| `default_bottle_ml` | Double? | nil | nil/0 = off. Stored in mL. |
| `active_timers` | JSON | — | See §7. Must be in the App Group (Live Activity intents mutate it). |

Unit conversions (port `reference/Units.kt`): `ML_PER_OZ = 29.5735`, `LB_PER_KG = 2.2046226218`, `IN_PER_CM = 0.3937007874`, `°F = °C × 9/5 + 32`. Display decimals: oz 1, mL 0, lb 1, kg 2, length 1, temperature 1.

---

## 7. Active timers (persistent stopwatches)

Port `reference/ActiveTimerStore.kt`. Timer ids: `BREAST_LEFT, BREAST_RIGHT, PUMP, SLEEP`. Each stores `accumulatedMs`, `runningSince: epochMs?`, `sessionStart: epochMs?` (when it was first started in this session). Ops: `start, pause, toggle, reset, elapsed(now) = accumulated + (now − runningSince if running)`. State survives app kill/relaunch (persisted on every change).

Rules:
- Starting one breast side pauses the other.
- Timers are only used for **new** BREASTFEED, COMBO (breastfeed part), PUMP and SLEEP entries.
- Saving or discarding the entry clears the involved timers.
- **iOS addition — Live Activity** (§21.5) mirrors any running/paused timer.

---

## 8. Session, family and selection

### 8.1 Auth state machine
`loading → signedOut | signedIn`. Once signed in, never go back to `loading` (token refresh/"initializing" events keep `signedIn`). Use `supabase.auth.authStateChanges`.

### 8.2 FamilyRepository (port behavior)
- `profiles`: refetch of non-deleted profiles in all my families, ordered by `created_at` asc.
- `selectedProfile`: stored `selected_profile` if present in list, else first.
- `caregivers`: caregivers of the selected profile's family, ordered by `name`.
- `currentCaregiver`: caregiver whose `user_id == auth.uid`, else stored `current_caregiver` if in list, else first.
- `hasFamily`: any non-deleted family visible to me.
- `addChild(name, sex, birthDate, caregiverName)`:
  - Target family = `currentFamilyId()` (first profile's family, else first non-deleted family I can see).
  - If there is **no family at all**: create one (`family.name = null`) and insert an `OWNER` caregiver `{user_id: me, name: caregiverName.trimmed or "Caregiver"}`, store it as current caregiver.
  - Else if `caregiverName` non-blank and no caregiver with that name exists in the family: insert name-only `MEMBER`.
  - Insert profile (`profile_type = CHILD`), select it. Bump profile, caregiver, family ticks.
  - **Intentional fix vs Android:** Android creates a new family whenever there are *no profiles*, even if the user already created/joined a family during onboarding (sign-up auto-creates one), which leaves an empty orphan family — or, for someone who joined an empty family by invite, puts the child in a family nobody else can see. iOS must reuse the existing family.
- `createFamily(caregiverName)` — insert family (`name = null`) + OWNER caregiver (as above), no profile.
- `joinWithInvite(code, name)` — call RPC with `code.trimmed` and `name.trimmed`; empty result → "Invite is invalid or expired". Store returned caregiver id as current caregiver.
- `createInvite(familyId)` — insert `{id, family_id}` then read back `code`.
- `updateChild(profile)` — version-checked.
- `addCaregiver(name)` — name-only `MEMBER`; if the name already exists return the existing one.
- `currentFamilyId` — selected profile's family, else first family.
- `clearCurrentFamilyData` (DEBUG builds only) — hard-delete in order: activity, reminder, appointment_question, appointment, note, family_invite, profile, family, then caregivers; also delete all storage objects under `{familyId}/`.

### 8.3 Selecting a child
Parity with Android: the selected child changes only via the Family screen (editing/saving a child selects it). Adding a child selects it.

---

## 9. App shell & navigation

### 9.1 Root gate
1. Auth `loading` → loading screen.
2. `signedOut` → **Auth screen**.
3. `signedIn`:
   - profiles not yet loaded → if `DataErrors.message` set: error screen with message + **Retry**; else "Loading your family…".
   - profiles empty → wait for `hasFamily` to load, then **Onboarding** (`hasFamily` variant).
   - profiles non-empty → **Main tabs**.

### 9.2 Tabs
`Activity`, `History`, `Trends`, `Account`.

### 9.3 Pushed routes
`growth/{metric}` (WEIGHT|HEIGHT|HEAD), `trends/{metric}/{window}`, `editActivities`, `milestones`, `vaccinations`, `reminders`, `appointments`, `appointments/new`, `appointments/{id}`, `notes`, `notes/new`, `notes/{id}`, `family`, `settings`, `units`, `email`, `communication`, `subscription`, `help`, `import`, **`nightstand`** (iOS, full-screen).

### 9.4 Entry sheet (global overlay)
Presentable from any screen via `EntryRequest.new(kind, milestone: MilestoneItem? = nil, vaccines: [String] = [])` or `EntryRequest.edit(activityId)`. One sheet at a time.

### 9.5 Deep links (URL scheme `nestly://`)
- `nestly://entry/{EntryKind}` — open the entry sheet for a new entry (widget buttons, App Shortcuts).
- `nestly://appointment/{id}` — open appointment detail (appointment notification tap).
- `nestly://nightstand` — open nightstand mode.
- Notification taps for interval reminders open the app (Activity tab).

---

## 10. Auth & onboarding

### 10.1 Auth screen
Modes: **Sign in** / **Create account** (toggle).
- Sign in: email, password.
- Sign up: email, password, "Your name (as caregiver)".
- After sign-up: if a session exists immediately → `createFamily(name)`; else show "Check your email to confirm your account, then sign in." (Remember the name locally and use it if they later onboard.)
- Friendly error mapping (substring match on the error message, case-insensitive, in this order):
  - "rate limit" → "Supabase's built-in email limit was hit, so no confirmation email was sent and the account wasn't created. For testing, turn off \"Confirm email\" in Supabase Dashboard → Authentication → Providers → Email, then try again."
  - "Invalid login" → "Wrong email or password."
  - "already registered" → "That email already has an account. Sign in instead."
  - "invite" → "That invite code is invalid or expired."
  - other → the server message, or "Something went wrong. Check your connection and try again." if blank.
- Root-gate error screen title: "Couldn't reach Nestly".
- Onboarding intro copy: "Start a new family, or join one with an invite code from another caregiver." / "Add your first child to start tracking, or do a one-time import of your Nara Baby history."

### 10.2 Onboarding — no family yet
- Field "Your name" → **Create my family** (`createFamily`).
- Or field "Invite code" → **Join with invite code** (`joinWithInvite(code, name)`; name required).
- Sign out button.

### 10.3 Onboarding — family exists, no children
- **Add child** → Add Child dialog (§11.1).
- **Import from Nara instead** → file picker → Nara import (§19.2), with a status line showing progress/result.
- Sign out button.

---

## 11. Activity tab (dashboard)

### 11.1 Header & empty state
- Child name, age (`Format.age`, e.g. "2 weeks, 3 days old" / "Born today"), today's date (`headerDate` "EEE, MMM d").
- **Summary** button → Summary sheet (§11.4).
- **More** menu: Set Reminders, Doctor Appointments, Notes, Edit Activities.
- If no profiles: Welcome with **Add Child** (dialog: Name, Boy/Girl, Birthdate, Your name) and **Import from Nara**.

### 11.2 Dashboard data
- Activities for the selected profile (plus `profile_id IS NULL` PUMP rows) since **start of yesterday**.
- Latest entry per card type; all GROWTH rows; all MILESTONE rows; latest MEDICAL; latest VACCINE.
- Feed interval = FEED reminder's `interval_minutes` for me+child (default 180).
- Clock: tick every 1 s while any timer runs, else every 30 s.
- Range query semantics (`ActivityRepository.range`): `family_id = F AND deleted_at IS NULL AND (profile_id = P OR profile_id IS NULL) AND start_time >= from AND start_time < to ORDER BY start_time DESC`. `latestOf(types)` with a blank profile matches only `profile_id IS NULL`.

### 11.3 Cards
Rendered in `card_order`, only if visible (§11.6). Each card (except Health) has an **Add** action and a **today list** of today's entries (newest first) with **Show More / Show Less** (collapsed shows a few rows) and a footer link to History. Tapping a row edits it.

- **Feed** — Add opens a picker of enabled kinds among Breastfeed, Bottle, Solids, Combo, **always plus Vitamin D**. Rows:
  - "Last feeding": time-ago + value (oz 1 decimal / mL integer, or breastfeed duration). Feed types = BOTTLE_FEED, BREASTFEED, SOLIDS.
  - If a breast timer is running: in-progress "Breastfeeding" row with elapsed.
  - "Next feeding": `Format.nextFeeding` (§13) using last feed + interval.
  - Today list **expanded by default**.
- **Pump** — "Last session" + amount; in-progress row when the pump timer runs.
- **Diaper** — "Last change" + type label. Footer reads "View History".
- **Sleep** — while running: "Sleeping since {time}" + elapsed. Else "Last sleep": time-ago measured from **end** time + duration.
- **Routine** — empty text "Track a routine or create your own".
- **Baby Firsts** — empty text "Track memorable moments"; shows relative day instead of time-ago.
- **Growth** — rows Weight / Height / Head (latest values, display units; each opens `growth/{metric}`), and "Milestones  N of 100" (N = distinct milestones logged) → Milestones screen.
- **Health** (no Add button):
  - Vitamin D: "Given today at {time}" or "Not given today". Tap → edit today's entry if given, else new VITAMIN_D entry. (Uses `DailyDose.givenAt`: earliest VITAMIN_D within today.)
  - Medical: latest's day + time with temperature or medication. Tap → new MEDICAL entry.
  - Vaccine: relative day + "N vaccines". Tap → Vaccinations screen.
- Bottom **Edit Activities** button.

### 11.4 Summary sheet
Two columns/segments: **Today** and **Last 24 Hours**. One line per type in this order: BREASTFEED, BOTTLE, SOLIDS, PUMP, DIAPER, SLEEP, ROUTINE, BABY_FIRST, GROWTH, MILESTONE, MEDICAL, VACCINE, VITAMIN_D. Only types with entries. Port `reference/Summary.kt` exactly:
- Bottle: total, breast milk, formula. Pump: total. Breastfeed: total time + L/R. Diaper: "x wet, y dirty" (MIXED counts as both). Sleep: total.
- Empty: "Nothing logged yet."

### 11.5 Filters sheet
Toggles: Notes, Photos, Feed, Pump, Diaper, Sleep, Routine, Health → **Apply** (persist). Semantics (port `reference/ActivityFilters.kt`):
- Type filters are OR'ed: Feed = BOTTLE_FEED/BREASTFEED/SOLIDS; Pump; Diaper; Sleep; Routine = ROUTINE/BABY_FIRST; Health = MEDICAL/VACCINE/VITAMIN_D. (Growth/Milestone pass only when no type filter is set.)
- Notes = has non-blank note; Photos = has photo. These are AND'ed on top.
- Empty set = everything.
Filters apply to the History tab (and dashboard today lists).

### 11.6 Edit Activities
- Drag to reorder the 8 cards.
- Toggle hierarchy:
  - Feed: Breastfeeding; Bottle Feeding (sub-toggles: Breast Milk, Formula); Solid Feeding; Combo Feeding.
  - Pump; Diaper Changes; Sleep; Routines; Baby Firsts; Growth; Health.
- `ActivityToggle`: `BREASTFEEDING, BOTTLE_FEEDING, BOTTLE_BREAST_MILK, BOTTLE_FORMULA, SOLID_FEEDING, COMBO_FEEDING, PUMPING, DIAPER_CHANGES, SLEEP, ROUTINES, BABY_FIRSTS, GROWTH, HEALTH`.
- A card is visible if any of its top-level toggles is enabled (the two bottle sub-toggles don't count).
- **Save** persists order + toggles.

### 11.7 Row display helpers (port `reference/ActivityDisplay.kt`)
- Label: Bottle → milk type name ("Breast Milk"/"Formula"/"Mixed") else "Bottle"; Solids → meal name; Pump → ""; Diaper → "Wet"/"Dirty"/"Wet + Dirty"/"Dry"; Routine/Baby First/Milestone → name/title; Medical → medication name; Vaccine → joined names; Vitamin D → "Vitamin D".
- Detail: volume; breastfeed "L 10m  R 5m"; durations; foods joined; temperature; Vitamin D dose + unit.
- Bar value: bottle total mL, pump total mL, breastfeed seconds, sleep seconds. Bar width = value / max of that type that day, minimum 8%.
- Row: time ("6:14pm"), label, bar, detail; note/photo indicators.

---

## 12. Entry sheet (create / edit)

Port `reference/EntryModel.kt`, `reference/EntryBuilder.kt`, `reference/EntryController.kt`. The draft is a value type; `build(draft, context) -> [Activity]` and `draftOf([Activity]) -> Draft` are pure and tested.

### 12.1 Common to every form
- **Time row** with separate date and time tap targets. Date picker keeps time-of-day; time picker keeps the date. Changing start drops an end time that falls before it.
- **Notes** (multi-line). Trimmed; empty → null.
- **Add Photo / Remove Photo** (PhotosPicker or camera). On save, upload local photo first (§3.6), store path.
- Header: **Save** (enabled only when `canSave`), **Delete** (edit mode; soft delete, confirm), discard/close (clears timers for new timed entries).
- `updated_by_id` = current caregiver; new rows also get `created_by_id`.

### 12.2 `canSave` rules
| Kind | Rule |
|---|---|
| Breastfeed | left + right seconds > 0 |
| Bottle | amount > 0 or a milk type chosen |
| Solids | meal chosen or ≥ 1 food |
| Combo | breastfeed part saveable or bottle part saveable |
| Pump | seconds > 0 or computed total > 0 |
| Diaper | wet or dirty or dry |
| Sleep | end > start |
| Routine | name non-blank |
| Baby First | title non-blank |
| Growth | any measurement |
| Milestone | title non-blank |
| Medical | temperature or medication name |
| Vaccine | ≥ 1 vaccine |
| Vitamin D | always |

### 12.3 Build rules
- **PUMP** rows: `profile_id = null`.
- **Breastfeed**: `end = start + left + right`. Begin/end side default to whichever side is non-zero (LEFT if both). `breast_is_manual_entry` preserved from existing row (false for new).
- **Bottle**: `bottle_total_ml = amount`; `bottle_breast_milk_ml` only for BREAST_MILK; `bottle_formula_ml` + `bottle_formula_name` only for FORMULA.
- **Pump**: `end = start + seconds`; `pump_duration_sec = seconds`; left/right only in LEFT_RIGHT mode; total = left+right in LEFT_RIGHT mode, else entered total.
- **Diaper**: type = MIXED if wet&dirty, else DIRTY / WET / DRY. Color & texture only if dirty. `diaper_has_rash`.
- **Sleep**: `end_time` from draft.
- **Medical**: draft temperature is in the display unit; store °C. Medication name, dose (text), dose unit.
- **Vitamin D**: MedicalDetails with name "Vitamin D", dose, unit only if dose set. Defaults 400 IU.
- **Combo**: 0–2 rows (breastfeed + bottle); share a new `combo_group_id` only when both exist. Editing a combo loads both rows via `combo_group_id`.
- **Growth**: inputs in display units → kg / cm.
- **Milestone**: title + key (from the catalog item if opened from Milestones).

### 12.4 Controller behavior
- **Load (edit)**: fetch row (and combo sibling), resolve photo (download to cache). Failure → "Couldn't load this entry. Check your connection."
- **New Bottle/Combo**: prefill amount with `default_bottle_ml` (if set). Load `lastBottleMl`; when no amount is entered show "Use last amount: {X}?" with **Yes**.
- **Breastfeed**: load last breastfeed's end side → show a small "last side" caption under that side's timer button.
- **New Vitamin D**: prefill last dose + unit if the draft still has defaults.
- **Initial draft**: start = now; for timed kinds `startTimeSet = false` → the start row shows "Add" until set or a timer starts.
- **Effective draft with timers** (new timed entries):
  - Breastfeed: left/right seconds from timers. Begin side = side whose session started first. End side = running side, else the other used side. If start not set → earliest timer session start.
  - Pump: seconds from timer; start = session start if not set.
  - Sleep: start = session start; end = start + elapsed.
  - `setTimerDuration` edits the timer (or the draft when editing an existing entry).
- **Save**: requires a selected profile, else "No child selected. Check your connection and try again." → `saveAll(rows, existing)` → clear timers → dismiss → reschedule reminders in background → reload widgets (`WidgetCenter.shared.reloadAllTimelines()`) → end Live Activity.
  - `ConflictError` → reload latest into the form, show its message.
  - Other error → "Couldn't save. Check your connection and tap Save to retry."
- **saveAll**: for each row: upload photo if local → insert if new (no existing row with that id) else version-checked update + re-read; set `updated_at = now`. For edits of a combo where one part was removed, soft-delete that part.
- **Delete**: version-checked soft delete; error → "Couldn't delete. Check your connection and try again."
- **Default amount prompt** (after saving a *new* Bottle/Combo whose amount was typed manually and differs from the default by > 0.5 mL):
  - No default: "Set as default amount?" — **Yes, set default** / **Not now**.
  - Has default: "Update default amount?" — **Yes, update default** / **No, keep default**.
  (Port `DefaultBottleAmountTest`.)

### 12.5 Forms
- **Breastfeed**: Left and Right timer buttons (readout `MM:SS` under 1 h, `H:MM` after; tap to start/pause; long-press/edit to type a duration), last-side hint, Start Time, Total Time (sum).
- **Bottle**: Breast Milk / Formula choice (each option shown only if its toggle is enabled or already selected), Start Time, Amount (display units), "Use last amount" row, Formula name (when Formula).
- **Solids**: Breakfast/Lunch/Dinner/Snack, Start Time, food multi-select from catalog + "+ Add your own" (custom foods for this entry).
- **Combo**: segmented control Breastfeed | Bottle Feed, showing the respective sub-form; both parts can be filled.
- **Pump**: mode "Left / Right" | "Total" (default Total); stopwatch with Start Timer / Pause / Resume Timer and Reset; Start Time; Total Time (editable); amounts (left & right, or total).
- **Diaper**: Time; toggles Wet, Dirty, Dry (Dry clears the others; Wet/Dirty clear Dry); if Dirty: Color chips (with swatches) and Texture chips (Runny, Mushy, Solid, Mucousy, Seedy, Hard); Diaper Rash switch.
- **Sleep**: stopwatch ("Total Time"), Start Time, End Time.
- **Routine**: Time; picker of catalog routines + custom name.
- **Baby First**: Date (date-only); title text field.
- **Growth**: Date; Weight, Height, Head (display units).
- **Milestone**: title (read-only when from catalog, else editable); Date.
- **Medical**: Time; Temperature (display unit); Medication dialog with name, dose and unit chips (mL, mg, drops, tsp).
- **Vaccine**: Date; multi-select from catalog (pre-selected when opened from Vaccinations).
- **Vitamin D**: Time; Dose; unit chips IU / drops / mL.

---

## 13. Formatting (port `reference/Format.kt` + `FormatTest`)

| Function | Output examples |
|---|---|
| `time` | "6:14pm" (lowercase am/pm, no space) |
| `relativeDay` | "Today", "Yesterday", "Tomorrow", "Mar 4", "Mar 4, 2025" (other year) |
| `countdown` | "in 3 days", "in 2 weeks", "in 4 months", "in 1 year"; past → "… ago" |
| `headerDate` | "Thu, Nov 5" |
| `longDateTime` | "Nov 5 2026 6:14pm" |
| `age` | "2 weeks, 3 days old", "Born today" |
| `ago` | "Just now", "12m ago", "3h 5m ago", "2d ago" |
| `duration` | "1h 5m", "12m 5s", "45s" |
| `nextFeeding` | "Next feeding in {dur, rounded up} at {time}", "Next feeding due now", "Next feeding overdue by {dur} · due {time}" |
| `number` | up to 2 decimals, trailing zeros trimmed |

Use `en_US_POSIX`-style fixed patterns for these strings (they're product copy), but use the device time zone.

---

## 14. History tab

Port behavior from Android `ui/history`.
- Header: selected day's date. **Filters** button with active-count badge (§11.5). **More** menu: Set Reminders.
- **Week strip**: 7 days, week start = `Calendar.current.firstWeekday`; month label(s); previous-week arrow (and next, not beyond the current week); horizontal swipe changes week. Tapping a day selects it.
- **7×24 timeline grid**: columns = days, rows = hours. Each entry is a colored bar in its category color at its start time; duration types (sleep, breastfeed, pump) span their duration. Tap a bar → edit entry. Tap a column → select that day. Night bands shaded before 06:00 and after 18:00. Dashed lines every 3 h. A "now" line on today.
- **Selected-day list**: header "Weekday, Mon d" + "N entries" (or "Nothing logged."), then rows (§11.7), tap to edit.
- Filters apply to grid and list. Data = activities in the visible week (range query).

---

## 15. Trends tab

Port `reference/TrendsAggregator.kt`, `reference/TrendsUi.kt` and `TrendsAggregatorTest` exactly — this is where subtle bugs hide.

- **Windows**: 1d, 7d, 14d (picker). Current window ends at end of today; previous window is the same length immediately before.
- Data: activities from start of previous window to now.
- Each metric row: title, current value summary, delta vs previous window (null if either window has no samples), comparison text.
- **Meaningful-delta thresholds**: count 0.05, volume 1.5 mL, duration 1 s. Below threshold → "Same as the previous day/N days".
- Comparison text: counts "More/Fewer {noun}", duration *averages* "Longer/Shorter", else "More/Less", followed by "than the previous day" (1d) or "than the previous N days".
- Summary text: "{v} {noun} per day" (per-day stats) or "{v} average".

### 15.1 Metrics
| Section | Metric | Stat | Notes |
|---|---|---|---|
| Feed | Feed Sessions | count / day, breakdown | noun "sessions"; combo group = 1 session (series COMBO) |
| | Total BF Hours | duration / day | |
| | Daytime BF Hours | duration / day | overlap with 06:00–18:00 |
| | Nighttime BF Hours | duration / day | |
| | BF Session Length | average | |
| | Amount Bottlefed | volume / day, breakdown | Breast Milk, Formula, Unspecified |
| | Bottle Size | average | |
| | Time Btwn Feedings | average | gaps between consecutive feed starts |
| Pump | Pump Sessions | count / day | |
| | Amount Pumped | volume / day | |
| | Total Pump Hours | duration / day | |
| Diaper | Total Diapers | count / day, breakdown | Wet, Dirty, "Wet + Dirty", Dry |
| | Daytime Diapers / Nighttime Diapers | count / day | |
| Sleep | Total Sleep, Daytime Sleep, Nighttime Sleep | duration / day | sleeps split across days and day/night bands by overlap |
| | Longest Sleep | average of per-day max | |
| | Daytime Naps | count / day | noun "naps"; sleeps that **start** in daytime |
| | Daytime Nap Length | average | |
| | Wake Window | average | positive gaps between consecutive sleeps |

Per-day value = window total / number of days. Average = mean of samples.

### 15.2 Trend detail (`trends/{metric}/{window}`)
- Window menu; previous/next period arrows (no future).
- **Share** (ShareLink): "{child} · {metric} ({range}): {summary}".
- Tabs:
  - **Calendar** — days with a mark per contributing entry; tap → edit entry.
  - **Graph** — stacked bars per day by series, dashed **AVG** line; Y-axis floor: 5 (counts), 100 mL / 4 oz (volume), 1 h (duration). Use Swift Charts.
  - **Entries** — list of contributing entries.
- Summary block with breakdown by series and comparison ("Same as …" when equal).

---

## 16. Health & development screens

### 16.1 Growth (`growth/{metric}`)
Port `reference/GrowthPercentiles.kt` + `GrowthPercentilesTest`; load LMS from `data/who_growth_lms.json` (tables `weightBoys/Girls` kg, `lengthBoys/Girls` cm, `headBoys/Girls` cm; index = month 0…60).
- Metric toggle Weight/Height/Head; **+** logs a new GROWTH entry; switch Chart ↔ List.
- Age for points uses `adjusted_birth_date` if set, else `birth_date`. `ageMonths = days / 30.4375`. LMS linearly interpolated between months.
- z = `ln(v/M)/S` if |L| < 1e-6 else `((v/M)^L − 1)/(L·S)`; percentile = Φ(z)×100 (Abramowitz–Stegun erf). Curves at percentiles 2, 5, 10, 25, 50, 75, 90, 95, 98 via inverse normal (Acklam) → value = `M·(1+L·S·z)^(1/L)` (or `M·e^(S·z)` when L≈0).
- Chart X max = `min(60, max(6, ceil(maxAge + 1)))` months. Tap point → popover with value, percentile, age, **Edit**, "Source: WHO".
- List rows: date, value (display units), "Boys Percentile N%"/"Girls Percentile N%", "Age {ageLabel}" (e.g. "5m 2w 2d", "1y 3m"; "Not born yet" if before birth).
- No curves/percentiles when sex is unknown/OTHER.
- Empty: "Add {name}'s birth date to see the growth chart." / "No {metric} measurements yet."

### 16.2 Milestones
- Groups from `data/milestones.json`, collapsible, each with "done/total".
- Default expanded group = last group with `ageMonths ≤ max(child age in months, 2)`.
- Item is done if a MILESTONE activity matches by `milestone_key`, or by title (`findByTitle`: lowercase, alphanumerics only). Done → check + date; tap edits that entry. Not done → tap opens new MILESTONE entry prefilled with title + key.

### 16.3 Vaccinations
Port `reference/VaccineSchedule.kt` + `VaccineScheduleTest`; data from `data/vaccine_schedule.json`.
- **Add** button → new VACCINE entry.
- No birth date → note asking to add one (doses show UPCOMING).
- No vaccine entries → "No vaccines logged yet".
- Dose matching: canonicalize every logged vaccine name (fuzzy: hepatitisb/hepb, rotavirus/rv, diphtheria/dtap, haemophilus/hemophilus/hib, pneumococcal/pcv*, polio/ipv, measles/mmr, varicella/chickenpox/var, hepatitisa/hepa). The n-th chronological entry containing a vaccine = dose n. A vaccine listed twice in one entry counts once.
- Dose status: due date = birth + start months; overdue date = birth + end months + 1 month. GIVEN if matched; else UPCOMING if no birth date; else OVERDUE if today ≥ overdue date and not brand-dependent; else DUE if today ≥ due date; else UPCOMING. Uses actual birth date.
- Sections:
  - "Up next for {name}" — `recommendations`: exclude given & brand-dependent; order overdue (by overdue date), due, upcoming (by due date); top 5. Empty → "All scheduled doses are up to date. Nice work!"
  - "Vaccination chart" — per group with "given/total" (brand-dependent not-given doses don't count toward totals).
  - "Also recommended" — 4 info items.
  - "History" — vaccine entries newest first.
  - CDC disclaimer text (informational, "check with your pediatrician").
- Dose subtitles: "Given {date}", "Was due {date}", "Due now · recommended at {group label}", "Due {date} · {group label}"; plus note text when present.
- Tap given dose → edit that entry; other dose → new VACCINE entry with that vaccine preselected.

### 16.4 Reminders
- Intro: "Get an alert after a set time since the last activity of each type."
- Rows Feed, Pump, Diaper, Sleep: toggle + interval editor (hours/minutes). Subtitle "Every {duration} after last {kind}".
- On load: `getOrCreate(familyId, profileId, kind)` for each kind (scope: PUMP → `profile_id null`; others → selected child). Caregiver = mine (by user_id) → current → first. New rows: default interval (FEED 180, PUMP 180, DIAPER 120, SLEEP 120 min), `enabled = false`.
- Enabling requests notification permission (`UNUserNotificationCenter.requestAuthorization`). If denied, show a hint to open Settings and keep the toggle off.
- `setEnabled` / `setInterval(min 1)` are version-checked updates, followed by reschedule.

---

## 17. Appointments & Notes

### 17.1 Appointments list
- Upcoming (`starts_at ≥ now`, ascending) — first one badged "Next appointment". Past (most recent first).
- Row: title; "doctor · location" (omit blanks); checklist progress from notes: "x/y questions asked" if any checked, else "N questions to ask"; "Reminder: {lead label}" if lead set; date tile (month/day); countdown (`Format.countdown`).
- Empty state + **Add appointment**.

### 17.2 Appointment detail (new/edit)
- **Title** with suggestions = distinct past titles + hints (catalogs.json).
- **Doctor**, **Location** — each with suggestions from past values.
- **Date & Time** — default tomorrow 09:00.
- **Reminder** — lead options (§5); default "1 day before"; choosing a non-NONE lead requests notification permission.
- **Notes & questions** — formatted editor (§17.3).
- Save validation: "Give the appointment a title — pick a hint or type your own."
- Save = insert or version-checked update; then schedule/cancel its notification.
- Delete confirm: "This removes the appointment, its notes and its reminder." → soft delete + cancel notification.

### 17.3 Formatted notes editor (`reference/AppointmentNotesFormat.kt` + its 16 tests)
Plain-text with line prefixes: "• " bullet, "☐ " unchecked, "☑ " checked, "N. " numbered.
- Toolbar: **• Bullet**, **1. Numbered**, **☐ Checkbox**, **Done**. `formatCurrentLine` replaces the current line's prefix; numbered continues from an immediately preceding numbered line.
- Enter continues the list: checkbox → new "☐ " (always unchecked); numbered → next number and renumber following numbered lines; Enter on an empty item removes the prefix.
- **Preview** mode: checkbox lines are tappable (toggle ☐/☑ and save), "x of y done" count, **Edit** to return to editing.
- iOS implementation: `TextEditor` bound to `String` with a custom `onChange` diff to detect inserted newlines, or a `UITextView` wrapper (preferred for cursor position control). Port the pure functions first.

### 17.4 Notes
- List (per selected child, `updated_at` desc): title ("Untitled" if blank), first non-blank body line, "Edited {relativeDay} · {x of y done}" (progress only if checkboxes). Empty-state text explaining notes are shared with the family + **New note**.
- Detail: Header field (placeholder "e.g. Bedtime routine") + the same formatted editor/preview.
- Validation: "Add a header or some text."
- Conflict → load latest + show message.
- Delete confirm: "This removes the note for everyone in your family."

---

## 18. Account

Rows: **Family**, **Settings**, **Subscription**, **Help**. Section "Data": **Import / Export CSV**. Section "Share & Social": "Share Nestly With Friends", "Rate Nestly" — **stubs (no-op)** for parity.

### 18.1 Family
- **Children**: each row name + age + "Tap to edit" → Edit Child dialog (Name, Boy/Girl, Birthdate). Save → version-checked update **and selects that child**. **Add child** (asks "Your name" only if the family has no caregivers).
- **Caregivers**: each row name + "Your Profile" (if current) or "Tap if this is you" (tap → set current caregiver). **Add caregiver** → name-only.
- **Invite**: **Create invite code** → "Code: {CODE} — share it with another caregiver" (add a Copy/Share action).

### 18.2 Settings
- **Log Out** (sign out, unsubscribe realtime, cancel pending notifications, end Live Activities, clear selection prefs).
- **Email & password** → Email screen (read-only email + "Your account is used to share this family's data with other caregivers through Supabase. Data is stored online only; there is no local copy on this device.").
- **Units** → four segmented choices (Volume mL/oz, Weight kg/lb, Length cm/in, Temperature °C/°F) + note "Storage stays metric. These settings only change what you see and enter."
- **Communication preferences** → toggles Reminders, Product updates (local, **not persisted** — parity stub).
- **Nightstand Mode** → opens the in-app nightstand (§21.6). (Android deep-linked to system screensaver settings.)
- **Default bottle amount** — numeric field in display volume units; empty = off. Helper: "Tap to change it. Leave the amount empty and tap OK to turn the default off."
- **Clear all data** — `#if DEBUG` only; confirm, then clear family photos + `clearCurrentFamilyData`.

### 18.3 Subscription / Help
- Subscription: "Free" plan label + stub.
- Help: Contact `help@nestly.app` (mailto), FAQs (stub), Version (`CFBundleShortVersionString (CFBundleVersion)`), Legal (stub), Advanced Settings (stub).

---

## 19. Import / Export

Screen rows: **Import from Nara**, **Export Nestly CSV**, **Import Nestly CSV**, a result/status message, and "Activities in Nestly" with per-type counts (`fetchCountsByType`). Use `fileImporter` (types: csv, tsv, plain text, xlsx, xml, html) and `fileExporter`/ShareLink for export.

### 19.1 Nestly CSV (port `reference/NestlyCsv.kt` + `NestlyCsvRoundTripTest`)
- UTF-8 **with BOM**, RFC 4180 quoting, header columns exactly as in the reference (record, id, familyId, profileId, name, birthDate, sex, profileType, type, startTime, endTime, timeZone, note, photoUri, comboGroupId, createdById, updatedById, createdAt, updatedAt, bottle_*, pump_*, breast_*, diaper_*, growth_*, milestone_title, milestone_milestoneKey, solids_mealType, solids_foods, routine_name, babyFirst_title, medical_*, vaccine_vaccines).
- `record` ∈ FAMILY, CAREGIVER, PROFILE, ACTIVITY. Times = epoch ms. Lists joined with `|`.
- Export: all my families, their caregivers, profiles, active activities sorted by start time. Filename `nestly_export_{yyyy-MM-dd}.csv`.
- Import: upsert families, caregivers (**forced name-only**: `user_id = null`), profiles, activities (chunks of 200). Bump all ticks after.
- Files must be interchangeable with Android exports.

### 19.2 Nara import (port `reference/SpreadsheetReader.kt`, `CsvParser.kt`, `NaraRowMapper.kt`, `NaraImportMapping.kt`, `NaraCsvImporter.kt` + tests)
- **Format sniffing**: ZIP header → XLSX (parse `xl/sharedStrings.xml` + first sheet; use a small zip reader such as ZIPFoundation); OLE header → error asking the user to re-export as CSV/XLSX; `<?xml` SpreadsheetML; HTML `<table>`; otherwise CSV/TSV (tab if more tabs than commas in the first line). Handle UTF-8/UTF-16 BOMs.
- First row = header; values trimmed; blank values dropped.
- Row mapping by `Type` column (Profile, Bottle Feed, Pump, Breastfeed, Diaper, Growth, Milestone); see reference for every column name (e.g. `[Bottle Feed] Volume`, `[Pump] End Date/time (Epoch)`, `[Breastfeed] Begin Side` with `.nonTimer` suffix = manual entry, `[Diaper] Type` contains "Wet"/"Dirty", `[Profile] Birth Date`, `Birth Date (Adjusted)`).
- Shared columns: `_familyKey`, `_profileKey`, `_activityKey`, `Start Date/time (Epoch)` (flexible parse), `Time Zone`, `Note`, `Created By Caregiver`, `Last Updated By Caregiver`.
- Unit conversions: volume FLOZ/OZ ×29.5735295625, L ×1000; weight LB ×0.45359237, OZ ×0.45359237/16, G ÷1000; length IN ×2.54, MM ÷10, M ×100.
- **Deterministic IDs — must match Android exactly** so re-importing on either platform upserts instead of duplicating: Java `UUID.nameUUIDFromBytes` = MD5 of the UTF-8 bytes, then set version 3 (`b[6] = b[6] & 0x0f | 0x30`) and IETF variant (`b[8] = b[8] & 0x3f | 0x80`), lowercase string. Names: `nara:profile:{key}`, `nara:activity:{key}`, `nara:caregiver:{familyId}:{normalizedName}`. (Use `CryptoKit.Insecure.MD5`.) Add a unit test with a fixed vector computed from the Android implementation.
- Profile matching against existing profiles: normalized name; prefer same birth date; otherwise only if exactly one same-named profile.
- Everything imports into `currentFamilyId`; none → "Create or join a family before importing from Nara."
- Nothing recognized → "No recognizable Nara rows found in this file … (columns: …) …" (see reference for exact text).
- Result message: counts per activity type, profiles, caregivers, skipped rows.
- Android has a real sample export in `app/src/androidTest/assets/nara_export.csv` (personal data — not copied here). Ask the project owner for it to run `NaraSampleImportTest` (expects 1 profile; 1125 bottle, 1107 pump, 65 breastfeed, …).

---

## 20. Notifications (reminders + appointments)

Port `reference/ReminderLogic.kt`, `AppointmentReminderLogic.kt`, `DailyDose.kt` + tests.

### 20.1 Interval reminders
- Kind → activity types: FEED = BOTTLE_FEED, BREASTFEED, SOLIDS; PUMP = PUMP; DIAPER = DIAPER; SLEEP = SLEEP.
- `nextFireMs = lastStart + interval`; if already past → `now + 1 min`.
- If nothing logged of that kind → no notification.
- Notification: title "{Kind} reminder" (Feed/Pump/Diaper/Sleep), body "Time to log the next {kind}." (lowercase kind). Identifier `reminder-{reminderId}` (replace on reschedule). Fires once; next schedule happens on the next reschedule.
- `nextFeedState`: NoFeed / Upcoming / DueNow (within 60 s after due) / Overdue — used by dashboard, nightstand and widget.

### 20.2 Appointment reminders
- `fireAt`: nil if no lead or appointment in the past; else `start − lead`; if that's past → `min(now + 1 min, start)`.
- Title = appointment title; body = "EEE, MMM d 'at' h:mma" (am/pm lowercased) + " · doctor" + " · location" (omit blanks). Identifier `appointment-{id}`; `userInfo["appointment_id"]` → deep link on tap.
- Don't schedule if the appointment started > 5 min ago.

### 20.3 `rescheduleAll()`
Waits up to 30 s for an authenticated session, then: remove all pending `reminder-*`/`appointment-*` requests; for each **enabled** reminder owned by me (all my profiles): compute fire time from the latest matching activity; for each upcoming appointment with a lead (all families): schedule. Runs:
- after every activity/reminder/appointment save or delete;
- on app launch and foreground;
- on realtime activity/reminder/appointment events while the app is running (debounced ~2 s);
- in a `BGAppRefreshTask` (identifier `<bundle>.reschedule`, best-effort, request every ~30 min).

iOS limitation (document in code): Android re-checked the reminder's `enabled` flag at fire time. iOS local notifications can't run code at fire time, so a feed logged by **another caregiver while this app is suspended** won't push back this device's reminder until the next reschedule (background refresh / next open). Acceptable for v1; a future server-side push could fix it.

Respect the 64 pending-notification limit (well under it: ≤ 4 reminders per child + appointments; schedule only the nearest 50 appointments).

---

## 21. Widgets, Siri, StandBy, Live Activities, Nightstand

All extension code uses `NestlyCore`, the shared keychain session, and App Group preferences.

### 21.1 Quick bottle log (shared action — port `reference/QuickBottleLog.kt` + `QuickBottleLogTest`)
`QuickBottleLog.run(at: Date) -> Result`:
1. Wait up to 30 s for a definitive auth status (restore session from shared keychain; refresh if needed).
2. Not signed in → `.notSignedIn`. Session still restoring → `.sessionNotReady`.
3. Selected (or first) profile; none → `.noChild`.
4. Amount = `default_bottle_ml` if > 0, else last bottle's `bottle_total_ml`; none → `.noAmount`.
5. Insert BOTTLE_FEED at tap time (`bottle_total_ml = amount`, no milk type, current caregiver, device time zone).
6. Reschedule reminders, reload widget timelines.
- **Never auto-retry** (avoid duplicates). De-duplicate concurrent invocations (in-process lock; ignore a second tap while one is in flight).

Result messages — widget / Siri / home-screen quick action:
| Result | Message |
|---|---|
| saved | "Bottle feed saved: {amount in display units} at {time}" |
| notSignedIn | "Couldn't save bottle feed. Open Nestly and sign in first." |
| sessionNotReady | "Couldn't save bottle feed yet — still restoring your sign-in. Check your connection and try again." |
| noChild | "Couldn't save bottle feed. Open Nestly and select a child first." |
| noAmount | "No default bottle amount set. Open Nestly to set one first." |
| failed | "Couldn't save bottle feed. Check your connection and try again." |

Nightstand uses its own wording: "Feed added successfully: {amount} at {time}", "Couldn't add feed. Open Nestly and sign in first.", "Couldn't add feed yet — sign-in is still loading. Check your connection and tap again.", "Couldn't add feed. Open Nestly and select a child first.", the same noAmount text, "Couldn't add feed. Check your connection and try again."

`QuickVitaminDLog.run()` (port reference): if `DailyDose.givenAt(today)` exists → `.alreadyGiven`; else insert VITAMIN_D with last dose/unit or 400 IU. Messages: "Vitamin D added at {time}", "Vitamin D was already given today at {time}", "Couldn't add Vitamin D. Open Nestly and sign in first.", "Couldn't add Vitamin D yet — sign-in is still loading. Check your connection and tap again.", "Couldn't add Vitamin D. Open Nestly and select a child first.", "Couldn't add Vitamin D. Check your connection and try again."

### 21.2 Home-screen widget "Nestly Quick Log" (WidgetKit, iOS 17 interactive)
- Sizes: small + medium.
- Buttons: **Bottle** → `Button(intent: LogBottleIntent())` (one-tap background save, shows result via timeline reload: "Saved 4 oz at 6:14pm" / error text). **Diaper**, **Sleep**, **Pump** → `Link` to `nestly://entry/DIAPER|SLEEP|PUMP`.
- Show child name and "Last feed {ago}" when available.

### 21.3 StandBy / "Next feed" widget
- Small widget (works in StandBy and Lock Screen accessory rectangular): child name, **NEXT FEED** time, countdown (`Text(dueDate, style: .relative)` or `.timer`), state (in X / NOW / OVERDUE BY X), last feed time + detail, Vitamin D status ("Vitamin D given at {time}" / "Vitamin D due").
- Interactive buttons (where size allows): **Log feed** (`LogBottleIntent`), **Vitamin D given** (`LogVitaminDIntent`, only when due).
- Timeline entries: now, at due time (switch to NOW), +60 s (OVERDUE), and every 15 min; policy `.after(next)`. Reload after any save from app/intents.

### 21.4 Siri & App Shortcuts (App Intents)
- `LogBottleIntent` (runs in background, `openAppWhenRun = false`), returns dialog with the result message.
- `LogVitaminDIntent`.
- `OpenEntryIntent(kind: EntryKindAppEnum)` → opens app to entry sheet (`openAppWhenRun = true`).
- `OpenNightstandIntent`.
- `AppShortcutsProvider` phrases (must include app name): "Log a bottle in \(.applicationName)", "Add feed in \(.applicationName)", "Add a feed now in \(.applicationName)", "Log feed with \(.applicationName)", "Log Vitamin D in \(.applicationName)", "Log a diaper in \(.applicationName)", "Start sleep in \(.applicationName)". Shortcut tile title "Add feed".
- Home-screen quick action (`UIApplicationShortcutItem`): "Add feed" → quick bottle log with a toast/banner result.

### 21.5 Live Activities (new on iOS)
- `TimerActivityAttributes` (child name, timer kind) with `ContentState { side/kind, accumulatedSeconds, runningSince: Date?, isPaused }`.
- Start when a BREAST_LEFT/BREAST_RIGHT, PUMP or SLEEP timer starts from a new entry; update on pause/resume/side switch; end on save/discard/reset (dismissal `.immediate`).
- Lock Screen + Dynamic Island: kind ("Breastfeeding · Left", "Pumping", "Sleeping"), elapsed via `Text(timerInterval:countsDown:false)` when running or static when paused, buttons **Pause/Resume** (and **Switch side** for breastfeed) via `LiveActivityIntent`s that mutate the shared `ActiveTimerStore` and update the activity. Tapping opens the entry sheet for that kind.
- Requires `NSSupportsLiveActivities = YES`. If the user disabled Live Activities, timers still work in-app.

### 21.6 In-app Nightstand mode (`nightstand` route, full-screen)
Port Android `dream/` behavior:
- `UIApplication.shared.isIdleTimerDisabled = true` while shown; dark, minimal.
- Child name + date; **NEXT FEED** time; countdown "IN {dur}" (amber) / "NOW" / "OVERDUE BY {dur}" (red); "Last feed {time} · {detail}"; "Today: {N} feeds · {volume} · every ~{avg interval}".
- Vitamin D: "VITAMIN D DUE / tap when given" (pulsing red, tap → `QuickVitaminDLog`) or "VITAMIN D GIVEN at {time}".
- Large **LOG FEED** (quick bottle) and **CLOSE** buttons; result shown inline briefly.
- Burn-in protection: offset whole layout by a random ±4 pt each minute.
- Refresh data every 60 s and on auth arrival; clock ticks every 30 s.
- Empty texts: "Open Nestly to set up your family", "No feeds logged yet — tap LOG FEED".
- Optional: when the device is charging and in landscape on the Activity tab, show a small "Nightstand" suggestion (not required).

---

## 22. Error handling summary
- All network reads: via refetch streams + global banner (§4).
- Writes surface inline errors in the relevant sheet/screen (copy in each section). Never silently drop a failed write. Never auto-retry inserts.
- Conflicts: reload + "This entry was changed by someone else. Showing the latest version."
- Map Supabase/auth errors to the friendly copy in §10.1.

---

## 23. Test checklist (acceptance)

Port each Android test file in `reference/tests/` to Swift (same cases, same expected values):
`VaccineScheduleTest`, `GrowthPercentilesTest`, `CsvParserTest`, `NaraImportMappingTest`, `NaraRowMapperTest`, `NaraSampleImportTest` (skips if sample missing), `NestlyCsvRoundTripTest`, `SpreadsheetReaderTest`, `AppointmentReminderLogicTest`, `DailyDoseTest`, `ReminderLogicTest`, `DtoMappingTest`, `RefetchFlowTest`, `UnitsTest`, `ActivityFiltersTest`, `SummaryTest`, `AppointmentNotesFormatTest` (16 cases), `FormatTest`, `DefaultBottleAmountTest`, `EntryBuilderTest`, `TrendsAggregatorTest`, `QuickBottleLogTest`.

Plus iOS-specific:
- Deterministic UUID v3 matches Java `nameUUIDFromBytes`: `nara:profile:c-1` → `6b12227c-4764-3461-b740-9cdd5ecc7db9`, `nara:activity:t-1` → `2b7a2906-111a-3bda-bcfa-09a79e7bd4a3`.
- Nestly CSV exported on iOS imports on Android and vice-versa (byte-level header match, BOM present).
- Manual QA: two devices (one Android, one iOS) in the same family — log on one, appears on the other within seconds; edit the same entry concurrently → conflict message on the loser.

---

## 24. Build plan (suggested order for Cursor)

1. **Project setup** — Xcode project, targets (app, widget extension), App Group, shared keychain group, `NestlyCore` package, supabase-swift, resources from `data/`.
2. **Logic layer + tests** — Units, Format, catalogs/JSON loaders, MilestoneCatalog, VaccineSchedule, GrowthPercentiles, ReminderLogic, AppointmentReminderLogic, DailyDose, ActivityFilters, Summary, AppointmentNotesFormat, EntryModel/EntryBuilder, TrendsAggregator, CSV/Spreadsheet/Nara/NestlyCsv. All tests green before UI.
3. **Backend** — DTOs, Supabase client, RefreshBus, refetch streams, DataErrors, version-checked update helper, PhotoStore, RealtimeSync.
4. **Repositories** — Auth, Family, Activity, Reminder, Appointment, Note.
5. **Root gate, Auth, Onboarding**.
6. **Activity tab + Entry sheet** (all 14 kinds, timers, photos, default amount prompt).
7. **History tab**, **Trends tab + detail**.
8. **Growth, Milestones, Vaccinations**.
9. **Reminders + notification scheduling + BG refresh**.
10. **Appointments + Notes** (formatted editor).
11. **Account** screens (Family, Settings, Units, Email, Communication, Subscription, Help, Import/Export).
12. **QuickBottleLog / QuickVitaminDLog**, App Intents + Siri phrases + home-screen quick action.
13. **Widgets** (Quick Log, Next feed/StandBy), **Live Activities**.
14. **Nightstand mode**.
15. Two-device QA against Android.

## 25. Out of scope / known parity notes
- Visual design.
- `appointment_question` and `user_settings` tables (unused).
- Communication preferences don't persist; Share/Rate/FAQs/Legal/Advanced/Subscription are stubs (parity).
- Legacy binary `.xls` (OLE) import unsupported — show the re-export message.
- No dedicated child switcher (parity: switch by editing/saving a child in Family).
