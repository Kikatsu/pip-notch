import os

/// Unified logging. Read with: log show --last 10m --predicate 'subsystem == "com.kikatsu.pip"'
enum Log {
    static let ui = Logger(subsystem: "com.kikatsu.pip", category: "ui")
    static let events = Logger(subsystem: "com.kikatsu.pip", category: "events")
}
