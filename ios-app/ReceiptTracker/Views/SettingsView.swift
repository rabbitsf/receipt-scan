import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = APIKeyStore.load() ?? ""
    @State private var hasStoredKey: Bool = APIKeyStore.load() != nil
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-...", text: $apiKey)
                        .accessibilityIdentifier("apiKeyField")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Used only to scan receipt photos directly from this device via Claude's Vision API. Stored securely in the iOS Keychain and never sent anywhere except api.anthropic.com. Get a key at console.anthropic.com.")
                }

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                if hasStoredKey {
                    Button("Remove Key", role: .destructive) {
                        APIKeyStore.delete()
                        apiKey = ""
                        hasStoredKey = false
                        statusMessage = "Key removed."
                    }
                    .accessibilityIdentifier("removeAPIKeyButton")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try APIKeyStore.save(apiKey)
                            hasStoredKey = true
                            statusMessage = "Saved."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                    .disabled(apiKey.isEmpty)
                    .accessibilityIdentifier("saveAPIKeyButton")
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
