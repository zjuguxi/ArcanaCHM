import XCTest
@testable import ArcanaCHM

// Regression tests for the launch crash caused by SwiftPM's
// resource_bundle_accessor looking for the resource bundle at
// Bundle.main.bundleURL (the .app root) while packaging placed it in
// Contents/Resources/. The fix unpacks .lproj folders into
// Contents/Resources/ and resolves localizations from Bundle.main when
// running inside a packaged .app.
@MainActor
final class LocalizationPackagingTests: XCTestCase {

    private func makeAppShapedBundle(lproj code: String, value: String) throws -> Bundle {
        let appDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeApp-\(UUID().uuidString).app", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: appDir) }

        let lproj = appDir.appendingPathComponent("\(code).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        let strings = "\"language_system\" = \"\(value)\";"
        try strings.write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(Bundle(url: appDir))
        return Bundle(url: appDir)!
    }

    private func isInside(_ child: URL, _ parent: URL) -> Bool {
        let c = child.standardizedFileURL.path
        let p = parent.standardizedFileURL.path
        return c == p || c.hasPrefix(p + "/")
    }

    func testResolveBundle_usesMainBundleInAppLayout() throws {
        let appBundle = try makeAppShapedBundle(lproj: "en", value: "Follow System")
        let moduleBundle = Bundle.module

        let resolved = LocalizationService.resolveLocalizationBundle(
            mainBundle: appBundle,
            moduleBundle: moduleBundle,
            languageCode: "en"
        )

        XCTAssertTrue(isInside(resolved.bundleURL, appBundle.bundleURL),
                      "In a packaged .app the localizations live in Contents/Resources/*.lproj and must be resolved from Bundle.main, not Bundle.module. Resolving via Bundle.module triggers fatalError because the SPM resource bundle is absent from the .app root.")
        XCTAssertFalse(isInside(resolved.bundleURL, moduleBundle.bundleURL),
                       "Resolved bundle must not fall through to the SPM module bundle in a packaged .app.")
    }

    func testResolveBundle_appLayoutResolvesLocalizedStrings() throws {
        let appBundle = try makeAppShapedBundle(lproj: "zh-hans", value: "跟随系统")

        let resolved = LocalizationService.resolveLocalizationBundle(
            mainBundle: appBundle,
            moduleBundle: Bundle.module,
            languageCode: "zh-hans"
        )

        XCTAssertEqual(
            NSLocalizedString("language_system", bundle: resolved, comment: ""),
            "跟随系统"
        )
    }

    func testResolveBundle_nonAppFallsBackToModuleBundle() throws {
        let nonAppDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: nonAppDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: nonAppDir) }
        let nonAppBundle = Bundle(url: nonAppDir)!
        let moduleBundle = Bundle.module

        let resolved = LocalizationService.resolveLocalizationBundle(
            mainBundle: nonAppBundle,
            moduleBundle: moduleBundle,
            languageCode: "en"
        )

        XCTAssertTrue(isInside(resolved.bundleURL, moduleBundle.bundleURL),
                      "Outside a packaged .app (swift run / swift test) localizations must come from Bundle.module.")
        XCTAssertFalse(isInside(resolved.bundleURL, nonAppBundle.bundleURL),
                       "Non-.app main bundle must not be used as the localization source.")
    }
}

