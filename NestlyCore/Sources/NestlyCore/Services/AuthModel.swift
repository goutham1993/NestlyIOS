import Foundation
import Observation
import Supabase

public enum AuthStatus: Equatable, Sendable {
    case loading
    case signedOut
    case signedIn(userId: String)

    public var userId: String? {
        if case let .signedIn(id) = self { return id }
        return nil
    }
}

/// `loading → signedOut | signedIn`. Once signed in, token refreshes and other transient events
/// never send the app back to loading (spec §8.1).
@MainActor
@Observable
public final class AuthModel {
    public static let shared = AuthModel()

    public private(set) var status: AuthStatus = .loading
    public private(set) var email: String?

    @ObservationIgnored private let backend: Backend
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(backend: Backend = .shared) { self.backend = backend }

    public func start() {
        guard task == nil else { return }
        let auth = backend.client.auth
        task = Task { [weak self] in
            for await (event, session) in auth.authStateChanges {
                self?.handle(event, session)
            }
        }
    }

    private func handle(_ event: AuthChangeEvent, _ session: Session?) {
        switch event {
        case .initialSession:
            apply(session)
        case .signedIn, .tokenRefreshed, .userUpdated, .mfaChallengeVerified, .passwordRecovery:
            if let session { apply(session) }
        case .signedOut, .userDeleted:
            apply(nil)
        }
    }

    private func apply(_ session: Session?) {
        if let session {
            let next = AuthStatus.signedIn(userId: session.user.id.uuidString.lowercased())
            if next != status { status = next }
            email = session.user.email
        } else {
            status = .signedOut
            email = nil
        }
    }

    public func signIn(email: String, password: String) async throws {
        let session = try await backend.client.auth.signIn(email: email.trimmed, password: password)
        apply(session)
    }

    /// Returns true when a session exists right away (email confirmation off).
    public func signUp(email: String, password: String) async throws -> Bool {
        let response = try await backend.client.auth.signUp(email: email.trimmed, password: password)
        if let session = response.session {
            apply(session)
            return true
        }
        return false
    }

    public func signOut() async {
        try? await backend.client.auth.signOut()
        apply(nil)
    }
}
