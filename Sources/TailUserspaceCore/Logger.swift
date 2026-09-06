import Foundation

public enum VerbosityLevel: Int, Comparable, Sendable {
    case normal = 0
    case verbose = 1  // -v / --verbose
    case debug = 2    // -vv / --debug

    public static func < (lhs: VerbosityLevel, rhs: VerbosityLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public final class Logger: @unchecked Sendable {
    public static let shared = Logger()

    private let lock = NSLock()
    private var _level: VerbosityLevel = .normal

    public var level: VerbosityLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _level
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _level = newValue
        }
    }

    public init() {}

    public func info(_ message: @autoclosure () -> String) {
        if level >= .verbose {
            print("[INFO] \(message())")
        }
    }

    public func debug(_ message: @autoclosure () -> String) {
        if level >= .debug {
            print("[DEBUG] \(message())")
        }
    }

    public func trace(_ message: @autoclosure () -> String) {
        if level >= .debug {
            print("[TRACE] \(message())")
        }
    }
}
