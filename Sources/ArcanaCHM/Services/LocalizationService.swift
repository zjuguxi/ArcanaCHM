import Foundation
import SwiftUI

@MainActor
final class LocalizationService: ObservableObject {

    static let shared = LocalizationService()

    enum Language: String, CaseIterable {
        case system = ""
        case en = "en"
        case zh = "zh-hans"

        var identifier: String? {
            switch self {
            case .system: return nil
            case .en, .zh: return rawValue
            }
        }
    }

    @Published var currentLanguage: Language {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: selectedLanguageKey)
        }
    }

    private let selectedLanguageKey = "selectedLanguage"

    private init() {
        let raw = UserDefaults.standard.string(forKey: "selectedLanguage") ?? ""
        currentLanguage = Language(rawValue: raw) ?? .system
    }

    func localizedString(_ key: String) -> String {
        NSLocalizedString(key, bundle: localizationBundle, comment: "")
    }

    private var localizationBundle: Bundle {
        let code = currentLanguage.identifier ?? preferredLanguageCode
        if Bundle.main.bundlePath.hasSuffix(".app"),
           Bundle.main.path(forResource: "en", ofType: "lproj") != nil {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
            return Bundle.main
        }
        guard let path = Bundle.module.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.module
        }
        return bundle
    }

    private var preferredLanguageCode: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") { return "zh-hans" }
        return String(preferred.prefix(2))
    }

    func label(for language: Language) -> String {
        switch language {
        case .system: return localizedString("language_system")
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

@MainActor
extension String {
    var loc: String {
        LocalizationService.shared.localizedString(self)
    }

    func loc(_ args: CVarArg...) -> String {
        let format = LocalizationService.shared.localizedString(self)
        return String(format: format, arguments: args)
    }
}
