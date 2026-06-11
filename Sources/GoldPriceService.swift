import Foundation

/// Result type for gold price fetch
struct GoldPriceResult {
    /// Price in USD per troy ounce
    let priceUSDPerOunce: Double
    /// Timestamp from the exchange
    let tickTime: Date
    /// Raw sequence number from the API
    let seq: String
}

/// Fetches the latest GOLD price from the AllTick HTTP API
final class GoldPriceService {

    private let baseURL = "https://quote.alltick.co/quote-b-api/trade-tick"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    /// Fetch the latest gold price in USD per troy ounce
    func fetchPrice() async throws -> GoldPriceResult {
        guard let apiKey = Preferences.shared.apiKey else {
            throw GoldPriceError.missingAPIKey
        }
        let trace = UUID().uuidString

        // Build query JSON
        let queryData: [String: Any] = [
            "trace": trace,
            "data": [
                "symbol_list": [
                    ["code": "GOLD"]
                ]
            ]
        ]

        guard let queryJSON = String(data: try JSONSerialization.data(withJSONObject: queryData),
                                      encoding: .utf8) else {
            throw GoldPriceError.invalidQuery
        }

        // Build URL
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "token", value: apiKey),
            URLQueryItem(name: "query", value: queryJSON)
        ]

        guard let url = components.url else {
            throw GoldPriceError.invalidURL
        }

        // Request
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GoldPriceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        // Parse
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ret = json["ret"] as? Int else {
            throw GoldPriceError.invalidResponse
        }

        if ret != 200 {
            let msg = json["msg"] as? String ?? "unknown error"
            throw GoldPriceError.apiError(code: ret, message: msg)
        }

        guard let dataDict = json["data"] as? [String: Any],
              let tickList = dataDict["tick_list"] as? [[String: Any]],
              let tick = tickList.first,
              let priceStr = tick["price"] as? String,
              let price = Double(priceStr) else {
            throw GoldPriceError.noData
        }

        // Parse tick time (milliseconds since epoch)
        let tickTime: Date
        if let tickTimeStr = tick["tick_time"] as? String,
           let tickTimeMs = Double(tickTimeStr) {
            tickTime = Date(timeIntervalSince1970: tickTimeMs / 1000.0)
        } else {
            tickTime = Date()
        }

        return GoldPriceResult(
            priceUSDPerOunce: price,
            tickTime: tickTime,
            seq: tick["seq"] as? String ?? ""
        )
    }
}

// MARK: - Errors
enum GoldPriceError: Error, LocalizedError {
    case invalidURL
    case invalidQuery
    case missingAPIKey
    case httpError(Int)
    case invalidResponse
    case apiError(code: Int, message: String)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:       return "无法构建请求 URL"
        case .invalidQuery:     return "无法构建查询参数"
        case .missingAPIKey:    return "请先配置 API Key"
        case .httpError(let c): return "HTTP 错误 (\(c))"
        case .invalidResponse:  return "服务器返回了无效数据"
        case .apiError(let c, let m): return "API 错误 (\(c)): \(m)"
        case .noData:           return "未获取到金价数据"
        }
    }
}
