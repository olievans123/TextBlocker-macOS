import Foundation

enum DependencyLocator {
    private static let commonPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    static func findExecutable(named name: String) -> String? {
        for directory in searchPaths() {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static func isInstalled(_ name: String) -> Bool {
        findExecutable(named: name) != nil
    }

    private static func searchPaths() -> [String] {
        var paths: [String] = []
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        paths.append(contentsOf: envPath.split(separator: ":").map(String.init))

        for path in commonPaths where !paths.contains(path) {
            paths.append(path)
        }

        return paths
    }
}
