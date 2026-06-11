import Cocoa

/// Manages the macOS menu bar item — displays gold price and provides controls.
/// Supports two data source modes: HTTP polling and WebSocket push.
final class MenuBarController: NSObject {

    // MARK: - Constants
    private static let troyOunceToGrams = 31.1034768

    // MARK: - Services
    private let goldService = GoldPriceService()
    private let currencyService = CurrencyService()
    private let klineService = KLineService()
    private let wsService = WebSocketService()

    // MARK: - UI
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var klineTimer: Timer?
    private var settingsWC: SettingsWindowController?
    private var setupWC: SetupWindowController?

    // MARK: - State
    private var lastGoldResult: GoldPriceResult?
    private var lastError: String?
    private var isUpdating = false
    private var currentMode: String = "http" // "http" or "websocket"
    private var wsConnectionState: WebSocketService.ConnectionState = .disconnected

    /// Cached previous close for change calculation (refreshed every 30 min)
    private var previousClose: Double?
    /// Computed change percentage (positive = up, negative = down)
    private var changePercent: Double?

    // MARK: - Menu items (updated dynamically)
    private let goldPriceItem = NSMenuItem(title: "金价: 加载中...", action: nil, keyEquivalent: "")
    private let changeItem = NSMenuItem(title: "涨跌: --", action: nil, keyEquivalent: "")
    private let exchangeRateItem = NSMenuItem(title: "汇率: 加载中...", action: nil, keyEquivalent: "")
    private let updateTimeItem = NSMenuItem(title: "更新时间: --", action: nil, keyEquivalent: "")

    // Data source submenu
    private let dataSourceSubmenu = NSMenu()
    private let httpModeItem = NSMenuItem(title: "HTTP 轮询", action: #selector(switchToHTTP), keyEquivalent: "")
    private let wsModeItem = NSMenuItem(title: "WebSocket 实时推送", action: #selector(switchToWebSocket), keyEquivalent: "")

    // Color scheme submenu
    private let colorSchemeSubmenu = NSMenu()
    private let colorWesternItem = NSMenuItem(title: "绿涨红跌 (国际)", action: #selector(switchToWesternColors), keyEquivalent: "")
    private let colorChineseItem = NSMenuItem(title: "红涨绿跌 (国内)", action: #selector(switchToChineseColors), keyEquivalent: "")

    // MARK: - Init
    override init() {
        super.init()
        setupStatusItem()
        setupWebSocketCallbacks()
        observeSettingsChanges()

        if Preferences.shared.hasAPIKey {
            // Restore cached reference price
            previousClose = Preferences.shared.previousClose
            startDataFetching()
            startKLineRefresh()
            Task {
                await refreshExchangeRate()
                await refreshKLineReference()
            }
        } else {
            statusItem.button?.title = "Au ⚙️"
            goldPriceItem.title = "金价: 请先配置 API Key"
            exchangeRateItem.title = "点击「设置...」配置 API Key"
            updateTimeItem.title = "更新时间: --"

            // Slight delay so the status item is on screen before the window pops
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.showSetupWindow()
            }
        }
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

        // Change (↑↓)
        changeItem.isEnabled = false
        menu.addItem(changeItem)

        // Exchange rate detail
        exchangeRateItem.isEnabled = false
        menu.addItem(exchangeRateItem)

        // Last update time
        updateTimeItem.isEnabled = false
        menu.addItem(updateTimeItem)

        menu.addItem(NSMenuItem.separator())

        // Data source submenu
        httpModeItem.target = self
        wsModeItem.target = self
        dataSourceSubmenu.addItem(httpModeItem)
        dataSourceSubmenu.addItem(wsModeItem)

        let dataSourceSubmenuItem = NSMenuItem(title: "数据源", action: nil, keyEquivalent: "")
        dataSourceSubmenuItem.submenu = dataSourceSubmenu
        menu.addItem(dataSourceSubmenuItem)

        // Color scheme submenu
        colorWesternItem.target = self
        colorChineseItem.target = self
        colorSchemeSubmenu.addItem(colorWesternItem)
        colorSchemeSubmenu.addItem(colorChineseItem)
        updateColorSchemeCheckmark()

        let colorSchemeSubmenuItem = NSMenuItem(title: "涨跌配色", action: nil, keyEquivalent: "")
        colorSchemeSubmenuItem.submenu = colorSchemeSubmenu
        menu.addItem(colorSchemeSubmenuItem)

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

    private func setupWebSocketCallbacks() {
        wsService.onPriceUpdate = { [weak self] result in
            guard let self = self else { return }
            self.lastGoldResult = result
            self.lastError = nil
            self.updateDisplay(with: result)
        }

        wsService.onConnectionStateChange = { [weak self] state in
            guard let self = self else { return }
            self.wsConnectionState = state
            self.updateDataSourceItem()
        }
    }

    private func observeSettingsChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged),
            name: .goldBarSettingsChanged,
            object: nil
        )
    }

    @objc private func handleSettingsChanged() {
        let newMode = Preferences.shared.dataSourceMode
        if newMode != currentMode {
            restartDataFetching()
        }
    }

    // MARK: - Data fetching (mode-aware)

    private func startDataFetching() {
        currentMode = Preferences.shared.dataSourceMode
        updateDataSourceItem()

        switch currentMode {
        case "websocket":
            startWebSocket()
        default:
            startHTTPPolling()
        }
    }

    private func stopDataFetching() {
        stopHTTPPolling()
        stopWebSocket()
    }

    private func restartDataFetching() {
        stopDataFetching()
        // Brief delay to allow cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startDataFetching()
        }
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        stopDataFetching()
        klineTimer?.invalidate()
        klineTimer = nil
    }

    // MARK: - HTTP Polling mode

    private func startHTTPPolling() {
        stopWebSocket()
        let interval = Preferences.shared.refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshGoldPriceHTTP() }
        }
        // Fire immediately
        Task { await refreshGoldPriceHTTP() }
    }

    private func stopHTTPPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshGoldPriceHTTP() async {
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

    // MARK: - WebSocket mode

    private func startWebSocket() {
        stopHTTPPolling()
        wsService.connect()
    }

    private func stopWebSocket() {
        wsService.disconnect()
    }

    // MARK: - Refresh

    @objc private func refreshNow() {
        if currentMode == "websocket" {
            wsService.disconnect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.wsService.connect()
            }
        } else {
            Task {
                await refreshGoldPriceHTTP()
                await refreshExchangeRate(forceRefresh: true)
            }
        }
        // Always refresh reference price
        Task { await refreshKLineReference() }
    }

    private func refreshExchangeRate(forceRefresh: Bool = false) async {
        if Preferences.shared.exchangeRateMode == "manual" && !forceRefresh {
            updateDisplayIfNeeded()
            return
        }

        do {
            _ = try await currencyService.fetchRate(forceRefresh: forceRefresh)
            await MainActor.run { updateDisplayIfNeeded() }
        } catch {
            // Use cached or fallback rate — no need to show error for rate alone
        }
    }

    // MARK: - K-Line reference (daily close for change calculation)

    /// Starts a timer that refreshes the previous-day close every 30 minutes.
    /// The reference price only changes once per trading day, so this is generous.
    private func startKLineRefresh() {
        klineTimer?.invalidate()
        klineTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { await self?.refreshKLineReference() }
        }
    }

    private func refreshKLineReference() async {
        // Use cached value if available and data fetching hasn't started yet
        if let cached = klineService.cachedReference() {
            await MainActor.run {
                previousClose = cached.previousClose
                updateDisplayIfNeeded()
            }
        }
        // Always try a network refresh to keep it current
        do {
            let ref = try await klineService.fetchReference()
            await MainActor.run {
                previousClose = ref.previousClose
                updateDisplayIfNeeded()
            }
        } catch {
            // Use cached value silently — it's only stale once per day
        }
    }

    // MARK: - Display

    private func updateDisplay(with result: GoldPriceResult) {
        let rate = Preferences.shared.effectiveExchangeRate()
        let rmbPerGram = result.priceUSDPerOunce * rate / Self.troyOunceToGrams

        // Compute change if we have a reference close
        if let prevClose = previousClose, prevClose > 0 {
            changePercent = (result.priceUSDPerOunce - prevClose) / prevClose * 100.0
        }

        // Status bar: price + change arrow + percentage (colored)
        if let chg = changePercent {
            let arrow = chg >= 0 ? "↑" : "↓"
            let color = changeColor(isUp: chg >= 0)
            let title = String(format: "Au ¥%.1f/g \(arrow)%.2f%%", rmbPerGram, abs(chg))
            statusItem.button?.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.smallSystemFontSize, weight: .medium),
                    .foregroundColor: color
                ])
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(
                string: String(format: "Au ¥%.1f/g", rmbPerGram))
        }

        // Menu items
        goldPriceItem.title = String(format: "黄金: $%.2f/oz (USD)", result.priceUSDPerOunce)

        if let chg = changePercent, let prevClose = previousClose {
            let arrow = chg >= 0 ? "↑" : "↓"
            changeItem.title = String(format: "涨跌: \(arrow)%.2f%%   (昨收 $%.2f)", abs(chg), prevClose)
        } else {
            changeItem.title = "涨跌: 等待基准价..."
        }

        exchangeRateItem.title = String(format: "汇率: %.4f USD/CNY", rate)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        updateTimeItem.title = "更新时间: \(formatter.string(from: result.tickTime))"
    }

    private func updateDisplayOnError() {
        if lastGoldResult == nil {
            statusItem.button?.attributedTitle = NSAttributedString(string: "Au --.-/g")
        } else {
            let title = statusItem.button?.attributedTitle.string ?? "Au --.-/g"
            // Keep last known price but indicate staleness
            let muted = NSAttributedString(
                string: title.replacingOccurrences(of: "Au ¥", with: "Au ⚠¥"),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.smallSystemFontSize, weight: .medium),
                    .foregroundColor: NSColor.systemGray
                ])
            statusItem.button?.attributedTitle = muted
        }
        goldPriceItem.title = "金价: 获取失败"
        if let error = lastError {
            exchangeRateItem.title = "错误: \(error)"
        }
        updateTimeItem.title = "更新时间: 失败"
    }

    private func updateDisplayIfNeeded() {
        if let result = lastGoldResult {
            updateDisplay(with: result)
        }
    }

    private func updateDataSourceItem() {
        // Checkmark: indicate which mode is active
        httpModeItem.state = (currentMode == "http") ? .on : .off
        wsModeItem.state = (currentMode == "websocket") ? .on : .off

        // Append connection status to WebSocket item
        switch wsConnectionState {
        case .connected:
            wsModeItem.title = "WebSocket 实时推送 ✅"
        case .connecting:
            wsModeItem.title = "WebSocket 实时推送 ⏳"
        case .disconnected:
            wsModeItem.title = "WebSocket 实时推送"
        case .error(let msg):
            wsModeItem.title = "WebSocket 实时推送 ❌ \(msg)"
        }

        // HTTP item is always clean
        httpModeItem.title = "HTTP 轮询"
    }

    // MARK: - Actions

    @objc private func switchToHTTP() {
        guard currentMode != "http" else { return }
        Preferences.shared.dataSourceMode = "http"
        restartDataFetching()
    }

    @objc private func switchToWebSocket() {
        guard currentMode != "websocket" else { return }
        Preferences.shared.dataSourceMode = "websocket"
        restartDataFetching()
    }

    // MARK: - Color scheme

    /// Returns the appropriate color for a price move based on user preference.
    /// "western": green for up, red for down.  "chinese": red for up, green for down.
    private func changeColor(isUp: Bool) -> NSColor {
        let isChinese = Preferences.shared.colorScheme == "chinese"
        let green = NSColor.systemGreen.blended(withFraction: 0.3, of: .black) ?? .systemGreen
        let red = NSColor.systemRed

        if isUp {
            return isChinese ? red : green
        } else {
            return isChinese ? green : red
        }
    }

    private func updateColorSchemeCheckmark() {
        let scheme = Preferences.shared.colorScheme
        colorWesternItem.state = (scheme == "western") ? .on : .off
        colorChineseItem.state = (scheme == "chinese") ? .on : .off
    }

    @objc private func switchToWesternColors() {
        Preferences.shared.colorScheme = "western"
        updateColorSchemeCheckmark()
        updateDisplayIfNeeded()
    }

    @objc private func switchToChineseColors() {
        Preferences.shared.colorScheme = "chinese"
        updateColorSchemeCheckmark()
        updateDisplayIfNeeded()
    }

    // MARK: - Window actions

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
        }
        settingsWC?.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSetupWindow() {
        if setupWC == nil {
            setupWC = SetupWindowController()
        }
        setupWC?.onDismiss = { [weak self] in
            self?.previousClose = Preferences.shared.previousClose
            self?.startDataFetching()
            self?.startKLineRefresh()
            Task {
                await self?.refreshExchangeRate()
                await self?.refreshKLineReference()
            }
        }
        setupWC?.showWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
