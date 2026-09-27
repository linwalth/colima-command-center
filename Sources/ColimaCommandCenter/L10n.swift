import Foundation

enum L10n {
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let template = NSLocalizedString(key, comment: "")
        if args.isEmpty { return template }
        return String(format: template, locale: Locale.current, arguments: args)
    }
}
