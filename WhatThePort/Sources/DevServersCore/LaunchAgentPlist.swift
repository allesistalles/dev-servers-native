import Foundation

/// The fields we need from a launchd plist. XML and binary plists both go through Foundation.
public enum LaunchAgentPlist {
    public static func parse(_ data: Data, path: String = "", loaded: Bool = false) -> LaunchAgentRecord? {
        guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = raw as? [String: Any],
              let label = dict["Label"] as? String,
              !label.isEmpty else { return nil }

        let arguments = stringArray(dict["ProgramArguments"])
        let program = (dict["Program"] as? String) ?? arguments.first ?? ""
        let disabled = dict["Disabled"] as? Bool ?? false
        return LaunchAgentRecord(
            label: label,
            plistPath: path,
            program: program,
            arguments: arguments,
            disabled: disabled,
            loaded: loaded
        )
    }

    private static func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
    }
}
