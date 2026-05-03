import Foundation

public enum LoginItemService {
    public static let label = "cn.local.voiceinput.loginitem"

    private static var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    private static var launchAgentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(label).plist")
    }

    public static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    public static func setEnabled(_ enabled: Bool, executablePath: String) throws {
        if enabled {
            try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            let data = try launchAgentPlist(executablePath: executablePath)
            try data.write(to: launchAgentURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    public static func launchAgentPlist(executablePath: String) throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}
