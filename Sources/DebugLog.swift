import Foundation

/// Simple debug logger — prints to stdout only in DEBUG builds.
/// Usage: `DebugLog.info("price update", ["price": "4098.11", "rmb": "894.5"])`
enum DebugLog {

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func info(_ event: String, _ details: [String: Any] = [:]) {
        #if DEBUG
        let ts = formatter.string(from: Date())
        var parts = "[\(ts)] [GoldBar] \(event)"
        if details.isNotEmpty {
            let kv = details.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            parts += " | \(kv)"
        }
        print(parts)
        fflush(stdout)
        #endif
    }

    static func error(_ event: String, _ details: [String: Any] = [:]) {
        #if DEBUG
        let ts = formatter.string(from: Date())
        var parts = "[\(ts)] [GoldBar] ❌ \(event)"
        if details.isNotEmpty {
            let kv = details.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            parts += " | \(kv)"
        }
        print(parts)
        fflush(stdout)
        #endif
    }
}

private extension Dictionary {
    var isNotEmpty: Bool { !isEmpty }
}
