import Foundation

/// Integration tests that hit real APIs. Only run with `--integration` flag.
func runAPITests(apiKey: String) async {

    await runSuite("API: Gold price (trade-tick)") {
        guard let url = buildTradeTickURL(apiKey: apiKey) else {
            print("  ⚠️  Skipped: could not build URL")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            assertEqual(code, 200, "HTTP 200")

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ret = json["ret"] as? Int {
                assertEqual(ret, 200, "API ret=200")

                if let tickData = json["data"] as? [String: Any],
                   let tickList = tickData["tick_list"] as? [[String: Any]],
                   let tick = tickList.first,
                   let priceStr = tick["price"] as? String,
                   let price = Double(priceStr) {
                    assertTrue(price > 1000, "GOLD > $1000/oz (got \(price))")
                    assertTrue(price < 10000, "GOLD < $10000/oz (got \(price))")
                    print("  ✅ GOLD = $\(price)/oz")
                } else {
                    assertTrue(false, "could not parse price from response")
                }
            } else {
                assertTrue(false, "invalid JSON response")
            }
        } catch {
            assertTrue(false, "network error: \(error.localizedDescription)")
        }
    }

    await runSuite("API: K-line daily reference") {
        let urlStr = "https://quote.alltick.co/quote-b-api/batch-kline?token=\(apiKey)"
        guard let url = URL(string: urlStr) else {
            print("  ⚠️  Skipped: could not build URL")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "trace": "test-kline",
            "data": [
                "data_list": [[
                    "code": "GOLD",
                    "kline_type": 8,
                    "kline_timestamp_end": 0,
                    "query_kline_num": 2,
                    "adjust_type": 0
                ]]
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            assertEqual(code, 200, "HTTP 200")

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ret = json["ret"] as? Int {
                assertEqual(ret, 200, "API ret=200")

                if let dataDict = json["data"] as? [String: Any],
                   let klineList = dataDict["kline_list"] as? [[String: Any]],
                   let first = klineList.first,
                   let bars = first["kline_data"] as? [[String: Any]],
                   bars.count >= 2 {
                    let prevClose = bars[0]["close_price"] as? String ?? "?"
                    let currClose = bars[1]["close_price"] as? String ?? "?"
                    assertTrue(Double(prevClose) != nil, "prev close is a number")
                    assertTrue(Double(currClose) != nil, "curr close is a number")
                    print("  ✅ prev close=$\(prevClose)  curr close=$\(currClose)")
                } else {
                    assertTrue(false, "could not parse K-line data")
                }
            }
        } catch {
            assertTrue(false, "network error: \(error.localizedDescription)")
        }
    }

    await runSuite("API: Exchange rate") {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            assertEqual(code, 200, "HTTP 200")

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? String {
                assertEqual(result, "success", "result=success")
                if let rates = json["rates"] as? [String: Double],
                   let cny = rates["CNY"] {
                    assertTrue(cny > 5 && cny < 10, "CNY rate reasonable (5-10): \(cny)")
                    print("  ✅ USD/CNY = \(cny)")
                } else {
                    assertTrue(false, "CNY rate not found")
                }
            }
        } catch {
            assertTrue(false, "network error: \(error.localizedDescription)")
        }
    }
}

// Duplicated from GoldPriceService to keep tests independent
private func buildTradeTickURL(apiKey: String) -> URL? {
    let queryData: [String: Any] = [
        "trace": "test-tick",
        "data": ["symbol_list": [["code": "GOLD"]]]
    ]
    guard let queryJSON = String(data: (try! JSONSerialization.data(withJSONObject: queryData)),
                                  encoding: .utf8) else { return nil }
    var comps = URLComponents(string: "https://quote.alltick.co/quote-b-api/trade-tick")!
    comps.queryItems = [
        URLQueryItem(name: "token", value: apiKey),
        URLQueryItem(name: "query", value: queryJSON)
    ]
    return comps.url
}
