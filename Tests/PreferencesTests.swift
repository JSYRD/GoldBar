import Foundation

/// Tests for Preferences (UserDefaults wrapper) behavior.
/// Uses a separate suite name to avoid polluting real preferences.
func runPreferencesTests() {

    // We're testing the Preferences class from the app directly.
    // But we need to be careful: it reads/writes real UserDefaults.
    // We'll snapshot values, run tests, then restore.
    let prefs = Preferences.shared

    // Snapshot
    let savedKey = prefs.apiKey
    let savedFontSize = prefs.fontSize
    let savedBaseline = prefs.baselineOffset
    let savedColorScheme = prefs.colorScheme
    let savedDataSource = prefs.dataSourceMode

    defer {
        // Restore
        prefs.apiKey = savedKey
        prefs.fontSize = savedFontSize
        prefs.baselineOffset = savedBaseline
        prefs.colorScheme = savedColorScheme
        prefs.dataSourceMode = savedDataSource
    }

    runSuite("Preferences: apiKey") {
        prefs.apiKey = nil
        assertTrue(prefs.apiKey == nil, "nil key → nil")
        assertFalse(prefs.hasAPIKey, "nil → hasAPIKey=false")

        prefs.apiKey = "test-key-12345"
        assertEqual(prefs.apiKey!, "test-key-12345", "set/get key")
        assertTrue(prefs.hasAPIKey, "has key → true")

        prefs.apiKey = ""  // empty string → nil
        assertTrue(prefs.apiKey == nil, "empty string → nil")
    }

    runSuite("Preferences: fontSize") {
        prefs.fontSize = 14.0
        assertEqual(prefs.fontSize, 14.0, "set/get font size 14")

        prefs.fontSize = 5.0   // below min → Preferences clamps to min (8)
        assertEqual(prefs.fontSize, 8.0, "clamp below min to 8")

        prefs.fontSize = 25.0  // above max → clamped to 18
        assertEqual(prefs.fontSize, 18.0, "clamp above max to 18")
    }

    runSuite("Preferences: baselineOffset") {
        prefs.baselineOffset = -2.0
        assertEqual(prefs.baselineOffset, -2.0, "set/get -2.0")

        prefs.baselineOffset = 0.5
        assertEqual(prefs.baselineOffset, 0.5, "set/get 0.5")

        prefs.baselineOffset = -10.0  // below min → clamped
        assertEqual(prefs.baselineOffset, -4.0, "clamp below min")

        prefs.baselineOffset = 10.0   // above max → clamped
        assertEqual(prefs.baselineOffset, 4.0, "clamp above max")
    }

    runSuite("Preferences: dataSourceMode") {
        prefs.dataSourceMode = "http"
        assertEqual(prefs.dataSourceMode, "http", "http mode")

        prefs.dataSourceMode = "websocket"
        assertEqual(prefs.dataSourceMode, "websocket", "websocket mode")
    }

    runSuite("Preferences: colorScheme") {
        prefs.colorScheme = "western"
        assertEqual(prefs.colorScheme, "western", "western scheme")

        prefs.colorScheme = "chinese"
        assertEqual(prefs.colorScheme, "chinese", "chinese scheme")
    }

    runSuite("Preferences: exchange rate cache") {
        prefs.lastExchangeRate = 7.1234
        assertEqual(prefs.lastExchangeRate!, 7.1234, "cache rate")
        assertTrue(prefs.lastExchangeRateUpdate != nil, "cache timestamp set")

        // effectiveExchangeRate helper
        prefs.exchangeRateMode = "auto"
        prefs.lastExchangeRate = 7.25
        assertEqual(prefs.effectiveExchangeRate(), 7.25, "auto uses cached")

        prefs.exchangeRateMode = "manual"
        prefs.manualExchangeRate = 6.50
        assertEqual(prefs.effectiveExchangeRate(), 6.50, "manual uses manual value")
    }
}
