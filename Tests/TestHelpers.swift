import Foundation

// MARK: - Minimal test framework

var totalTests = 0
var passedTests = 0
var failedTests = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "",
                                file: String = #file, line: Int = #line) {
    totalTests += 1
    if actual == expected {
        passedTests += 1
    } else {
        failedTests += 1
        let loc = (file as NSString).lastPathComponent
        print("  ❌ FAIL \(loc):\(line) — \(message)")
        print("     expected: \(expected)")
        print("     actual:   \(actual)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "",
                file: String = #file, line: Int = #line) {
    assertEqual(condition, true, message, file: file, line: line)
}

func assertFalse(_ condition: Bool, _ message: String = "",
                 file: String = #file, line: Int = #line) {
    assertEqual(condition, false, message, file: file, line: line)
}

func assertNil<T>(_ value: T?, _ message: String = "",
                  file: String = #file, line: Int = #line) where T: Equatable {
    totalTests += 1
    if value == nil {
        passedTests += 1
    } else {
        failedTests += 1
        let loc = (file as NSString).lastPathComponent
        print("  ❌ FAIL \(loc):\(line) — \(message)")
        print("     expected nil, got \(value!)")
    }
}

func runSuite(_ name: String, _ block: () -> Void) {
    let before = totalTests
    print("\n📦 \(name)")
    block()
    let ran = totalTests - before
    if ran == 0 { print("  (no tests)") }
}

func runSuite(_ name: String, _ block: () async -> Void) async {
    let before = totalTests
    print("\n📦 \(name)")
    await block()
    let ran = totalTests - before
    if ran == 0 { print("  (no tests)") }
}

func printSummary() {
    print("\n" + String(repeating: "=", count: 50))
    print("Results: \(passedTests)/\(totalTests) passed")
    if failedTests > 0 {
        print("❌ \(failedTests) test(s) FAILED")
        fflush(stdout)
        exit(1)
    } else {
        print("✅ All tests passed")
        fflush(stdout)
        exit(0)
    }
}

// MARK: - Shared test constants

let troyOunceToGrams = 31.1034768
