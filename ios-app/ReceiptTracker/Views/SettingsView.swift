import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var receipts: [Receipt]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @Query(sort: \CustomGroup.name) private var customGroups: [CustomGroup]

    @State private var provider: OCRProvider = OCRSettings.selectedProvider()
    @State private var apiKey: String = APIKeyStore.load(for: OCRSettings.selectedProvider()) ?? ""
    @State private var hasStoredKey: Bool = APIKeyStore.load(for: OCRSettings.selectedProvider()) != nil
    @State private var modelText: String = OCRSettings.modelOverride(for: OCRSettings.selectedProvider()) ?? ""
    @State private var statusMessage: String?

    @State private var isDriveConnected = GoogleDriveAuth.isSignedIn
    @State private var isConnectingDrive = false
    @State private var driveStatusMessage: String?

    @State private var newCategoryName = ""
    @State private var renamingCategory: String?
    @State private var renameCategoryText = ""

    @State private var newGroupName = ""
    @State private var renamingGroup: String?
    @State private var renameGroupText = ""

    @State private var deleteBlockedMessage: String?

    @ObservedObject private var webAccess = WebAccessServer.shared

    /// Every non-predefined category currently known — Settings-created
    /// (`customCategories`) or already in use on a receipt via the form's
    /// "Custom category…" field. Same merge `CategoryOptions` already uses
    /// elsewhere, `predefined` dropped since those get their own read-only
    /// rows above this list.
    private var customCategoryNames: [String] {
        CustomValueStore.listedNames(.category, receipts: receipts, customNames: customCategories.map(\.name))
    }

    private var groupNames: [String] {
        CustomValueStore.listedNames(.group, receipts: receipts, customNames: customGroups.map(\.name))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(OCRProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ocrProviderPicker")
                    SecureField(provider.keyPlaceholder, text: $apiKey)
                        .accessibilityIdentifier("apiKeyField")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(provider.defaultModel, text: $modelText)
                        .accessibilityIdentifier("ocrModelField")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Receipt Scanning")
                } footer: {
                    Text("Choose which AI scans your receipt photos, directly from this device. Each provider keeps its own \(provider.displayName) API key, stored securely in the iOS Keychain and never sent anywhere except \(provider.apiHost). Get a key at \(provider.keyConsoleHint). Leave the model blank to use \(provider.defaultModel).")
                }
                .onChange(of: provider) { _, newProvider in
                    OCRSettings.setSelectedProvider(newProvider)
                    apiKey = APIKeyStore.load(for: newProvider) ?? ""
                    hasStoredKey = APIKeyStore.load(for: newProvider) != nil
                    modelText = OCRSettings.modelOverride(for: newProvider) ?? ""
                    statusMessage = nil
                }

                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                if hasStoredKey {
                    Button("Remove Key", role: .destructive) {
                        APIKeyStore.delete(for: provider)
                        apiKey = ""
                        hasStoredKey = false
                        statusMessage = "Key removed."
                    }
                    .accessibilityIdentifier("removeAPIKeyButton")
                }

                Section {
                    if isDriveConnected {
                        if let email = GoogleDriveAuth.signedInEmail {
                            Text(email)
                                .foregroundStyle(.secondary)
                        }
                        Button("Disconnect", role: .destructive) {
                            GoogleDriveAuth.signOut()
                            isDriveConnected = false
                            driveStatusMessage = "Disconnected."
                        }
                        .accessibilityIdentifier("disconnectDriveButton")
                    } else {
                        Button {
                            connectToDrive()
                        } label: {
                            if isConnectingDrive {
                                ProgressView()
                            } else {
                                Text("Connect to Google Drive")
                            }
                        }
                        .disabled(isConnectingDrive)
                        .accessibilityIdentifier("connectDriveButton")
                    }

                    if let driveStatusMessage {
                        Text(driveStatusMessage)
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .accessibilityIdentifier("driveStatusMessage")
                    }
                } header: {
                    Text("Google Drive")
                } footer: {
                    Text("Connect once here to upload receipt photos to a \"Receipt Tracker\" folder in your Google Drive — from a receipt's photo view, or for multiple receipts at once via Select.")
                }

                Section {
                    Toggle("Web Access", isOn: Binding(
                        get: { webAccess.isEnabled },
                        set: { isOn in
                            if isOn {
                                webAccess.start(context: modelContext)
                            } else {
                                webAccess.stop()
                            }
                        }
                    ))
                    .accessibilityIdentifier("webAccessToggle")
                    if webAccess.isEnabled {
                        if let errorMessage = webAccess.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("webAccessError")
                        } else {
                            LabeledContent("Address") {
                                Text(webAccess.address ?? "Not on Wi-Fi")
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("webAccessAddress")
                            }
                            LabeledContent("Access code") {
                                Text(webAccess.accessCode ?? "")
                                    .font(.title3.monospacedDigit().bold())
                                    .accessibilityIdentifier("webAccessCode")
                            }
                        }
                    }
                } header: {
                    Text("Web Access over Wi-Fi")
                } footer: {
                    Text("Use the receipt web app on a computer on the same Wi-Fi: open the address in its browser and enter the code. Keep this app open while you use it.")
                }

                Section {
                    ForEach(CategoryOptions.predefined, id: \.self) { category in
                        categoryLabel(category)
                    }
                    ForEach(customCategoryNames, id: \.self) { category in
                        categoryRow(category)
                    }
                    HStack {
                        TextField("New category", text: $newCategoryName)
                            .accessibilityIdentifier("newCategoryNameField")
                        Button("Add") { addCategory() }
                            .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("addCategoryButton")
                    }
                } header: {
                    Text("Categories")
                } footer: {
                    Text("The 8 built-in categories can't be renamed or removed. Categories added here — or typed as \"Custom category…\" on a receipt — show up in the category picker right away.")
                }

                Section {
                    ForEach(groupNames, id: \.self) { group in
                        groupRow(group)
                    }
                    HStack {
                        TextField("New group", text: $newGroupName)
                            .accessibilityIdentifier("newGroupNameField")
                        Button("Add") { addGroup() }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("addGroupButton")
                    }
                } header: {
                    Text("Groups")
                } footer: {
                    Text("Groups added here — or typed as \"New group…\" on a receipt — show up in the group picker right away.")
                }
            }
            .alert("Can't Delete", isPresented: Binding(
                get: { deleteBlockedMessage != nil },
                set: { isPresented in if !isPresented { deleteBlockedMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteBlockedMessage ?? "")
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try APIKeyStore.save(apiKey, for: provider)
                            OCRSettings.setModelOverride(modelText, for: provider)
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

    @ViewBuilder
    private func categoryLabel(_ category: String) -> some View {
        Label {
            Text(category)
        } icon: {
            Image(systemName: CategoryOptions.icon(for: category))
                .foregroundStyle(CategoryOptions.color(for: category))
        }
    }

    @ViewBuilder
    private func categoryRow(_ category: String) -> some View {
        if renamingCategory == category {
            HStack {
                TextField(category, text: $renameCategoryText)
                    .accessibilityIdentifier("renameCategoryField")
                Button("Save") { commitRenameCategory(from: category) }
                    .accessibilityIdentifier("saveRenameCategoryButton")
                Button("Cancel", role: .cancel) { renamingCategory = nil }
            }
        } else {
            HStack {
                categoryLabel(category)
                Spacer()
            }
            // `Label`'s own icon+text accessibility merge reports only the
            // icon's small frame once `.swipeActions` is attached (observed
            // via XCUITest: a `.swipeLeft()` on that frame lands too close
            // to the row's leading edge and gets misread as a system
            // edge-swipe, dismissing the whole Settings sheet instead of
            // revealing the actions). Explicitly combining into ONE element
            // over this full-width `HStack` (via the `Spacer()`) fixes the
            // reported frame to the whole row.
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("categoryRow_\(category)")
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) { requestDeleteCategory(category) }
                    .accessibilityIdentifier("deleteCategoryButton_\(category)")
                Button("Rename") {
                    renamingCategory = category
                    renameCategoryText = ""
                }
                .tint(.blue)
                .accessibilityIdentifier("renameCategoryButton_\(category)")
            }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: String) -> some View {
        if renamingGroup == group {
            HStack {
                TextField(group, text: $renameGroupText)
                    .accessibilityIdentifier("renameGroupField")
                Button("Save") { commitRenameGroup(from: group) }
                    .accessibilityIdentifier("saveRenameGroupButton")
                Button("Cancel", role: .cancel) { renamingGroup = nil }
            }
        } else {
            HStack {
                Label {
                    Text(group)
                } icon: {
                    Image(systemName: GroupOptions.icon(for: group))
                        .foregroundStyle(GroupOptions.color(for: group))
                }
                Spacer()
            }
            // See `categoryRow`'s comment on the same pattern.
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("groupRow_\(group)")
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) { requestDeleteGroup(group) }
                    .accessibilityIdentifier("deleteGroupButton_\(group)")
                Button("Rename") {
                    renamingGroup = group
                    renameGroupText = ""
                }
                .tint(.blue)
                .accessibilityIdentifier("renameGroupButton_\(group)")
            }
        }
    }

    // Add/rename/delete rules live in `CustomValueStore` (shared with the
    // Web Access API); these only wire them to this screen's state.
    private func addCategory() {
        CustomValueStore.add(newCategoryName, kind: .category, in: modelContext)
        newCategoryName = ""
    }

    private func requestDeleteCategory(_ category: String) {
        if case .blocked(let count) = CustomValueStore.delete(category, kind: .category, in: modelContext) {
            deleteBlockedMessage = CustomValueStore.blockedMessage(category, usageCount: count)
        }
    }

    private func commitRenameCategory(from oldName: String) {
        CustomValueStore.rename(oldName, to: renameCategoryText, kind: .category, in: modelContext)
        renamingCategory = nil
    }

    private func addGroup() {
        CustomValueStore.add(newGroupName, kind: .group, in: modelContext)
        newGroupName = ""
    }

    private func requestDeleteGroup(_ group: String) {
        if case .blocked(let count) = CustomValueStore.delete(group, kind: .group, in: modelContext) {
            deleteBlockedMessage = CustomValueStore.blockedMessage(group, usageCount: count)
        }
    }

    private func commitRenameGroup(from oldName: String) {
        CustomValueStore.rename(oldName, to: renameGroupText, kind: .group, in: modelContext)
        renamingGroup = nil
    }

    private func connectToDrive() {
        guard let presenter = Self.topViewController() else {
            driveStatusMessage = "Couldn't present the Google sign-in screen."
            return
        }
        isConnectingDrive = true
        driveStatusMessage = nil
        Task {
            do {
                try await GoogleDriveAuth.signIn(presenting: presenter)
                isDriveConnected = true
                driveStatusMessage = "Connected."
            } catch {
                driveStatusMessage = error.localizedDescription
            }
            isConnectingDrive = false
        }
    }

    /// Google's sign-in UI (`ASWebAuthenticationSession`/`SFSafariViewController`
    /// depending on iOS version) needs a `UIViewController` to present from
    /// — SwiftUI has no first-class way to hand one over, so this walks
    /// UIKit's scene/window hierarchy to the topmost presented controller
    /// (this Settings sheet itself, typically), the standard workaround for
    /// UIKit-presenting SDKs called from pure SwiftUI.
    @MainActor
    private static func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return nil
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Receipt.self, CustomCategory.self, CustomGroup.self], inMemory: true)
}
