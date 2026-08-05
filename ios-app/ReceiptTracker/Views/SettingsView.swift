import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var receipts: [Receipt]
    @Query(sort: \CustomCategory.name) private var customCategories: [CustomCategory]
    @Query(sort: \CustomGroup.name) private var customGroups: [CustomGroup]

    @State private var apiKey: String = APIKeyStore.load() ?? ""
    @State private var hasStoredKey: Bool = APIKeyStore.load() != nil
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

    /// Every non-predefined category currently known — Settings-created
    /// (`customCategories`) or already in use on a receipt via the form's
    /// "Custom category…" field. Same merge `CategoryOptions` already uses
    /// elsewhere, `predefined` dropped since those get their own read-only
    /// rows above this list.
    private var customCategoryNames: [String] {
        Array(
            CategoryOptions.mergeWithInUseCategories(
                receipts.compactMap(\.category),
                customCategories: customCategories.map(\.name)
            )
            .dropFirst(CategoryOptions.predefined.count)
        )
    }

    private var groupNames: [String] {
        GroupOptions.availableGroups(from: receipts, customGroups: customGroups.map(\.name))
    }

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

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { newCategoryName = "" }
        guard !trimmed.isEmpty, !CategoryOptions.predefined.contains(trimmed), !customCategoryNames.contains(trimmed) else {
            return
        }
        modelContext.insert(CustomCategory(name: trimmed))
        try? modelContext.save()
    }

    private func requestDeleteCategory(_ category: String) {
        let count = CategoryOptions.usageCount(of: category, in: receipts)
        guard count == 0 else {
            deleteBlockedMessage = "\"\(category)\" is used by \(count) receipt\(count == 1 ? "" : "s") and can't be deleted. Change or clear that field on those receipts first."
            return
        }
        if let existing = customCategories.first(where: { $0.name == category }) {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    private func commitRenameCategory(from oldName: String) {
        defer { renamingCategory = nil }
        let trimmed = renameCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName, !CategoryOptions.predefined.contains(trimmed) else { return }
        CategoryOptions.renameInUse(from: oldName, to: trimmed, in: receipts)
        if let existing = customCategories.first(where: { $0.name == oldName }) {
            existing.name = trimmed
        } else {
            modelContext.insert(CustomCategory(name: trimmed))
        }
        try? modelContext.save()
    }

    private func addGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { newGroupName = "" }
        guard !trimmed.isEmpty, !groupNames.contains(trimmed) else { return }
        modelContext.insert(CustomGroup(name: trimmed))
        try? modelContext.save()
    }

    private func requestDeleteGroup(_ group: String) {
        let count = GroupOptions.usageCount(of: group, in: receipts)
        guard count == 0 else {
            deleteBlockedMessage = "\"\(group)\" is used by \(count) receipt\(count == 1 ? "" : "s") and can't be deleted. Change or clear that field on those receipts first."
            return
        }
        if let existing = customGroups.first(where: { $0.name == group }) {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    private func commitRenameGroup(from oldName: String) {
        defer { renamingGroup = nil }
        let trimmed = renameGroupText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != oldName else { return }
        GroupOptions.renameInUse(from: oldName, to: trimmed, in: receipts)
        if let existing = customGroups.first(where: { $0.name == oldName }) {
            existing.name = trimmed
        } else {
            modelContext.insert(CustomGroup(name: trimmed))
        }
        try? modelContext.save()
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
