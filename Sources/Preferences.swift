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
    }

    // MARK: - Default values
    static let defaultAPIKey = "YOUR_API_KEY"
    static let defaultExchangeRate: Double = 6.79
    static let defaultRefreshInterval: TimeInterval = 15.0

    /// AllTick API key (token)
    var apiKey: String {
        get { defaults.string(forKey: Key.apiKey) ?? Self.defaultAPIKey }
        set { defaults.set(newValue, forKey: Key.apiKey) }
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

    /// Returns the effective exchange rate: manual if in manual mode,
    /// cached auto-rate if available, or the default fallback
    func effectiveExchangeRate() -> Double {
        if exchangeRateMode == "manual" {
            return manualExchangeRate
        }
        return lastExchangeRate ?? Self.defaultExchangeRate
    }
}
