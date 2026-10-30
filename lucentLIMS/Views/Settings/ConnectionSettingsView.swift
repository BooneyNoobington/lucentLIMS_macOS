import AuthenticationServices
import SwiftUI

/// Where the data comes from and how to sign in: in Settings on the Mac, a sheet elsewhere.
struct ConnectionSettingsView: View {
    @Environment(Connection.self) private var connection
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var token = ""

    var body: some View {
        @Bindable var connection = connection

        Form {
            Section {
                Picker("Data", selection: Binding(get: { connection.source }, set: { source in
                    if source == .demo { connection.useDemoData() } else { Task { await connection.connect() } }
                })) {
                    Text("Demo data").tag(Connection.Source.demo)
                    Text("lucentAPI server").tag(Connection.Source.server)
                }
            } footer: {
                if connection.isDemo {
                    Text("The demo data lives in memory. Changes are gone when the app quits.")
                }
            }

            if !connection.isDemo {
                Section("Server") {
                    TextField("Address", text: $connection.serverURL, prompt: Text("https://lims.example.org"))
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }

                Section {
                    Picker("Sign in with", selection: $connection.method) {
                        Text("OpenID Connect").tag(Connection.SignInMethod.openIDConnect)
                        Text("Access token").tag(Connection.SignInMethod.accessToken)
                    }
                    switch connection.method {
                    case .openIDConnect:
                        TextField("Issuer", text: $connection.issuer, prompt: Text("https://id.example.org/realms/lucent"))
                            .autocorrectionDisabled()
                        TextField("Client ID", text: $connection.clientID, prompt: Text("lucentlims"))
                            .autocorrectionDisabled()
                        LabeledContent("Redirect URI", value: OpenIDConnect.redirectURI.absoluteString)
                            .textSelection(.enabled)
                    case .accessToken:
                        SecureField("Access token", text: $token, prompt: Text("eyJ…"))
                    }
                } header: {
                    Text("Sign-in")
                } footer: {
                    switch connection.method {
                    case .openIDConnect:
                        Text("Register lucentLIMS at your identity provider as a public client with this redirect URI.")
                    case .accessToken:
                        Text("For development, e.g. a token from lucentAPI's dev/mint_token.py. It expires.")
                    }
                }

                Section {
                    LabeledContent("Status") { StatusText() }
                    HStack {
                        switch connection.method {
                        case .openIDConnect:
                            Button("Sign In") { Task { await connection.signIn(with: webAuthenticationSession) } }
                        case .accessToken:
                            Button("Use Token") { Task { await connection.use(accessToken: token) } }
                                .disabled(token.isEmpty)
                        }
                        Button("Reload") { Task { await connection.connect() } }
                        Spacer()
                        Button("Sign Out", role: .destructive) { Task { await connection.signOut() } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connection")
    }
}

private struct StatusText: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        switch connection.state {
        case .ready:
            let store = connection.store
            let roles = LabRole.allCases.filter { store.roles.contains($0) }.map(\.rawValue)
            Text("\(store.currentUser.fullName) · \(roles.isEmpty ? String(localized: "read only") : roles.joined(separator: ", "))")
        case .loading:
            Text("Loading…")
        case .needsSignIn:
            Text("Not signed in").foregroundStyle(.orange)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

/// Shown instead of the data while nobody is signed in.
struct SignInView: View {
    @Environment(Connection.self) private var connection
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var token = ""

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Sign In to \(connection.summary)")
            } icon: {
                LucentMark()
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 8)
            }
        } description: {
            switch connection.method {
            case .openIDConnect:
                Text("Log in at your organization's identity provider. lucentAPI shows you what your roles allow.")
            case .accessToken:
                Text("Paste an access token, for example from lucentAPI's dev/mint_token.py.")
            }
        } actions: {
            switch connection.method {
            case .openIDConnect:
                Button("Sign In") { Task { await connection.signIn(with: webAuthenticationSession) } }
                    .buttonStyle(.borderedProminent)
            case .accessToken:
                SecureField("Access token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                Button("Connect") { Task { await connection.use(accessToken: token) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(token.isEmpty)
            }
            Button("Use Demo Data") { connection.useDemoData() }
        }
    }
}
