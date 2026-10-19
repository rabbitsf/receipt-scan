import XCTest

extension XCUIApplication {
    /// The app under test, launched with the "no API key" launch popup
    /// turned off (via the UserDefaults argument domain, which overrides the
    /// stored value without changing it). Every UI test starts without a
    /// saved key, so the popup would otherwise cover the screen. Tests of
    /// the popup itself (`MissingKeyWarningFlowTests`) build their own app.
    static func receiptTracker() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ocrKeyWarningDismissed", "YES"]
        // AI permission pre-granted for every provider (same argument-domain
        // trick); `AIScanConsentFlowTests` builds its own app to test the prompt.
        for provider in ["anthropic", "openai", "gemini"] {
            app.launchArguments += ["-aiScanConsent.\(provider)", "YES"]
        }
        return app
    }
}

extension XCUIElement {
    /// Swipes `container` until this element is on screen. Forms and lists
    /// only expose rows that are visible — and which rows fit differs
    /// between iPhone and the iPad's smaller sheets.
    @discardableResult
    func scrolledIntoView(in container: XCUIApplication, up: Bool = true, maxSwipes: Int = 10) -> XCUIElement {
        var swipes = 0
        while !(exists && isHittable) && swipes < maxSwipes {
            // Slow, so a short iPad sheet doesn't fling past the element.
            up ? container.swipeUp(velocity: .slow) : container.swipeDown(velocity: .slow)
            swipes += 1
        }
        return self
    }
}
