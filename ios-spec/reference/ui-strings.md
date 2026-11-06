# User-facing strings in the Android app, by file:line (Kotlin string templates like ${x} are placeholders).
# Adjacent lines joined with + in the source form one sentence.

## data/importer/NaraCsvImporter.kt
42: No recognizable Nara rows found in this file
43:  (columns: $it)
44: . Make sure it's a Baby Nara export (.csv, .xls or .xlsx), not a different app's file.
50: Create or join a family before importing from Nara.
89: Baby

## data/reminder/AppointmentReminderLogic.kt
21: appointment:

## data/reminder/ReminderLogic.kt
46: Feed
47: Pump
48: Diaper
49: Sleep

## data/reminder/ReminderNotifications.kt
17: Reminders
19: Appointments
25: Alerts after the interval since the last activity
30: Reminders for upcoming doctor appointments
47: EEE, MMM d 'at' h:mma
79: ${ReminderLogic.label(kind)} reminder
80: Time to log the next ${ReminderLogic.label(kind).lowercase()}.

## data/reminder/ReminderScheduler.kt
121: com.lifestyle.nestly.REMINDER_FIRE
122: com.lifestyle.nestly.APPOINTMENT_FIRE

## dream/NightstandScreen.kt
104: Feed added successfully: ${Format.volume(result.ml, state?.units ?: com.lifestyle.nestly.data.units.UnitPrefs.DEFAULT)} at ${Format.time(result.atMs)}
106: Couldn't add feed. Open Nestly and sign in first.
108: Couldn't add feed yet — sign-in is still loading. Check your connection and tap again.
110: Couldn't add feed. Open Nestly and select a child first.
112: No default bottle amount set. Open Nestly to set one first.
114: Couldn't add feed. Check your connection and try again.
120: Couldn't add feed. Check your connection and try again.
132: Vitamin D added at ${Format.time(result.atMs)}
133: Vitamin D was already given today at ${Format.time(result.atMs)}
134: Couldn't add Vitamin D. Open Nestly and sign in first.
136: Couldn't add Vitamin D yet — sign-in is still loading. Check your connection and tap again.
137: Couldn't add Vitamin D. Open Nestly and select a child first.
138: Couldn't add Vitamin D. Check your connection and try again.
144: Couldn't add Vitamin D. Check your connection and try again.
324: Nestly
332:   ·  ${Format.headerDate(now)}
357: VITAMIN D GIVEN
357: VITAMIN D DUE
359: at ${Format.time(givenAt)}
360: saving…
361: tap when given
435: NEXT FEED
436: NEXT FEED
437: NEXT FEED
438: NEXT FEED
439: NEXT FEED
455: Open Nestly to set up your family
464: No feeds logged yet — tap LOG FEED
487: OVERDUE BY
512: Last feed ${Format.time(lastFeed.startTime)}
524: No feeds yet today
525: Today: ${state.todayFeedCount} ${if (state.todayFeedCount == 1) 
525:  else 
525: }  ·  ${Format.volume(state.todayBottleMl, state.units)}
526: Today: ${state.todayFeedCount} ${if (state.todayFeedCount == 1) 
526:  else 
529: $todayText  ·  every ~${minutesText(state.intervalMinutes * 60_000L, roundUp = false)}
596: LOGGING…
596: LOG FEED
628: 11m
628: 1h 23m
632:  0m

## ui/NestlyApp.kt
78: growth/${metric.name}
79: editActivities
86: appointments/$id
90: notes/$id
100: trends/${metric.name}/${window.name}
104: Activity
105: History
106: Trends
107: Account
145: Loading your family…
155: Loading your family…
247: Import / Export

## ui/account/AccountScreens.kt
66: Account
68: Family
69: Settings
70: Subscription
71: Help
72: Data
73: Import / Export CSV
74: Share & Social
75: Share Nestly With Friends
76: Rate Nestly on the Play Store
90: Family
92: Children
98: Tap to edit
103: Add child
104: Caregivers
108: Your Profile
108: Tap if this is you
112: Add caregiver
113: Invite to this family
116: Entries you log are recorded as added by your profile. Tap a child to edit their details.
146: Add caregiver
166: Create invite code
167: Code: $it — share it with another caregiver
167: They enter it when joining
205: Edit child
211: First Name
217: Boy
217: Girl
226: Birthdate
228: Add
235: Save
238: Cancel
266: Settings
266: Log Out
272: Email & password
273: Units
274: Communication preferences
276: Nightstand
278: Nightstand Mode
279: Show the clock and next feed while this device is charging
291: Select Nestly Nightstand as your screen saver, then set it to start while charging. 
292: From it you can log a feed with your default bottle amount in one tap, without unlocking.
298: Feeding
300: Default bottle amount
301: Pre-fills new bottle & combo feeds
301: Not set — new bottle feeds start empty
307: Tap to change it. Leave the amount empty and tap OK to turn the default off.
316: Testing
318: Clear all data
319: Deletes this family's children, activities, reminders and photos from Supabase
333: Default bottle amount
349: Clear all data?
352: This permanently deletes this family's children, activities, reminders, invites and photos 
353: from Supabase for every caregiver. This cannot be undone. You'll return to setup and can re-import from Nara.
374: Couldn't clear data: ${it.message ?: 
381: Clearing…
381: Clear everything
386: Cancel
397: Email & password
398: Email
398: Signed in
400: Your account is used to share this family's data with other caregivers through Supabase. 
401: Data is stored online only; there is no local copy on this device.
413: Communication preferences
414: Reminders
414: Get alerts for timers you set.
415: Product updates
415: Stay up to date on new features and more.
439: Subscription
440: Status
440: Free
441: Manage
442: Subscribe
444: Nestly is free while in development.
457: v${info.versionName} (${info.longVersionCode})
459: Help
460: Contact Us
460: help@nestly.app
461: Baby tracker FAQs
462: Version
463: Legal
465: Advanced Settings

## ui/account/UnitsScreen.kt
39: Units
42: Storage stays metric. These settings only change what you see and enter.
48: Volume
54: Weight
60: Length
66: Temperature

## ui/activity/ActivityDisplay.kt
29: Feed
30: Pump
31: Diaper
32: Sleep
33: Routine
34: Baby Firsts
35: Growth
36: Health
56: Breast Milk
60: Breast Milk
61: Formula
62: Mixed
63: Bottle
65: Breastfeed
66: Solids
68: Diaper
69: Sleep
70: Routine
71: Baby First
72: Growth
73: Milestone
74: Medical
75: Vaccine
76: Vitamin D
80: Wet
81: Dirty
82: Wet + Dirty
83: Dry
86: 150 mL
86: L 10m  R 5m
92: L ${Format.duration(it)}
93: R ${Format.duration(it)}

## ui/activity/ActivityScreen.kt
106: Summary
108: More
115: Set Reminders
123: Doctor Appointments
131: Notes
139: Edit Activities
176: Edit Activities
214: Welcome to Nestly
217: Track feeds, pumping, diapers, sleep and more. Add your child to get started, or bring your history over from Nara Baby.
223: Add Child
225: Import from Nara
261: Add child
267: First Name
273: Boy
273: Girl
282: Birthdate
284: Add
291: Your Name
301: Save
304: Cancel

## ui/activity/CardParts.kt
92: Add ${kind.title}
98: Last feeding / 1h 53m ago
133: Track a sleep session
150: Next feeding in 1h 25m at 7:18pm
187: Show Less
187: Show More
284: Vitamin D / Given today at 8:12am
297: Vitamin D
299: Given today at ${Format.time(givenAt)}
299: Not given today

## ui/activity/Cards.kt
70: Track a routine or create your own
71: Track memorable moments
83: Entries before 12:00am
102: Track a feeding
117: Last feeding
126: Breastfeeding
143: Track a pumping session
149: Last session
159: Pumping
171: Track a diaper change
175: Last change
181: View History
194: Sleeping
195: since ${Format.time(it)}
199: Track a sleep session
202: Last sleep
247: Weight
250: Height
253: Head Size
260: Milestones
262: $logged of ${MilestoneCatalog.groups.sumOf { it.items.size }}
283: Medical
290: Vaccine
292: 1 vaccine
292: $it vaccines

## ui/activity/EditActivitiesScreen.kt
53: Breastfeeding
54: Bottle Feeding
55: Breast Milk
56: Formula
57: Solid Feeding
58: Combo Feeding
60: Pumping
61: Diaper Changes
62: Sleep
63: Routines
64: Baby Firsts
65: Growth
66: Health
86: Edit Activities
88: Save
119: Reorder

## ui/activity/Sheets.kt
93: Summary
96: Today
96: Last 24 Hours
101: Nothing logged yet.
143: Notes
144: Photos
145: Feed
146: Pump
147: Diaper
148: Sleep
149: Routine
150: Health
157: Filters
161: Apply

## ui/activity/Summary.kt
32: ${Format.volume(total, prefs)} total
33: ${Format.volume(it, prefs)} breast milk
34: ${Format.volume(it, prefs)} formula
37: ${Format.volume(items.sumOf { it.pump?.totalMl ?: 0.0 }, prefs)} total
41: ${Format.duration(left + right)} total
41: L ${Format.duration(left)}  R ${Format.duration(right)}
46: $wet wet, $dirty dirty
48: ${Format.duration(items.sumOf { it.durationSec ?: 0 })} total
71: Bottle Feed
72: Breastfeed
73: Pump
74: Diaper
75: Growth
76: Milestone
77: Sleep
78: Solids
79: Routine
80: Baby First
81: Medical
82: Vaccine
83: Vitamin D

## ui/appointments/AppointmentNotesFormat.kt
16: ^(\d+)\.\s+
17: ^(\d+)\.(?:\s+|$)
18: ^(•\s+|☐\s+|☑\s+|\d+\.\s+)
50: \n
68: ${nextNumber(text.substring(0, lineStart))}. 
94: \n
143: $nextNumber. 
165: \n
170: \n
175: $expected. 
177: \n

## ui/appointments/AppointmentsScreen.kt
72: Well-child checkup
73: Vaccination visit
74: Sick visit
75: Follow-up visit
76: Developmental check
77: Weight check
93: Appointments
93: Add
104: No appointments yet
110: Add a doctor appointment to keep its date, your questions and notes in one place.
116: Add appointment
122: Upcoming
133: Past
165: Next appointment
188: ${checkboxItems.count { it.checked }}/${checkboxItems.size} questions asked
190: 1 question to ask
190: ${checkboxItems.size} questions to ask
191: ${checkboxItems.count { it.checked }}/${checkboxItems.size} questions asked
195: Reminder: ${it.label.lowercase()}
219: MMM ''yy
390: Give the appointment a title — pick a hint or type your own.
408: New Appointment
408: Appointment
410: Save
429: Title
433: e.g. 4-month checkup
436: Doctor
440: e.g. Dr. Patel
443: Location
447: e.g. Sunny Pediatrics
450: Date & Time
455: Reminder
461: Notes & questions
465: Write freely — questions to ask, what the doctor said, follow-ups. 
466: Use the buttons below to start a bullet, numbered or checkbox line; 
467: pressing Enter continues it onto the next line.
468: ☐ Ask about feeding\n• Bring vaccine record\n1. First question
478: Delete appointment
498: Reminder
516: Delete appointment?
519: This removes the appointment, its notes and its reminder.
531: Delete
536: Cancel

## ui/appointments/AppointmentsViewModel.kt
60: Add a child first
82: Couldn't save the appointment.
93: Couldn't delete the appointment.

## ui/auth/AuthScreens.kt
41: Loading…
65: Couldn't reach Nestly
70: Retry
87: Retry
119: Nestly
121: Create your account to share tracking with your family.
122: Sign in to see your family's tracking.
128: Email
136: Password
146: Your name (as caregiver)
164: Please wait…
164: Create account
164: Sign in
168: Already have an account? Sign in
168: New to Nestly? Create an account
177: text/comma-separated-values
180: text/tab-separated-values
181: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
182: application/vnd.ms-excel
184: application/octet-stream
210: Welcome to Nestly
215: Start a new family, or join one with an invite code from another caregiver.
221: Your name (as caregiver)
232: Create my family
236: Invite code
246: Join with invite code
250: Add your first child to start tracking, or do a one-time import of your Nara Baby history.
259: Add child
264: Importing…
264: Import from Nara instead
270: Back
276: Sign out

## ui/auth/AuthViewModel.kt
109: Importing your Nara history…
114: Could not open the selected file
117: Imported ${result.totalActivities} activities for ${result.profiles} child profile(s) 
118: and ${result.caregivers} caregiver(s). Skipped ${result.skippedRows} unsupported row(s).
121: Import failed. Check your connection and try again.
139: Check your email to confirm your account, then sign in.
158: Couldn't save. Check your connection and try again.
182: rate limit
183: Supabase's built-in email limit was hit, so no confirmation email was sent and the account wasn't created. 
184: For testing, turn off \"Confirm email\" in Supabase Dashboard → Authentication → Providers → Email, then try again.
185: Invalid login
185: Wrong email or password.
186: already registered
186: That email already has an account. Sign in instead.
187: That invite code is invalid or expired.
188: Something went wrong. Check your connection and try again.

## ui/components/AddPhotoButton.kt
37: Add Photo
62: Photo
71: Add Photo
76: Remove Photo
83: ${UUID.randomUUID()}.jpg

## ui/components/Controls.kt
180: Notes
237: Start Timer
237: Add Photo
237: Yes
260: 0H 0M
272: Edit time

## ui/components/Dialogs.kt
254: Cancel
311: Cancel
361: Cancel
374: Cancel
401: Done
432: + Add your own
440: Add

## ui/components/DoseStatusDot.kt
34: dosePulse
39: dosePulseProgress

## ui/components/EntrySheetScaffold.kt
47: Save
73: Delete
95: Save
105: Close

## ui/components/Format.kt
16: h:mma
17: MMM d
18: MMM d, yyyy
19: EEE, MMM d
20: MMM d yyyy
22: 6:14pm
26: Today
26: Yesterday
26: Sep 30
31: Today
32: Yesterday
33: Tomorrow
38: Today  8:07pm
40: ${relativeDay(epochMs, now, zone)}  ${time(epochMs, zone)}
53: $value $name${if (value == 1L) 
53:  else 
55: Today
56: Tomorrow
56: Yesterday
62: in $amount
62: $amount ago
65: Thu, Oct 1
69: May 12 2026 4:30am
71: ${longDateFormat.format(Instant.ofEpochMilli(epochMs).atZone(zone))} ${time(epochMs, zone)}
73: Oct 1, 2026
84: $value $name${if (value == 1) 
84:  else 
89:  old
93:  old
97:  old
98: ${unit(period.days, 
98: )} old
99: Born today
103: 1h 53m ago
103: 5m ago
103: Just now
103: 3d ago
107: Just now
108: ${minutes}m ago
109: ${minutes / 60}h ${minutes % 60}m ago
110: ${minutes / (60 * 24)}d ago
114: 1h 5m
114: 12m
114: 45s
114: 0s
120: ${h}h ${m}m
121: ${m}m ${s}s
121: ${m}m
122: ${s}s
133: Next feeding in ${durationShort(state.remainingMs, roundUp = true)} at ${time(state.dueMs)}
134: Next feeding due now
136: Next feeding overdue by ${durationShort(state.overdueMs, roundUp = false)} · due ${time(state.dueMs)}
140: 1m
140: 25m
140: 1h
140: 1h 25m
140: 1d 2h
147: ${it}d
148: ${it}h
149: ${it}m
162: ${number(value, 0)} mL
166: ${number(Units.mlToDisplay(ml, prefs.volume), decimals)} ${Units.volumeLabel(prefs.volume)}
170: ${number(Units.kgToDisplay(kg, prefs.weight), if (prefs.weight.name == 
170: ) 1 else 2)} ${Units.weightLabel(prefs.weight)}
173: ${number(Units.cmToDisplay(cm, prefs.length), if (prefs.length.name == 
173: ) 1 else 1)} ${Units.lengthLabel(prefs.length)}
176: ${number(Units.cToDisplay(celsius, prefs.temp), 1)} ${Units.tempLabel(prefs.temp)}

## ui/components/FormattedNotesEditor.kt
130: • Bullet
133: 1. Numbered
136: ☐ Checkbox
141: Done
262: ${checkboxItems.values.count { it.checked }} of ${checkboxItems.size} done
269: Edit

## ui/components/ScreenScaffold.kt
35: Save
35: Log Out
61: Back

## ui/entry/EntryBuilder.kt
147: handled above
209: Vitamin D

## ui/entry/EntryController.kt
173: No child selected. Check your connection and try again.
210: Couldn't save. Check your connection and tap Save to retry.
228: Couldn't delete. Check your connection and try again.
248: Couldn't load this entry. Check your connection.

## ui/entry/EntryModel.kt
14: Breastfeed
15: Bottle Feed
16: Solids
17: Combo Feed
18: Pump
19: Diaper
20: Sleep
21: Routine
22: Baby First
23: Growth
24: Milestone
25: Medical
26: Vaccine
27: Vitamin D
64: Add

## ui/entry/EntrySheetHost.kt
160: Today
161: Add
167: Today
168: Add
207: Baby First

## ui/entry/FeedForms.kt
66: 12M 5S
66: 1H 3M
77: Start Time
98: Left
98: Right
103: last side
110: Pause
121: $label Side
135: Total Time
156: Breast\nMilk
156: Formula
164: Start Time
169: Amount
171: Add
184: Use last amount: ${Format.volume(last, units)}?
189: Yes
196: Formula
198: Add
202: Formula
213: Amount
229: Set as default amount?
229: Update default amount?
236: Use ${Format.volume(pendingMl, units)} as your default bottle amount? 
237: It will pre-fill future bottle feeds. This feed will use ${Format.volume(pendingMl, units)} either way.
239: Your default bottle amount is ${Format.volume(currentDefault, units)}. 
240: Change it to ${Format.volume(pendingMl, units)} for future feeds? 
241: This feed will use ${Format.volume(pendingMl, units)} either way.
252: Yes, set default
252: Yes, update default
257: Not now
257: No, keep default
280: Start Time
284: Food
286: Add
292: Food
351: Breastfeed
351: Bottle Feed
358: Start Time
372: Left / Right
372: Total
380: Start Time
384: Total Time
386: Add
390: Total Time
397: Left Side Amount
398: Right Side Amount
400: Total
401: 0 ${Units.volumeLabel(currentUnitPrefs().volume)}
405: Total Amount
416: Add
428: 0H 0M
449: Pause Timer
450: Start Timer
451: Resume Timer
456: Reset
463: Duration

## ui/entry/OtherForms.kt
64: Time
66: Wet
67: Dirty
68: Dry
72: Color
82: Texture
92: Diaper Rash
99: Runny
100: Mushy
101: Mucousy
163: Total Time
164: Start Time
165: End Time
172: Time
174: Routine
176: Add
182: Routine
198: Date
199: Baby First
206: Date
208: Weight
213: Height
218: Head Size
229: ${Format.number(it)} $unit
230: Add
259: Date
269: Time
271: Temperature
273: Add
277: Medication
279: ${Format.number(it)} ${d.doseUnit.orEmpty()}
281: Add
287: Temperature
315: mL
322: Time
324: Dose
325: ${Format.number(it)} $unit
326: Add
341: Dose
368: Medication
374: Name
382: Dose
401: Cancel
410: Date
412: Vaccines
414: Add
420: Vaccines

## ui/growth/GrowthScreen.kt
127: Back
130: Growth
136: Log growth
141: Show list
141: Show chart
150: Loading…
174: No ${metric.label.lowercase()} measurements yet.
179: Log growth
217: Boys
218: Girls
221: $label Percentile ${percentile.roundToInt()}%
246: date-$date
266: ${metric.label} 
274: Age ${GrowthPercentiles.ageLabel(birth, point.date)}
310: Add ${profile.name}'s birth date to see the growth chart.
324: No measurements to chart yet.
449: ${percentile.toInt()}%
497: Edit
505: Dismiss
510: ${metric.label} 
516: Age ${GrowthPercentiles.ageLabel(birth, point.date)}
519: Source: WHO

## ui/history/HistoryTab.kt
101: Nestly
107: Filters
109: More
116: Set Reminders
222: Previous week
396: 1 entry
396: ${history.entries.size} entries
403: Nothing logged.
423: 12\nAM
424: 6\nAM
425: 12\nPM
426: 6\nPM

## ui/importer/ImportScreen.kt
33: text/comma-separated-values
36: text/tab-separated-values
37: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
38: application/vnd.ms-excel
40: application/octet-stream
71: Import a Nara Baby export, or back up Nestly to a CSV you can re-import later.
76: Import from Nara
85: Export Nestly CSV
87: nestly_export_${LocalDate.now()}.csv
90: Import Nestly CSV
99: Imported ${s.result.totalActivities} activities, ${s.result.profiles} profile(s), 
100: ${s.result.caregivers} caregiver(s) from ${s.source}. Skipped ${s.result.skippedRows} row(s).
103: Import failed: ${s.message}
108: Exported ${s.result.activities} activities, ${s.result.profiles} profile(s), 
109: ${s.result.caregivers} caregiver(s).
112: Export failed: ${s.message}
117: Activities in Nestly
123: None yet

## ui/importer/ImportViewModel.kt
57: Nara
61: Nestly
72: Could not open the selected file
92: Could not open the selected file

## ui/milestones/MilestonesScreen.kt
79: Milestones
95: $done/${group.items.size}
152: Logged
152: Log milestone

## ui/notes/NotesScreen.kt
61: Notes
61: Add
79: No notes yet
85: Jot down anything worth remembering — routines, to-dos, packing lists. 
86: Everyone in your family can see and edit notes.
92: Add note
115: Untitled
132: ${it.count { item -> item.checked }}/${it.size} done
134: Edited ${Format.relativeDay(note.updatedAt, now)}
175: Add a header or some text.
193: New Note
193: Note
195: Save
217: Header
218: e.g. Bedtime routine
232: Note
236: Write freely. Use the buttons below to start a bullet, numbered or 
237: checkbox line; pressing Enter continues it onto the next line.
238: • Bath at 7pm\n1. Feed\n☐ Buy more diapers
250: Delete note
261: Delete note?
264: This removes the note for everyone in your family.
276: Delete
281: Cancel

## ui/notes/NotesViewModel.kt
48: Add a child first
65: This note was changed by someone else.
67: Couldn't save the note.
77: Couldn't delete the note.

## ui/reminders/RemindersScreen.kt
59: Reminders
62: Get an alert after a set time since the last activity of each type.
89: ${ReminderLogic.label(kind)} interval
124: Every ${Format.duration(intervalMinutes * 60L)} after last ${ReminderLogic.label(kind).lowercase()}

## ui/theme/Type.kt
25: Start Time

## ui/trends/TrendDetailScreen.kt
99: Calendar
99: Graph
99: Entries
129: ${d.profileName} · ${metric.title} (${rangeText(d.dates)}): ${metric.summary(d.row.current.value, prefs)}
177: No entries in this period.
189: date-$date
229: Back
246: Share
331: Previous period
561: 30m
561: 2h
561: 1h 30m
568: ${m}m
569: ${h}h
570: ${h}h ${m}m
588: Nothing logged in this period.
624: $amount ${metric.noun}
636: the previous day
636: the previous ${detail.window.days} days
637: Same as $period
654: 12\nAM
655: 6\nAM
656: 12\nPM
657: 6\nPM
661: MMM d
666: ${RangeFormat.format(first)} – ${RangeFormat.format(last)}

## ui/trends/TrendsAggregator.kt
21: Feeds
22: Bottle Feed
23: Breastfeed
24: Combo Feed
25: Solids
26: Breast Milk
27: Formula
28: Unspecified
29: Pump
30: Wet
31: Dirty
32: Wet + Dirty
33: Dry
34: Sleep
35: Naps
36: Awake
46: 6.5 sessions per day
51: Feed Sessions
52: Total BF Hours
53: Daytime BF Hours
54: Nighttime BF Hours
55: BF Session Length
56: Amount Bottlefed
57: Bottle Size
58: Time Btwn Feedings
59: Pump Sessions
60: Amount Pumped
61: Total Pump Hours
62: Total Diapers
63: Daytime Diapers
64: Nighttime Diapers
65: Total Sleep
66: Daytime Sleep
67: Nighttime Sleep
68: Longest Sleep
69: Daytime Naps
70: Daytime Nap Length
71: Wake Window

## ui/trends/TrendsTab.kt
57: Nestly

## ui/trends/TrendsUi.kt
58: 150 mL
58: 3h 30m
65: 6.5 sessions per day
65: 980 mL per day
65: 3h 30m average
67: ${formatValue(value, prefs)} $noun
69: $amount per day
70: $amount average
81: Fewer sessions than the previous 14 days
81: Longer than the previous day
85: More $noun
85: Fewer $noun
86: Longer
86: Shorter
87: More
87: Less
89: the previous day
89: the previous ${window.days} days
90: $lead than $period
105: Up
105: Down
141: 1d 7d 14d

## ui/trends/TrendsViewModel.kt
23: 1d
24: 7d
25: 14d

## ui/vaccinations/VaccinationsScreen.kt
79: Vaccinations
79: Add
88: Loading…
133: Add ${profile.name}'s birth date (Account → Family → tap their name) to see due dates, 
134: recommendations and overdue doses. Vaccines you've logged still show below.
144: $givenCount of ${counted.size} scheduled doses given
162: No vaccines logged yet
168: Log the vaccines ${profile.name} has already had and Nestly will track what's due next.
173: Add vaccination
180: Up next for ${profile.name}
181: rec-${it.dose.key}
188: All scheduled doses are up to date. Nice work!
197: Vaccination chart
203: group-${group.label}
215: $groupGiven/${groupCounted.size}
235: Also recommended
249: History
257: Based on the CDC (US) immunization schedule for birth–6 years. Dose numbers are worked out 
258: from the order vaccines were logged. If a dose was late, catch-up timing can differ — 
259: this isn't medical advice, so confirm what's due with your pediatrician.
282: ${status.dose.vaccineName} — dose ${status.dose.doseNumber}
301: Given ${Format.date(it)}
301: Given
302: Was due ${Format.date(it)} · ${status.groupLabel}
303: Overdue · ${status.groupLabel}
304: Due now · recommended at ${status.groupLabel}
305: Due ${Format.date(it)} · ${status.groupLabel}
306: Recommended at ${status.groupLabel}
319: Given
323: Overdue
329: Due now
340: Log dose
348: Given
349: Overdue
350: Due now
351: Upcoming
377: Vaccine

## widget/NestlyQuickLogWidget.kt
55: Nestly
68: Bottle
75: Diaper
84: Sleep
91: Pump

## widget/QuickBottleLog.kt
153: Bottle feed saved: ${Format.volume(result.ml, units)} at ${Format.time(result.atMs)}
156: Couldn't save bottle feed. Open Nestly and sign in first.
158: Couldn't save bottle feed yet — still restoring your sign-in. Check your connection and try again.
160: Couldn't save bottle feed. Open Nestly and select a child first.
162: No default bottle amount set. Open Nestly to set one first.
164: Couldn't save bottle feed. Check your connection and try again.
226: Saving bottle feed…
