import Foundation

/// The AI services that can scan receipts. Chosen in Settings; every scan
/// goes through `ReceiptExtractor`, which routes to this provider's
/// `VisionOCRClient`.
enum OCRProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    /// Used when the user hasn't overridden the model in Settings.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-8"
        case .openai: return "gpt-6.1-sol"
        case .gemini: return "gemini-3.8-flash"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        }
    }

    var apiHost: String {
        switch self {
        case .anthropic: return "api.anthropic.com"
        case .openai: return "api.openai.com"
        case .gemini: return "generativelanguage.googleapis.com"
        }
    }

    var keyConsoleHint: String {
        switch self {
        case .anthropic: return "console.anthropic.com"
        case .openai: return "platform.openai.com"
        case .gemini: return "aistudio.google.com"
        }
    }

    var client: VisionOCRClient.Type {
        switch self {
        case .anthropic: return AnthropicVisionClient.self
        case .openai: return OpenAIVisionClient.self
        case .gemini: return GeminiVisionClient.self
        }
    }
}

/// Non-secret OCR preferences (active provider, per-provider model
/// override), stored in `UserDefaults`. API keys are secrets and live in the
/// Keychain via `APIKeyStore` instead.
enum OCRSettings {
    private static let providerKey = "ocrProvider"
    private static let keyWarningDismissedKey = "ocrKeyWarningDismissed"
    private static func modelKey(for provider: OCRProvider) -> String { "ocrModel.\(provider.rawValue)" }

    /// Defaults to Claude, so existing installs keep scanning exactly as
    /// before until the user picks something else.
    static func selectedProvider(defaults: UserDefaults = .standard) -> OCRProvider {
        defaults.string(forKey: providerKey).flatMap(OCRProvider.init(rawValue:)) ?? .anthropic
    }

    static func setSelectedProvider(_ provider: OCRProvider, defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: providerKey)
    }

    /// The user's override, or nil when they're using the default.
    static func modelOverride(for provider: OCRProvider, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: modelKey(for: provider))
    }

    /// Blank clears the override (back to `defaultModel`).
    static func setModelOverride(_ model: String, for provider: OCRProvider, defaults: UserDefaults = .standard) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: modelKey(for: provider))
        } else {
            defaults.set(trimmed, forKey: modelKey(for: provider))
        }
    }

    static func effectiveModel(for provider: OCRProvider, defaults: UserDefaults = .standard) -> String {
        modelOverride(for: provider, defaults: defaults) ?? provider.defaultModel
    }

    /// Set by the launch warning's "Don't Show Again"; permanent.
    static func keyWarningDismissed(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: keyWarningDismissedKey)
    }

    static func dismissKeyWarning(defaults: UserDefaults = .standard) {
        setKeyWarningDismissed(true, defaults: defaults)
    }

    /// `false` brings the launch warning back (used by the Web Access API,
    /// mirroring the web app's `keyWarningDismissed` setting).
    static func setKeyWarningDismissed(_ dismissed: Bool, defaults: UserDefaults = .standard) {
        if dismissed {
            defaults.set(true, forKey: keyWarningDismissedKey)
        } else {
            defaults.removeObject(forKey: keyWarningDismissedKey)
        }
    }

    /// Whether to show the "no API key" popup at launch: the selected
    /// provider has no saved key and the user hasn't chosen Don't Show
    /// Again. The app still works without a key — only scanning needs one.
    static func shouldShowMissingKeyWarning(
        defaults: UserDefaults = .standard,
        hasKey: (OCRProvider) -> Bool = { APIKeyStore.load(for: $0)?.isEmpty == false }
    ) -> Bool {
        !keyWarningDismissed(defaults: defaults) && !hasKey(selectedProvider(defaults: defaults))
    }
}
