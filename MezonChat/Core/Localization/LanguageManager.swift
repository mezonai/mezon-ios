import Foundation

enum AppLanguage: String, CaseIterable {
    case english    = "en"
    case vietnamese = "vi"

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }
}

final class LanguageManager {

    static let shared = LanguageManager()

    static let didChangeNotification = Notification.Name("AppLanguageDidChange")

    private static let userDefaultsKey = "mezon.mobile.selectedLanguage"

    private(set) var current: AppLanguage

    private init() {
        if let stored = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let language = AppLanguage(rawValue: stored) {
            current = language
        } else {
            current = Self.defaultLanguageForSystem()
        }
    }

    private static func defaultLanguageForSystem() -> AppLanguage {
        let preferredLanguage = Locale.preferredLanguages.first?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased() ?? ""
        let languageCode = preferredLanguage.split(separator: "-").first.map(String.init)
        return languageCode == AppLanguage.vietnamese.rawValue ? .vietnamese : .english
    }

    func set(_ language: AppLanguage) {
        guard language != current else { return }
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.userDefaultsKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: language)
        }
    }

    func string(for key: String) -> String {
        L10n.translations[current]?[key] ?? L10n.translations[.english]?[key] ?? key
    }
}

func L(_ key: String) -> String {
    LanguageManager.shared.string(for: key)
}

func L(_ key: String, _ args: CVarArg...) -> String {
    let format = L(key)
    return String(format: format, arguments: args)
}
