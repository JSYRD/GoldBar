import Cocoa

/// Application delegate — sets up main menu and menu bar controller on launch
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        menuBarController = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }

    // MARK: - Main Menu

    /// Build a minimal main menu so that Edit actions (⌘V paste, ⌘C copy, etc.)
    /// work in text fields.  `.accessory` apps don't get a default menu.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // --- App menu (GoldBar) ---
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "关于 GoldBar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(
            title: "退出 GoldBar", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenu.addItem(quitItem)

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // --- Edit menu ---
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(
            title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(
            title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(
            title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(
            title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(
            title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(
            title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
