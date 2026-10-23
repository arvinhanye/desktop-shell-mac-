import Foundation

struct ConfigStore {
    let supportDir: URL

    func loadUnfiltered() throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: supportDir.appendingPathComponent("config.json")))
    }

    func save(_ config: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: supportDir.appendingPathComponent("config.json"), options: .atomic)
    }

    // Merge only changed project fields into the latest JSON, retaining extension keys
    // and entries excluded from the public configuration. A concurrent typed edit aborts.
    func saveProjects(_ updated: AppConfig, replacing previous: AppConfig) throws {
        let url = supportDir.appendingPathComponent("config.json")
        let data = try Data(contentsOf: url)
        guard try JSONDecoder().decode(AppConfig.self, from: data) == previous,
              var raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = raw["projects"] as? [[String: Any]] else { throw BridgeError.failed }
        let encoder = JSONEncoder()
        var available = Array(previous.projects.indices)
        raw["projects"] = try updated.projects.map { project -> [String: Any] in
            let new = try JSONSerialization.jsonObject(with: encoder.encode(project)) as! [String: Any]
            let match = available.first { previous.projects[$0] == project }
                ?? available.first { previous.projects[$0].id == project.id }
            guard let index = match else { return new }
            available.removeAll { $0 == index }
            let old = try JSONSerialization.jsonObject(with: encoder.encode(previous.projects[index])) as! [String: Any]
            var merged = rows[index]
            for key in Set(old.keys).union(new.keys) {
                let a = old[key] as? NSObject, b = new[key] as? NSObject
                if a != b { merged[key] = new[key] }
            }
            return merged
        }
        if updated.projectOrder != previous.projectOrder { raw["projectOrder"] = updated.projectOrder }
        try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: url, options: .atomic)
    }

    func load() throws -> AppConfig {
        let fileManager = FileManager.default
        let configURL = supportDir.appendingPathComponent("config.json")
        if !fileManager.fileExists(atPath: configURL.path) {
            try fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try save(AppConfig.example)
            return AppConfig.example
        }

        // Decode before sanitizing, and never rewrite an existing configuration.
        let config = Self.filtered(try loadUnfiltered())
        if HotKey.resolve(config.terminal?.hotkey).usedDefaultBecauseInvalid {
            Log.error("terminal hotkey invalid, using default")
        }
        return config
    }

    static func filtered(_ input: AppConfig) -> AppConfig {
        var config = input
        config.projects = config.projects.filter { project in
            guard isValidID(project.id) else {
                Log.error("忽略配置中 id 非法的项目：\(project.id)")
                return false
            }
            return true
        }
        config.greetings = config.greetings.filter { (0...23).contains($0.from) }
            .sorted { $0.from < $1.from }
        return config
    }
}
