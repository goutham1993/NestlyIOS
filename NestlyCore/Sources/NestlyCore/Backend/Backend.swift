import Foundation
import Security
import Supabase

/// Rows with an optimistic-lock version column.
public protocol VersionedDto: Codable, Sendable {
    var id: String { get }
    var version: Int { get set }
    var updatedAt: String { get set }
}

extension FamilyDto: VersionedDto {}
extension CaregiverDto: VersionedDto {}
extension ProfileDto: VersionedDto {}
extension ReminderDto: VersionedDto {}
extension ActivityDto: VersionedDto {}
extension AppointmentDto: VersionedDto {}
extension NoteDto: VersionedDto {}

/// The single Supabase client plus the shared refresh bus. Used by the app, the widget
/// extension and App Intents; the auth session lives in a shared keychain access group.
public final class Backend: Sendable {
    public static let shared = Backend()

    public let client: SupabaseClient
    public let bus: RefreshBus
    public let prefs: Preferences

    public init(bus: RefreshBus = .shared, prefs: Preferences = .shared) {
        self.bus = bus
        self.prefs = prefs
        let storage = KeychainLocalStorage(service: AppConfig.keychainService, accessGroup: Self.usableKeychainGroup())
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: SupabaseClientOptions(
                auth: .init(storage: storage, emitLocalSessionAsInitialSession: true)
            )
        )
    }

    /// The shared access group when this build carries the entitlement, else the default group
    /// (unsigned simulator builds), so sign-in still works in the app.
    static func usableKeychainGroup() -> String? {
        let group = AppConfig.keychainGroup
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "nestly.keychain.probe",
            kSecAttrAccount as String: "probe",
            kSecAttrAccessGroup as String: group,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data([1])
        let status = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete(base as CFDictionary)
        return status == errSecSuccess || status == errSecDuplicateItem ? group : nil
    }

    public var currentUserId: String? { client.auth.currentSession?.user.id.uuidString.lowercased() }
    public var currentEmail: String? { client.auth.currentSession?.user.email }

    public func from(_ table: String) -> PostgrestQueryBuilder { client.from(table) }

    /// Waits for a definitive auth verdict (spec §21.1): restores the stored session and refreshes
    /// it if needed. nil = still not ready when the wait ran out.
    public func probeSession(timeout: Double = 30) async -> SessionProbe? {
        guard client.auth.currentSession != nil else { return .signedOut }
        let auth = client.auth
        do {
            return try await withTimeout(seconds: timeout) { () async throws -> SessionProbe in
                do {
                    _ = try await auth.session
                    return .signedIn
                } catch let error as AuthError {
                    if case .sessionMissing = error { return .signedOut }
                    return .refreshFailed
                }
            }
        } catch {
            return .refreshFailed
        }
    }

    // MARK: - Writes

    /// Inserts without reading the row back (RLS may not let a brand-new row be selected yet).
    public func insert<D: Encodable & Sendable>(_ table: String, _ rows: D) async throws {
        try await from(table).insert(rows, returning: .minimal).execute()
    }

    public func upsert<D: Encodable & Sendable>(_ table: String, _ rows: [D], chunk: Int = 200) async throws {
        var start = 0
        while start < rows.count {
            let slice = Array(rows[start ..< min(rows.count, start + chunk)])
            try await from(table).upsert(slice, onConflict: "id", returning: .minimal).execute()
            start += chunk
        }
    }

    /// `UPDATE … SET version = old + 1 WHERE id = :id AND version = :old`, then checks the returned
    /// row actually carries the new version (a stale write may be dropped by `keep_newer_row`).
    @discardableResult
    public func versionedUpdate<D: VersionedDto>(_ table: String, _ row: D, now: EpochMs = nowMs()) async throws -> D {
        let oldVersion = row.version
        var next = row
        next.version = oldVersion + 1
        next.updatedAt = now.toIso()
        let updated: [D] = try await from(table)
            .update(next)
            .eq("id", value: row.id)
            .eq("version", value: oldVersion)
            .select()
            .execute()
            .value
        guard let fresh = updated.first, fresh.version == oldVersion + 1 else { throw ConflictError() }
        return fresh
    }

    /// Version-checked soft delete.
    public func softDelete(_ table: String, id: String, version: Int, now: EpochMs = nowMs()) async throws {
        let updated: [TypeIdVersion] = try await from(table)
            .update(SoftDeletePatch(now: now, version: version + 1))
            .eq("id", value: id)
            .eq("version", value: version)
            .select("id,version")
            .execute()
            .value
        guard updated.first?.version == version + 1 else { throw ConflictError() }
    }

    /// Pages through a query 1000 rows at a time (PostgREST's default cap).
    public func fetchAll<T: Decodable & Sendable>(
        pageSize: Int = 1000,
        _ query: @Sendable (_ from: Int, _ to: Int) -> PostgrestTransformBuilder
    ) async throws -> [T] {
        var all: [T] = []
        var offset = 0
        while true {
            let page: [T] = try await query(offset, offset + pageSize - 1).execute().value
            all += page
            if page.count < pageSize { return all }
            offset += pageSize
        }
    }
}

struct TypeIdVersion: Decodable, Sendable {
    let id: String
    let version: Int
}

/// Friendly copy for auth / invite failures (spec §10.1), matched in this order.
public enum FriendlyError {
    public static func auth(_ error: Error) -> String {
        let raw = message(error)
        let lower = raw.lowercased()
        if lower.contains("rate limit") {
            return "Supabase's built-in email limit was hit, so no confirmation email was sent and the account wasn't created. For testing, turn off \"Confirm email\" in Supabase Dashboard → Authentication → Providers → Email, then try again."
        }
        if lower.contains("invalid login") { return "Wrong email or password." }
        if lower.contains("already registered") { return "That email already has an account. Sign in instead." }
        if lower.contains("invite") { return "That invite code is invalid or expired." }
        return raw.isBlank ? "Something went wrong. Check your connection and try again." : raw
    }

    public static func message(_ error: Error) -> String {
        if let e = error as? AuthError { return e.message }
        if let e = error as? PostgrestError { return e.message }
        if let e = error as? ImportError { return e.message }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
