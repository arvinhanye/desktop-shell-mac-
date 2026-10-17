import Foundation

struct ConfigStore {
    let supportDir: URL

    func load() throws -> AppConfig {
        let fileManager = FileManager.default
        let configURL = supportDir.appendingPathComponent("config.json")
        if !fileManager.fileExists(atPath: configURL.path) {
            try fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(AppConfig.example).write(to: configURL, options: .atomic)
            return AppConfig.example
        }

        // Decode before sanitizing, and never rewrite an existing configuration.
        var config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: configURL))
        config.projects = config.projects.filter { project in
            guard isValidID(project.id) else {
                NSLog("忽略配置中 id 非法的项目：%@", project.id)
                return false
            }
            return true
        }
        config.apps = config.apps.filter { app in
            guard isValidID(app.id) else {
                NSLog("忽略配置中 id 非法的应用：%@", app.id)
                return false
            }
            return true
        }
        config.greetings = config.greetings.filter { (0...23).contains($0.from) }
            .sorted { $0.from < $1.from }
        return config
    }
}
