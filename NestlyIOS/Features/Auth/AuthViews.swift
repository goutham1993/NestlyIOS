import NestlyCore
import SwiftUI
import UniformTypeIdentifiers

struct AuthView: View {
    @Environment(AppModel.self) private var app
    @State private var signUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                BrandHeader(
                    title: "Nestly",
                    message: signUp ? "Create your account to share tracking with your family." : "Sign in to see your family's tracking."
                )
                .padding(.top, 56)
                FieldGroup {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Divider()
                    SecureField("Password", text: $password)
                        .textContentType(signUp ? .newPassword : .password)
                    if signUp {
                        Divider()
                        TextField("Your name (as caregiver)", text: $name).textContentType(.name)
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(Palette.critical).multilineTextAlignment(.center)
                }
                VStack(spacing: Space.m) {
                    Button { submit() } label: {
                        if busy { ProgressView().tint(.white) } else { Text(signUp ? "Create Account" : "Sign In") }
                    }
                    .buttonStyle(.primary)
                    .disabled(busy || email.isBlank || password.isEmpty)
                    Button(signUp ? "Already have an account? Sign in" : "New to Nestly? Create an account") {
                        withAnimation(.snappy) { signUp.toggle() }
                        message = nil
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
    }

    private func submit() {
        busy = true
        message = nil
        Task {
            defer { busy = false }
            do {
                if signUp {
                    let hasSession = try await app.auth.signUp(email: email, password: password)
                    if hasSession {
                        _ = try? await app.repos.family.createFamily(caregiverName: name)
                    } else {
                        app.prefs.pendingCaregiverName = name.trimmedNilIfEmpty
                        message = "Check your email to confirm your account, then sign in."
                        signUp = false
                    }
                } else {
                    try await app.auth.signIn(email: email, password: password)
                }
            } catch {
                message = FriendlyError.auth(error)
            }
        }
    }
}

/// Signed in but no children yet (spec §10.2 / §10.3).
struct OnboardingView: View {
    let hasFamily: Bool
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?
    @State private var addingChild = false
    @State private var importing = false
    @State private var showJoin = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xl) {
                BrandHeader(
                    title: "Welcome to Nestly",
                    message: hasFamily
                        ? "Add your first child to start tracking, or do a one-time import of your Nara Baby history."
                        : "Start a new family, or join one with an invite code from another caregiver."
                )
                .padding(.top, 48)
                if hasFamily { childStep } else { familyStep }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Sign Out") { Task { await app.signOut() } }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(Space.xl)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .onAppear { name = app.prefs.pendingCaregiverName ?? app.family.currentCaregiver?.name ?? "" }
        .sheet(isPresented: $addingChild) {
            ChildForm(title: "Add child", askCaregiverName: false) { childName, sex, birth, _ in
                try await app.repos.family.addChild(name: childName, sex: sex, birthDate: birth, caregiverName: app.prefs.pendingCaregiverName ?? "")
                app.prefs.pendingCaregiverName = nil
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: ImportTypes.all) { result in
            runNaraImport(result)
        }
    }

    private var familyStep: some View {
        VStack(spacing: Space.m) {
            FieldGroup {
                TextField("Your name (as caregiver)", text: $name).textContentType(.name)
            }
            Button("Create My Family") { createFamily() }
                .buttonStyle(.primary).disabled(busy)
            OrDivider()
            FieldGroup {
                TextField("Invite code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
            }
            Button("Join with Invite Code") { join() }
                .buttonStyle(.secondary)
                .disabled(busy || code.isBlank || name.isBlank)
        }
    }

    private var childStep: some View {
        VStack(spacing: Space.m) {
            Button { addingChild = true } label: { Label("Add Child", systemImage: "plus") }
                .buttonStyle(.primary)
            Button { importing = true } label: { Text(busy ? "Importing…" : "Import from Nara Instead") }
                .buttonStyle(.secondary).disabled(busy)
            OrDivider()
            if showJoin {
                Text("Another caregiver can create a code in Account → Family.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                joinFields
            } else {
                Button("Join a family with an invite code instead") { withAnimation(.snappy) { showJoin = true } }
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder private var joinFields: some View {
        FieldGroup {
            TextField("Your name (as caregiver)", text: $name).textContentType(.name)
            Divider()
            TextField("Invite code", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
        }
        Button("Join with Invite Code") { join() }
            .buttonStyle(.secondary)
            .disabled(busy || code.isBlank || name.isBlank)
    }

    private func createFamily() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await app.repos.family.createFamily(caregiverName: name)
                app.prefs.pendingCaregiverName = nil
            } catch {
                message = "Couldn't save. Check your connection and try again."
            }
        }
    }

    private func join() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await app.repos.family.joinWithInvite(code: code, name: name)
                app.prefs.pendingCaregiverName = nil
            } catch {
                message = FriendlyError.auth(error)
            }
        }
    }

    private func runNaraImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result, let data = ImportTypes.read(url) else {
            message = "Could not open the selected file"
            return
        }
        busy = true
        message = "Importing your Nara history…"
        Task {
            defer { busy = false }
            do {
                let imported = try await DataTransfer(repos: app.repos).importNara(data)
                message = imported.onboardingMessage
            } catch let error as ImportError {
                message = error.message
            } catch {
                message = "Import failed. Check your connection and try again."
            }
        }
    }
}

private struct BrandHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Space.m) {
            IconTile(icon: .system("bird.fill"), tint: Palette.accent, size: 76, filled: true)
                .accessibilityHidden(true)
            Text(title).font(.rounded(.largeTitle, weight: .bold)).multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
    }
}

/// Inset grouped text fields, matching Settings-style forms.
private struct FieldGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) { content }
            .padding(.vertical, Space.m)
            .padding(.horizontal, Space.l)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
}

private struct OrDivider: View {
    var body: some View {
        HStack(spacing: Space.m) {
            VStack { Divider() }
            Text("or").font(.footnote).foregroundStyle(.secondary)
            VStack { Divider() }
        }
        .padding(.vertical, Space.xs)
    }
}

enum ImportTypes {
    static let all: [UTType] = [
        .commaSeparatedText, .tabSeparatedText, .plainText, .xml, .html, .data,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
        UTType("com.microsoft.excel.xls") ?? .data,
    ]

    static func read(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}
