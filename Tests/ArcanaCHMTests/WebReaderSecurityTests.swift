import WebKit
import XCTest
@testable import ArcanaCHM

@MainActor
final class WebReaderSecurityTests: XCTestCase {
    func testPackagedAppAllowsWebContentProcessToLaunch() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlementsURL = repositoryRoot
            .appendingPathComponent("Resources/ArcanaCHM.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["com.apple.security.network.client"] as? Bool, true)
    }

    func testContentBlockerRulesCompile() {
        let compiled = expectation(description: "WebKit content blocker rules compile")
        var compilationError: Error?
        var hasRuleList = false
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcanaCHM-rule-store-\(UUID().uuidString)", isDirectory: true)
        guard let store = WKContentRuleListStore(url: storeURL) else {
            return XCTFail("Could not create an isolated content rule list store")
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: storeURL) }

        store.compileContentRuleList(
            forIdentifier: "ArcanaCHMTests.\(UUID().uuidString)",
            encodedContentRuleList: WebReaderView.Coordinator.contentBlockerRules
        ) { ruleList, error in
            hasRuleList = ruleList != nil
            compilationError = error
            compiled.fulfill()
        }

        wait(for: [compiled], timeout: 10)
        XCTAssertNil(compilationError)
        XCTAssertTrue(hasRuleList)
    }
}
