import Cocoa

/// Application delegate — sets up the menu bar controller on launch
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }
}
