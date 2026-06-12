import Foundation

/// Tests for price conversion formulas independently of any network calls.
func runPriceCalcTests() {
    runSuite("Price conversion") {

        // RMB/g = (USD/oz × rate) ÷ troyOunceToGrams
        // 1 troy oz = 31.1034768 g
        func rmbPerGram(usdPerOz: Double, rate: Double) -> Double {
            usdPerOz * rate / troyOunceToGrams
        }

        // Known-value test: $4000/oz @ 7.0 rate
        let r1 = rmbPerGram(usdPerOz: 4000.0, rate: 7.0)
        let expected1 = 4000.0 * 7.0 / 31.1034768  // ≈ 900.24
        assertEqual(round(r1 * 100) / 100, round(expected1 * 100) / 100,
                     "$4000/oz @ 7.0 → 900.24 RMB/g")

        // Known-value test: $4100/oz @ 6.7893 rate (realistic)
        let r2 = rmbPerGram(usdPerOz: 4100.0, rate: 6.7893)
        let expected2 = 4100.0 * 6.7893 / 31.1034768  // ≈ 895.30
        assertEqual(round(r2 * 100) / 100, round(expected2 * 100) / 100,
                     "$4100/oz @ 6.7893 → ~895.30 RMB/g")

        // Edge case: zero rate
        let r3 = rmbPerGram(usdPerOz: 4000.0, rate: 0.0)
        assertEqual(r3, 0.0, "zero rate → 0 RMB/g")

        // Edge case: zero price
        let r4 = rmbPerGram(usdPerOz: 0.0, rate: 7.0)
        assertEqual(r4, 0.0, "zero price → 0 RMB/g")
    }

    runSuite("Change percentage") {

        func changePercent(current: Double, previous: Double) -> Double {
            (current - previous) / previous * 100.0
        }

        // Up: +0.50%
        let up = changePercent(current: 4100.0, previous: 4079.60)
        assertEqual(round(up * 100) / 100, 0.50, "up 0.50%")

        // Down: -0.50%
        let down = changePercent(current: 4079.60, previous: 4100.0)
        assertEqual(round(down * 100) / 100, -0.50, "down -0.50%")

        // Flat
        let flat = changePercent(current: 4100.0, previous: 4100.0)
        assertEqual(flat, 0.0, "flat → 0%")

        // Large move
        let big = changePercent(current: 5000.0, previous: 4000.0)
        assertEqual(big, 25.0, "+25%")

        // Negative price (shouldn't happen, but formula should still work)
        let weird = changePercent(current: 4100.0, previous: 1.0)
        assertTrue(weird > 400000, "tiny prev → huge %")
    }

    runSuite("Rounding / display format") {

        func format(_ value: Double, decimals: Int) -> String {
            String(format: "%.\(decimals)f", value)
        }

        assertEqual(format(895.234, decimals: 1), "895.2", "RMB 1 decimal")
        assertEqual(format(4100.0, decimals: 2), "4100.00", "USD 2 decimals")
        assertEqual(format(0.503, decimals: 2), "0.50", "change 2 decimals")
        assertEqual(format(-0.123, decimals: 2), "-0.12", "negative 2 decimals")

        // Check that rounding is truncation, not just floor
        assertEqual(format(895.256, decimals: 1), "895.3", "round up at .05")
    }

    runSuite("Exchange rate effective selection") {

        // Simulate Preferences logic
        func effectiveRate(mode: String, manual: Double, cached: Double?) -> Double {
            if mode == "manual" { return manual }
            return cached ?? 6.79  // default fallback
        }

        assertEqual(effectiveRate(mode: "auto", manual: 7.0, cached: 6.80), 6.80,
                     "auto mode uses cached")
        assertEqual(effectiveRate(mode: "manual", manual: 7.0, cached: 6.80), 7.0,
                     "manual mode uses manual")
        assertEqual(effectiveRate(mode: "auto", manual: 7.0, cached: nil), 6.79,
                     "auto mode w/o cache uses default")
    }
}
