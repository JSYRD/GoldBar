import Foundation

// GoldBar Test Suite
// Usage: ./test.sh            → unit tests only
//        ./test.sh --all      → unit + integration tests

print("🧪 GoldBar Test Suite")
print("====================\n")

// ── Unit tests (no network) ──
runPreferencesTests()
runPriceCalcTests()
runColorSchemeTests()

// ── Integration tests (API) ──
let args = CommandLine.arguments
let runIntegration = args.contains("--all") || args.contains("--integration")

if runIntegration {
    print("\n🌐 Integration tests (network required)...")

    // Read API key from environment or stored UserDefaults
    if let apiKey = ProcessInfo.processInfo.environment["GOLDBAR_API_KEY"]
            ?? Preferences.shared.apiKey {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await runAPITests(apiKey: apiKey)
            semaphore.signal()
        }
        semaphore.wait()
    } else {
        print("  ⚠️  Skipped: No API key configured.")
        print("     Set GOLDBAR_API_KEY env var or configure in the app first.")
    }
} else {
    print("\n💡 Run with --all for integration tests (requires API key)")
}

printSummary()
