import Foundation
import os

/// Central logging. Replaces the scattered `print("DEBUG: ...")` calls so output
/// can be filtered in Console.app and compiled out of release builds by the OS.
enum Log {
    private static let subsystem = "com.abhay.MacNotch"

    static let window = Logger(subsystem: subsystem, category: "window")
    static let music = Logger(subsystem: subsystem, category: "music")
    static let sports = Logger(subsystem: subsystem, category: "sports")
    static let system = Logger(subsystem: subsystem, category: "system")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let obsidian = Logger(subsystem: subsystem, category: "obsidian")
}
