import XCTest
@testable import ArcanaCHM

final class SearchHitTests: XCTestCase {
    func testSearchHitCreation() {
        let hit = SearchHit(title: "Result", path: "page.html", snippet: "some text here")
        XCTAssertEqual(hit.title, "Result")
        XCTAssertEqual(hit.path, "page.html")
        XCTAssertEqual(hit.snippet, "some text here")
    }
}
