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
            VStack(spacing: 18) {
                Image(systemName: "bird.fill").font(.system(size: 54)).foregroundStyle(Color.accentColor).padding(.top, 60)
                Text("Nestly").font(.largeTitle.bold())
                Text(signUp ? "Create your account to share tracking with your family." : "Sign in to see your family's tracking.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(signUp ? .newPassword : .password)
                    if signUp {
                        TextField("Your name (as caregiver)", text: $name).textContentType(.name)
                    }
                }
                .textFieldStyle(.roundedBorder)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button { submit() } label: {
                    Text(busy ? "Please wait…" : signUp ? "Create account" : "Sign in").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(busy || email.isBlank || password.isEmpty)
                Button(signUp ? "Already have an account? Sign in" : "New to Nestly? Create an account") {
                    signUp.toggle()
                    message = nil
                }
                .font(.footnote)
            }
            .padding(24)
        }
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
            VStack(spacing: 18) {
                Text("Welcome to Nestly").font(.largeTitle.bold()).padding(.top, 48)
                if hasFamily { childStep } else { familyStep }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Sign out") { Task { await app.signOut() } }.padding(.top, 12)
            }
            .padding(24)
        }
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
        VStack(spacing: 14) {
            Text("Start a new family, or join one with an invite code from another caregiver.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            TextField("Your name (as caregiver)", text: $name).textFieldStyle(.roundedBorder).textContentType(.name)
            Button { createFamily() } label: { Text("Create my family").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
            Divider().padding(.vertical, 6)
            TextField("Invite code", text: $code)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button { join() } label: { Text("Join with invite code").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
                .disabled(busy || code.isBlank || name.isBlank)
        }
    }

    private var childStep: some View {
        VStack(spacing: 14) {
            Text("Add your first child to start tracking, or do a one-time import of your Nara Baby history.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { addingChild = true } label: { Text("Add child").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button { importing = true } label: { Text(busy ? "Importing…" : "Import from Nara instead").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large).disabled(busy)
            Divider().padding(.vertical, 6)
            if showJoin {
                Text("Another caregiver can create a code in Account → Family.")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                joinFields
            } else {
                Button("Join a family with an invite code instead") { showJoin = true }
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder private var joinFields: some View {
        TextField("Your name (as caregiver)", text: $name).textFieldStyle(.roundedBorder).textContentType(.name)
        TextField("Invite code", text: $code)
            .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled()
        Button { join() } label: { Text("Join with invite code").frame(maxWidth: .infinity) }
            .buttonStyle(.bordered).controlSize(.large)
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
