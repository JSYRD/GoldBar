import Foundation

/// UserDefaults-backed preferences for GoldBar
final class Preferences {

    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let apiKey = "apiKey"
        static let exchangeRateMode = "exchangeRateMode" // "auto" or "manual"
        static let manualExchangeRate = "manualExchangeRate"
        static let lastExchangeRate = "lastExchangeRate"
        static let lastExchangeRateUpdate = "lastExchangeRateUpdate"
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let dataSourceMode = "dataSourceMode" // "http" or "websocket"
        static let previousClose = "previousClose"
        static let previousCloseDate = "previousCloseDate"
        static let colorScheme = "colorScheme" // "western" (green↑/red↓) or "chinese" (red↑/green↓)
        static let fontSize = "fontSize"
        static let baselineOffset = "baselineOffset"
        static let httpServerEnabled = "httpServerEnabled"
        static let httpServerPort = "httpServerPort"
    }

    // MARK: - Default values
    static let defaultExchangeRate: Double = 6.79
    static let defaultRefreshInterval: TimeInterval = 15.0
    static let minFontSize: Double = 8.0
    static let maxFontSize: Double = 18.0
    static let defaultFontSize: Double = 11.0
    static let minBaselineOffset: Double = -4.0
    static let maxBaselineOffset: Double = 4.0
    static let defaultBaselineOffset: Double = -0.5

    /// AllTick API key (token). Returns nil if not yet configured.
    var apiKey: String? {
        get {
            let val = defaults.string(forKey: Key.apiKey)
            return (val?.isEmpty == false) ? val : nil
        }
        set { defaults.set(newValue, forKey: Key.apiKey) }
    }

    /// Color scheme for price change: "western" = green↑/red↓, "chinese" = red↑/green↓
    var colorScheme: String {
        get { defaults.string(forKey: Key.colorScheme) ?? "western" }
        set { defaults.set(newValue, forKey: Key.colorScheme) }
    }

    /// Status bar font size (pt). Integer, 8…18.
    var fontSize: Double {
        get {
            let raw = defaults.double(forKey: Key.fontSize)
            // 0.0 means never set (min valid value is 8.0)
            return raw == 0 ? Self.defaultFontSize
                : min(max(raw, Self.minFontSize), Self.maxFontSize)
        }
        set { defaults.set(newValue, forKey: Key.fontSize) }
    }

    /// Baseline offset (pt). Multiple of 0.5, -4.0…+4.0.
    var baselineOffset: Double {
        get {
            guard defaults.object(forKey: Key.baselineOffset) != nil else {
                return Self.defaultBaselineOffset
            }
            let raw = defaults.double(forKey: Key.baselineOffset)
            return min(max(raw, Self.minBaselineOffset), Self.maxBaselineOffset)
        }
        set { defaults.set(newValue, forKey: Key.baselineOffset) }
    }

    /// Whether the user has configured an API key
    var hasAPIKey: Bool { apiKey != nil }

    /// Previous trading day's closing price (USD/oz) — benchmark for change calculation
    var previousClose: Double? {
        get {
            let val = defaults.double(forKey: Key.previousClose)
            return val > 0 ? val : nil
        }
        set { defaults.set(newValue ?? 0, forKey: Key.previousClose) }
    }

    /// Date of the cached previous close
    var previousCloseDate: Date? {
        get { defaults.object(forKey: Key.previousCloseDate) as? Date }
        set { defaults.set(newValue, forKey: Key.previousCloseDate) }
    }

    /// Exchange rate mode: "auto" fetches from API, "manual" uses user-provided value
    var exchangeRateMode: String {
        get { defaults.string(forKey: Key.exchangeRateMode) ?? "auto" }
        set { defaults.set(newValue, forKey: Key.exchangeRateMode) }
    }

    /// Manually configured USD/CNY exchange rate
    var manualExchangeRate: Double {
        get {
            let val = defaults.double(forKey: Key.manualExchangeRate)
            return val > 0 ? val : Self.defaultExchangeRate
        }
        set { defaults.set(newValue, forKey: Key.manualExchangeRate) }
    }

    /// Cached exchange rate from the last successful auto-fetch
    var lastExchangeRate: Double? {
        get {
            let val = defaults.double(forKey: Key.lastExchangeRate)
            return val > 0 ? val : nil
        }
        set {
            if let v = newValue {
                defaults.set(v, forKey: Key.lastExchangeRate)
                defaults.set(Date(), forKey: Key.lastExchangeRateUpdate)
            }
        }
    }

    /// Timestamp of the last successful exchange rate fetch
    var lastExchangeRateUpdate: Date? {
        defaults.object(forKey: Key.lastExchangeRateUpdate) as? Date
    }

    /// Refresh interval in seconds (minimum 10s to respect API rate limits)
    var refreshInterval: TimeInterval {
        get {
            let val = defaults.double(forKey: Key.refreshIntervalSeconds)
            return val >= 10 ? val : Self.defaultRefreshInterval
        }
        set {
            defaults.set(max(10, newValue), forKey: Key.refreshIntervalSeconds)
        }
    }

    /// Data source mode: "http" for REST polling, "websocket" for real-time push
    var dataSourceMode: String {
        get { defaults.string(forKey: Key.dataSourceMode) ?? "http" }
        set { defaults.set(newValue, forKey: Key.dataSourceMode) }
    }

    /// Whether the local HTTP status server is enabled
    var httpServerEnabled: Bool {
        get { defaults.bool(forKey: Key.httpServerEnabled) }
        set { defaults.set(newValue, forKey: Key.httpServerEnabled) }
    }

    /// Port for the local HTTP status server (1–65535, default 9188)
    var httpServerPort: Int {
        get {
            let val = defaults.integer(forKey: Key.httpServerPort)
            return (1...65535).contains(val) ? val : 9188
        }
        set { defaults.set(min(max(newValue, 1), 65535), forKey: Key.httpServerPort) }
    }

    /// Returns the effective exchange rate: manual if in manual mode,
    /// cached auto-rate if available, or the default fallback
    func effectiveExchangeRate() -> Double {
        if exchangeRateMode == "manual" {
            return manualExchangeRate
        }
        return lastExchangeRate ?? Self.defaultExchangeRate
    }
}
