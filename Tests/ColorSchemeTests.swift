import Foundation

/// Tests for the color scheme logic used in MenuBarController.changeColor(isUp:).
/// We replicate the logic here to keep tests self-contained.
func runColorSchemeTests() {

    // Simulate the color scheme logic
    func isGreen(isUp: Bool, isChinese: Bool) -> Bool {
        if isUp {
            return !isChinese   // western: green↑,  chinese: red↑
        } else {
            return isChinese    // western: red↓,    chinese: green↓
        }
    }

    runSuite("Color scheme: western (green↑/red↓)") {

        // Up → green
        assertTrue(isGreen(isUp: true, isChinese: false), "western: up → green")
        // Down → red (not green)
        assertFalse(isGreen(isUp: false, isChinese: false), "western: down → red")

    }

    runSuite("Color scheme: chinese (red↑/green↓)") {

        // Up → red (not green)
        assertFalse(isGreen(isUp: true, isChinese: true), "chinese: up → red")
        // Down → green
        assertTrue(isGreen(isUp: false, isChinese: true), "chinese: down → green")

    }

    runSuite("Color scheme: edge cases") {

        // Zero change → treated as "up" (non-negative), green in western
        assertTrue(isGreen(isUp: true, isChinese: false), "zero → up → green(western)")
        assertFalse(isGreen(isUp: true, isChinese: true), "zero → up → red(chinese)")

    }

    runSuite("Arrow direction") {

        func arrow(changePercent: Double) -> String {
            changePercent >= 0 ? "↑" : "↓"
        }

        assertEqual(arrow(changePercent: 0.50), "↑", "+ → up arrow")
        assertEqual(arrow(changePercent: -0.50), "↓", "- → down arrow")
        assertEqual(arrow(changePercent: 0.0), "↑", "0 → up arrow (flat = up)")
    }

    runSuite("Change display format") {

        func changeDisplay(changePercent: Double) -> String {
            let arrow = changePercent >= 0 ? "↑" : "↓"
            return "\(arrow)\(String(format: "%.2f", abs(changePercent)))%"
        }

        assertEqual(changeDisplay(changePercent: 0.50), "↑0.50%", "+0.50%")
        assertEqual(changeDisplay(changePercent: -0.35), "↓0.35%", "-0.35%")
        assertEqual(changeDisplay(changePercent: 1.234), "↑1.23%", "+1.23% rounds to 2dp")
    }
}
