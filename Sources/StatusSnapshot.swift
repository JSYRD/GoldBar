import Foundation

/// Thread-safe snapshot of current app state, updated by MenuBarController,
/// read by the HTTP server.
final class StatusSnapshot: @unchecked Sendable {

    static let shared = StatusSnapshot()

    private let lock = NSLock()

    private var _priceUSD: Double?
    private var _priceRMB: Double?
    private var _changePercent: Double?
    private var _previousClose: Double?
    private var _exchangeRate: Double?
    private var _exchangeRateMode: String?
    private var _dataSourceMode: String?
    private var _connectionState: String?
    private var _lastUpdate: Date?
    private var _lastError: String?

    // MARK: - Setters (called from main thread)

    func update(priceUSD: Double, priceRMB: Double, changePercent: Double?,
                previousClose: Double?, exchangeRate: Double, exchangeRateMode: String,
                dataSourceMode: String, connectionState: String) {
        lock.lock()
        _priceUSD = priceUSD
        _priceRMB = priceRMB
        _changePercent = changePercent
        _previousClose = previousClose
        _exchangeRate = exchangeRate
        _exchangeRateMode = exchangeRateMode
        _dataSourceMode = dataSourceMode
        _connectionState = connectionState
        _lastUpdate = Date()
        _lastError = nil
        lock.unlock()
    }

    func updateError(_ error: String) {
        lock.lock()
        _lastError = error
        _lastUpdate = Date()
        lock.unlock()
    }

    // MARK: - Snapshot (thread-safe read)

    func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        var gold: [String: Any] = [:]
        if let usd = _priceUSD {
            gold["price_usd_oz"] = (usd * 100).rounded() / 100
        }
        if let rmb = _priceRMB {
            gold["price_rmb_g"] = (rmb * 100).rounded() / 100
        }
        if let chg = _changePercent {
            gold["change_percent"] = (chg * 100).rounded() / 100
            gold["change_direction"] = chg >= 0 ? "up" : "down"
        }
        if let prev = _previousClose {
            gold["previous_close"] = (prev * 100).rounded() / 100
        }

        var rate: [String: Any] = [:]
        if let er = _exchangeRate {
            rate["usd_cny"] = (er * 10000).rounded() / 10000
        }
        rate["mode"] = _exchangeRateMode ?? "auto"

        var conn: [String: Any] = [
            "mode": _dataSourceMode ?? "http",
            "state": _connectionState ?? "disconnected"
        ]
        if let ts = _lastUpdate {
            conn["last_update"] = ISO8601DateFormatter().string(from: ts)
        }
        if let err = _lastError {
            conn["error"] = err
        }

        return [
            "gold": gold,
            "exchange_rate": rate,
            "connection": conn
        ]
    }
}
