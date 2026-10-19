import Foundation

struct AppConfig: Codable, Equatable {
    var user: User? = nil
    var background: Background
    var character: Character
    var greetings: [Greeting]
    var projects: [Project]
    var apps: [App]

    struct User: Codable, Equatable {
        var name: String?
    }

    struct Background: Codable, Equatable {
        var video: String
    }

    struct Character: Codable, Equatable {
        var name: String
        var motto: String? = nil
    }

    struct Greeting: Codable, Equatable {
        var from: Int
        var title: String
        var wish: String
    }

    struct Project: Codable, Equatable {
        var id: String
        var name: String
        var path: String
        var tags: [String]?
        var apps: [String]?
        var remindersList: String? = nil
    }

    struct App: Codable, Equatable {
        var id: String
        var name: String
        var bundleId: String
    }

    static let example = AppConfig(
        user: User(name: "Arvin"),
        background: Background(video: "video/aemeath.mp4"),
        character: Character(name: "爱弥斯", motto: "愿星光一直落在你走的路上"),
        greetings: [
            Greeting(from: 0, title: "深夜了", wish: "时辰已晚，且捻熄灯盏，良宵安枕"),
            Greeting(from: 6, title: "早上好", wish: "晨光熹微，愿您涤尽尘扰，理裳启新日"),
            Greeting(from: 12, title: "下午好", wish: "愿清风伴您今日，时刻皆有阳光满心"),
            Greeting(from: 18, title: "傍晚了", wish: "且舒怀抱，自在一刻尽欢愉"),
            Greeting(from: 20, title: "晚上好", wish: "且舒怀抱，自在一刻尽欢愉"),
            Greeting(from: 21, title: "晚上好", wish: "时辰已晚，且捻熄灯盏，良宵安枕"),
            Greeting(from: 23, title: "深夜了", wish: "时辰已晚，且捻熄灯盏，良宵安枕")
        ],
        projects: [Project(
            id: "desktop-shell", name: "DesktopShell", path: "~/Desktop/desktop-shell",
            tags: ["dev"], apps: ["cursor"]
        )],
        apps: [
            App(id: "cursor", name: "Cursor", bundleId: "com.todesktop.230313mzl4w4u92"),
            App(id: "safari", name: "Safari", bundleId: "com.apple.Safari")
        ]
    )
}

func isValidID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.allSatisfy { byte in
        (65...90).contains(byte) || (97...122).contains(byte)
            || (48...57).contains(byte) || byte == 95 || byte == 45
    }
}
