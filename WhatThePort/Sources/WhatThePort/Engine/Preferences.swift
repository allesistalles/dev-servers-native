import Foundation

/// UserDefaults keys and defaults for every setting. Views bind with
/// `@AppStorage(Preferences.x)`, the engine reads through `Preferences.value`.
enum Preferences {
    // General
    static let language = "general.language"
    static let iconStyle = "general.iconStyle"
    static let hotkey = "general.hotkey"
    static let scanInterval = "general.scanInterval"

    enum IconStyle: String, CaseIterable {
        case colon, colonCount, count
        var label: String {
            switch self {
            case .colon: return "Colon"
            case .colonCount: return "Colon + count"
            case .count: return "Count"
            }
        }
    }

    static let defaultProtected = ["postgres", "redis-server", "mongod", "mysqld", "mysql"]

    static func register() {
        UserDefaults.standard.register(defaults: [
            language: InterfaceLanguage.system.rawValue,
            iconStyle: IconStyle.colonCount.rawValue,
            hotkey: true,
            scanInterval: 2.0,
        ])
    }

    static var defaults: UserDefaults { .standard }
}
