import Cocoa

/// Manages the macOS menu bar item — displays gold price and provides controls
final class MenuBarController: NSObject {

    // MARK: - Constants
    private static let troyOunceToGrams = 31.1034768

    // MARK: - Services
    private let goldService = GoldPriceService()
    private let currencyService = CurrencyService()

    // MARK: - UI
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var settingsWC: SettingsWindowController?

    // MARK: - State
    private var lastGoldResult: GoldPriceResult?
    private var lastError: String?
    private var isUpdating = false

    // MARK: - Menu items (updated dynamically)
    private let goldPriceItem = NSMenuItem(title: "金价: 加载中...", action: nil, keyEquivalent: "")
    private let exchangeRateItem = NSMenuItem(title: "汇率: 加载中...", action: nil, keyEquivalent: "")
    private let updateTimeItem = NSMenuItem(title: "更新时间: --", action: nil, keyEquivalent: "")

    // MARK: - Init
    override init() {
        super.init()
        setupStatusItem()
        startPolling()

        // Fetch exchange rate at launch (cached for 1 hour)
        Task { await refreshExchangeRate() }
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Au ⌛"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.smallSystemFontSize, weight: .medium)

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Gold price detail
        goldPriceItem.isEnabled = false
        menu.addItem(goldPriceItem)

        // Exchange rate detail
        exchangeRateItem.isEnabled = false
        menu.addItem(exchangeRateItem)

        // Last update time
        updateTimeItem.isEnabled = false
        menu.addItem(updateTimeItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh Now
        let refreshItem = NSMenuItem(
            title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = true
        menu.addItem(refreshItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "退出 GoldBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Polling

    private func startPolling() {
        let interval = Preferences.shared.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshGoldPrice() }
        }
        // Fire immediately
        Task { await refreshGoldPrice() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Refresh

    @objc private func refreshNow() {
        Task {
            await refreshGoldPrice()
            await refreshExchangeRate(forceRefresh: true)
        }
    }

    private func refreshGoldPrice() async {
        guard !isUpdating else { return }
        isUpdating = true

        do {
            let result = try await goldService.fetchPrice()
            await MainActor.run {
                lastGoldResult = result
                lastError = nil
                updateDisplay(with: result)
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                updateDisplayOnError()
            }
        }

        isUpdating = false
    }

    private func refreshExchangeRate(forceRefresh: Bool = false) async {
        // If in manual mode, skip auto-fetch
        if Preferences.shared.exchangeRateMode == "manual" && !forceRefresh {
            updateDisplayIfNeeded()
            return
        }

        do {
            let rate = try await currencyService.fetchRate(forceRefresh: forceRefresh)
            await MainActor.run {
                updateDisplayIfNeeded()
            }
            _ = rate // used via Preferences in display update
        } catch {
            // Use cached or fallback rate — no need to show error for rate alone
        }
    }

    // MARK: - Display

    private func updateDisplay(with result: GoldPriceResult) {
        let rate = Preferences.shared.effectiveExchangeRate()
        let rmbPerGram = result.priceUSDPerOunce * rate / Self.troyOunceToGrams

        // Status bar: compact display
        statusItem.button?.title = String(format: "Au ¥%.1f/g", rmbPerGram)

        // Menu items
        goldPriceItem.title = String(format: "黄金: $%.2f/oz (USD)", result.priceUSDPerOunce)
        exchangeRateItem.title = String(format: "汇率: %.4f USD/CNY", rate)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        updateTimeItem.title = "更新时间: \(formatter.string(from: result.tickTime))"
    }

    private func updateDisplayOnError() {
        statusItem.button?.title = "Au --.-/g"
        goldPriceItem.title = "金价: 获取失败"
        if let error = lastError {
            exchangeRateItem.title = "错误: \(error)"
        }
        updateTimeItem.title = "更新时间: 失败"
    }

    private func updateDisplayIfNeeded() {
        // Recompute display when exchange rate changes
        if let result = lastGoldResult {
            updateDisplay(with: result)
        }
    }

    // MARK: - Actions

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
        }
        settingsWC?.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
