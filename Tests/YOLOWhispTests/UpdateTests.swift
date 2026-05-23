import XCTest
@testable import YOLOWhisp

final class UpdateTests: XCTestCase {

    private func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testUpdateCheckerConformsToProtocol() {
        let checker: UpdateChecking = GitHubUpdateChecker(session: makeMockSession())
        XCTAssertTrue(checker.canCheckForUpdates)
    }

    func testCheckForUpdatesCallsGitHubAPI() {
        let expectation = expectation(description: "API called")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.url?.path, "/repos/YOLOVibeCode/yolowhisp/releases/latest")
            expectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"tag_name":"v0.1.0","html_url":"https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.1.0"}"#
            return (response, json.data(using: .utf8)!)
        }

        let checker = GitHubUpdateChecker(currentVersion: "0.1.0", session: makeMockSession())
        checker.checkForUpdates()
        waitForExpectations(timeout: 5)
    }

    func testNewerVersionDetected() {
        let updateExpectation = expectation(description: "update available")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"tag_name":"v0.2.0","html_url":"https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.2.0"}"#
            return (response, json.data(using: .utf8)!)
        }

        let checker = GitHubUpdateChecker(currentVersion: "0.1.0", session: makeMockSession())
        checker.onUpdateAvailable = { version, url in
            XCTAssertEqual(version, "0.2.0")
            XCTAssertEqual(url.absoluteString, "https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.2.0")
            updateExpectation.fulfill()
        }
        checker.checkForUpdates()
        waitForExpectations(timeout: 5)
    }

    func testSameVersionNoUpdate() {
        let apiExpectation = expectation(description: "API called")
        MockURLProtocol.requestHandler = { request in
            apiExpectation.fulfill()
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let json = #"{"tag_name":"v0.1.0","html_url":"https://github.com/YOLOVibeCode/yolowhisp/releases/tag/v0.1.0"}"#
            return (response, json.data(using: .utf8)!)
        }

        let checker = GitHubUpdateChecker(currentVersion: "0.1.0", session: makeMockSession())
        checker.onUpdateAvailable = { _, _ in
            XCTFail("Should not report update for same version")
        }
        checker.checkForUpdates()
        waitForExpectations(timeout: 5)
        // Give a moment for any erroneous callback
        let noCallback = expectation(description: "no callback")
        noCallback.isInverted = true
        waitForExpectations(timeout: 0.5)
    }

    func testNetworkErrorHandled() {
        let apiExpectation = expectation(description: "API called")
        MockURLProtocol.requestHandler = { _ in
            apiExpectation.fulfill()
            throw URLError(.notConnectedToInternet)
        }

        let checker = GitHubUpdateChecker(currentVersion: "0.1.0", session: makeMockSession())
        checker.onUpdateAvailable = { _, _ in
            XCTFail("Should not report update on error")
        }
        checker.checkForUpdates()
        waitForExpectations(timeout: 5)
    }
}
