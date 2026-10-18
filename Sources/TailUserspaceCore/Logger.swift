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
    private var _useStderr: Bool = false

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

    public var useStderr: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _useStderr
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _useStderr = newValue
        }
    }

    public init() {}

    private func logLine(_ prefix: String, _ message: String) {
        let line = "\(prefix) \(message)"
        if useStderr {
            if let data = (line + "\n").data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        } else {
            print(line)
        }
    }

    public func info(_ message: @autoclosure () -> String) {
        if level >= .verbose {
            logLine("[INFO]", message())
        }
    }

    public func debug(_ message: @autoclosure () -> String) {
        if level >= .debug {
            logLine("[DEBUG]", message())
        }
    }

    public func trace(_ message: @autoclosure () -> String) {
        if level >= .debug {
            logLine("[TRACE]", message())
        }
    }
}
