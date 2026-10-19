import XCTest

/// Turns on Web Access in Settings, then talks to the real server over the
/// network from the test process (the Simulator shares the Mac's network,
/// so 127.0.0.1 reaches the app): the code page blocks the API until the
/// code shown in Settings is entered.
final class WebAccessFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testToggleShowsCodeAndServerRequiresIt() async throws {
        let app = await MainActor.run { () -> XCUIApplication in
            let app = XCUIApplication.receiptTracker()
            app.launch()
            return app
        }
        let code = try await MainActor.run { () -> String in
            let settingsButton = app.buttons["settingsButton"]
            XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
            settingsButton.tap()

            let toggle = app.switches["webAccessToggle"]
            toggle.scrolledIntoView(in: app)
            XCTAssertTrue(toggle.isHittable)
            // Tap the switch itself (right edge); the row's middle is its label.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

            let codeLabel = app.staticTexts["webAccessCode"]
            // The code row appears below the switch; rows off-screen aren't in
            // the hierarchy, so scroll it into view.
            if !codeLabel.waitForExistence(timeout: 3) { codeLabel.scrolledIntoView(in: app) }
            XCTAssertTrue(codeLabel.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["webAccessAddress"].exists)
            // Read the digits from the label (it may also carry the row title).
            let text = codeLabel.label.isEmpty ? (codeLabel.value as? String ?? "") : codeLabel.label
            return try XCTUnwrap(text.firstMatch(of: /\d{4}/).map { String($0.output) }, "code label was \"\(text)\"")
        }

        let session = URLSession(configuration: .ephemeral)
        let base = URL(string: "http://127.0.0.1:8080")!

        let (_, locked) = try await session.data(from: base.appendingPathComponent("api/health"))
        XCTAssertEqual((locked as? HTTPURLResponse)?.statusCode, 401)

        var wrong = URLRequest(url: base.appendingPathComponent("login"))
        wrong.httpMethod = "POST"
        wrong.httpBody = Data("code=\(code == "0000" ? "1111" : "0000")".utf8)
        let (_, wrongResponse) = try await session.data(for: wrong)
        XCTAssertEqual((wrongResponse as? HTTPURLResponse)?.statusCode, 401)

        var login = URLRequest(url: base.appendingPathComponent("login"))
        login.httpMethod = "POST"
        login.httpBody = Data("code=\(code)".utf8)
        let (page, _) = try await session.data(for: login) // follows the redirect to the web app
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("<div id=\"root\">"))

        let (health, healthResponse) = try await session.data(from: base.appendingPathComponent("api/health"))
        XCTAssertEqual((healthResponse as? HTTPURLResponse)?.statusCode, 200)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: health) as? [String: Any])
        XCTAssertEqual(body["host"] as? String, "iphone")

        await MainActor.run {
            let toggle = app.switches["webAccessToggle"]
            toggle.scrolledIntoView(in: app, up: false, maxSwipes: 4)
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            XCTAssertFalse(app.staticTexts["webAccessCode"].waitForExistence(timeout: 2))
        }
    }
}
