import Foundation

/// Result from the K-line API providing the previous trading day's close.
struct DailyReference {
    /// Previous trading day's closing price (USD/oz) — the benchmark for change calculation
    let previousClose: Double
    /// The date of that previous close (UTC)
    let date: Date
}

/// Fetches daily K-line data to obtain the previous trading day's closing price,
/// which serves as the reference for computing price change (↑/↓).
final class KLineService {

    private let baseURL = "https://quote.alltick.co/quote-b-api/batch-kline"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    /// Fetch the previous trading day's closing price.
    /// Result is also cached via Preferences.
    func fetchReference() async throws -> DailyReference {
        guard let apiKey = Preferences.shared.apiKey else {
            throw KLineError.missingAPIKey
        }

        // Build POST body
        let body: [String: Any] = [
            "trace": UUID().uuidString,
            "data": [
                "data_list": [[
                    "code": "GOLD",
                    "kline_type": 8,          // daily K-line
                    "kline_timestamp_end": 0, // latest
                    "query_kline_num": 2,     // last 2 bars
                    "adjust_type": 0
                ]]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw KLineError.invalidBody
        }

        var components = URLComponents(string: baseURL)!
        components.queryItems = [URLQueryItem(name: "token", value: apiKey)]
        guard let url = components.url else {
            throw KLineError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw KLineError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let ret = json?["ret"] as? Int, ret == 200,
              let dataDict = json?["data"] as? [String: Any],
              let klineList = dataDict["kline_list"] as? [[String: Any]],
              let first = klineList.first,
              let klineData = first["kline_data"] as? [[String: Any]],
              klineData.count >= 2 else {
            throw KLineError.invalidResponse
        }

        // [0] = yesterday (completed), [1] = today (in progress)
        let prevBar = klineData[0]
        guard let closeStr = prevBar["close_price"] as? String,
              let close = Double(closeStr),
              let tsStr = prevBar["timestamp"] as? String,
              let ts = Double(tsStr) else {
            throw KLineError.noData
        }

        let ref = DailyReference(
            previousClose: close,
            date: Date(timeIntervalSince1970: ts)
        )

        // Cache
        Preferences.shared.previousClose = close
        Preferences.shared.previousCloseDate = ref.date

        return ref
    }

    /// Return cached reference if available, without hitting the network
    func cachedReference() -> DailyReference? {
        guard let close = Preferences.shared.previousClose,
              let date = Preferences.shared.previousCloseDate else {
            return nil
        }
        return DailyReference(previousClose: close, date: date)
    }
}

// MARK: - Errors

enum KLineError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidBody
    case httpError(Int)
    case invalidResponse
    case noData

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:   return "请先配置 API Key"
        case .invalidURL:      return "无法构建 K线请求 URL"
        case .invalidBody:     return "无法构建 K线请求体"
        case .httpError(let c): return "K线 HTTP 错误 (\(c))"
        case .invalidResponse:  return "K线数据格式无效"
        case .noData:           return "K线数据为空"
        }
    }
}
