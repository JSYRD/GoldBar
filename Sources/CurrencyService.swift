import Foundation

/// Fetches USD/CNY exchange rate from a free API
final class CurrencyService {

    /// Cache duration: 1 hour (exchange rates don't change that fast)
    private static let cacheDuration: TimeInterval = 3600

    private let freeAPIURL = "https://open.er-api.com/v6/latest/USD"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    /// Get the current USD/CNY exchange rate.
    /// Uses cached value if it's less than 1 hour old.
    func fetchRate(forceRefresh: Bool = false) async throws -> Double {
        // Return cached value if fresh
        if !forceRefresh,
           let lastUpdate = Preferences.shared.lastExchangeRateUpdate,
           Date().timeIntervalSince(lastUpdate) < Self.cacheDuration,
           let cachedRate = Preferences.shared.lastExchangeRate {
            return cachedRate
        }

        // Fetch from free API
        guard let url = URL(string: freeAPIURL) else {
            throw CurrencyError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CurrencyError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String,
              result == "success",
              let rates = json["rates"] as? [String: Double],
              let cnyRate = rates["CNY"] else {
            throw CurrencyError.invalidResponse
        }

        // Cache the result
        Preferences.shared.lastExchangeRate = cnyRate
        return cnyRate
    }
}

// MARK: - Errors
enum CurrencyError: Error, LocalizedError {
    case invalidURL
    case httpError(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:      return "无法构建汇率 API URL"
        case .httpError(let c): return "汇率 API HTTP 错误 (\(c))"
        case .invalidResponse:  return "汇率 API 返回了无效数据"
        }
    }
}
