import Foundation
import UserNotifications

/// Local notifications for interval reminders and appointments (spec §20).
///
/// iOS limitation: Android re-checked the reminder at fire time. Local notifications can't run code
/// when they fire, so a feed logged by another caregiver while this app is suspended won't push this
/// device's reminder back until the next reschedule (background refresh or next open).
public enum NotificationScheduler {
    public static let reminderPrefix = "reminder-"
    public static let appointmentPrefix = "appointment-"
    public static let appointmentIdKey = "appointment_id"

    private static var center: UNUserNotificationCenter { .current() }

    /// Asks once; returns whether alerts are allowed.
    public static func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    public static func rescheduleAll(repos: Repositories = .shared, now: EpochMs = nowMs()) async {
        guard sessionWaitOutcome(await repos.backend.probeSession(timeout: 30)) == .SIGNED_IN else { return }
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) || $0.hasPrefix(appointmentPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        if let reminders = try? await repos.reminders.fetchMine() {
            for reminder in reminders where reminder.enabled {
                let latest: ActivityEntity?
                if reminder.kind == .FEED, let profileId = reminder.profileId {
                    latest = try? await repos.activities.latestFeedForSchedule(familyId: reminder.familyId, profileId: profileId)
                } else {
                    latest = try? await repos.activities.latestOf(
                        familyId: reminder.familyId, profileId: reminder.profileId, ReminderLogic.typesFor(reminder.kind)
                    )
                }
                guard let fire = ReminderLogic.nextFireMs(latest?.startTime, reminder.intervalMinutes, now: now) else { continue }
                let label = ReminderLogic.label(reminder.kind)
                await add(
                    id: reminderPrefix + reminder.id,
                    title: "\(label) reminder",
                    body: "Time to log the next \(label.lowercased()).",
                    fireMs: fire, now: now
                )
            }
        }
        if let appointments = try? await repos.appointments.upcomingWithReminders(now: now) {
            for appointment in appointments { await schedule(appointment, now: now) }
        }
    }

    public static func schedule(_ appointment: AppointmentEntity, now: EpochMs = nowMs()) async {
        cancel(appointmentId: appointment.id)
        guard appointment.startsAt > now - 5 * 60_000,
              let fire = AppointmentReminderLogic.fireAtMs(appointment.startsAt, appointment.reminderLead, now: now) else { return }
        await add(
            id: appointmentPrefix + appointment.id,
            title: appointment.title,
            body: appointmentBody(appointment),
            fireMs: fire, now: now,
            userInfo: [appointmentIdKey: appointment.id]
        )
    }

    public static func appointmentBody(_ a: AppointmentEntity, zone: TimeZone = .current) -> String {
        let when = Format.pattern("EEE, MMM d 'at' h:mma", a.startsAt, zone: zone)
            .replacingOccurrences(of: "AM", with: "am").replacingOccurrences(of: "PM", with: "pm")
        return ([when] + [a.doctorName, a.location].compactMap { $0?.trimmedNilIfEmpty }).joined(separator: " · ")
    }

    public static func cancel(appointmentId: String) {
        center.removePendingNotificationRequests(withIdentifiers: [appointmentPrefix + appointmentId])
    }

    public static func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    private static func add(id: String, title: String, body: String, fireMs: EpochMs, now: EpochMs, userInfo: [String: String] = [:]) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let seconds = max(1, Double(fireMs - now) / 1000)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        try? await center.add(request)
    }
}
