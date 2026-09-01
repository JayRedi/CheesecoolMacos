import Foundation

@main
struct Phase4BSettings {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 3, let action = Action(rawValue: arguments[0]) else {
            fputs("Usage: Phase4BSettings <prepare|restore> <settings-path> <backup-path>\n", stderr)
            exit(EXIT_FAILURE)
        }

        let settingsURL = URL(fileURLWithPath: arguments[1])
        let backupURL = URL(fileURLWithPath: arguments[2])
        let fileManager = FileManager.default

        switch action {
        case .prepare:
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.copyItem(at: settingsURL, to: backupURL)
            }
            let data = try Data(contentsOf: backupURL)
            guard var settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                fputs("Settings root is not a JSON object.\n", stderr)
                exit(EXIT_FAILURE)
            }
            settings["operatingMode"] = "MANUAL"
            settings["manualDuty"] = 20
            let encoded = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try encoded.write(to: settingsURL, options: .atomic)
            print("Prepared MANUAL / 20% settings; backup=\(backupURL.path)")
        case .restore:
            guard fileManager.fileExists(atPath: backupURL.path) else {
                fputs("Backup is missing: \(backupURL.path)\n", stderr)
                exit(EXIT_FAILURE)
            }
            try fileManager.removeItem(at: settingsURL)
            try fileManager.copyItem(at: backupURL, to: settingsURL)
            print("Restored settings from \(backupURL.path)")
        }
    }

    enum Action: String {
        case prepare
        case restore
    }
}
