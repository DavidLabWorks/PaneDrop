import Foundation

extension Notification.Name {
    static let paneDropLanguageDidChange = Notification.Name(
        "PaneDropLanguageDidChange"
    )
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    static var defaultLanguage: AppLanguage {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        return preferredLanguage.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum L10n {
    private static let localizedBundles: [AppLanguage: Bundle] = {
        Dictionary(
            uniqueKeysWithValues: AppLanguage.allCases.map { language in
                let bundle = Bundle.main.path(
                    forResource: language.rawValue,
                    ofType: "lproj"
                ).flatMap(Bundle.init(path:)) ?? .main
                return (language, bundle)
            }
        )
    }()

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let language = preferences.language
        let localizedBundle = localizedBundles[language] ?? .main
        let format = localizedBundle.localizedString(
            forKey: key,
            value: key,
            table: nil
        )

        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }

    static func duplicateSuffix(number: Int) -> String {
        if number == 1 {
            return string("template.copy_suffix")
        }
        return string("template.numbered_copy_suffix", number)
    }
}
