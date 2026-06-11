import Cocoa

/// Manages the macOS menu bar item — displays gold price and provides controls.
/// Supports two data source modes: HTTP polling and WebSocket push.
final class MenuBarController: NSObject {

    // MARK: - Constants
    private static let troyOunceToGrams = 31.1034768

    // MARK: - Services
    private let goldService = GoldPriceService()
    private let currencyService = CurrencyService()
    private let wsService = WebSocketService()

    // MARK: - UI
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var settingsWC: SettingsWindowController?

    // MARK: - State
    private var lastGoldResult: GoldPriceResult?
    private var lastError: String?
    private var isUpdating = false
    private var currentMode: String = "http" // "http" or "websocket"
    private var wsConnectionState: WebSocketService.ConnectionState = .disconnected

    // MARK: - Menu items (updated dynamically)
    private let goldPriceItem = NSMenuItem(title: "金价: 加载中...", action: nil, keyEquivalent: "")
    private let exchangeRateItem = NSMenuItem(title: "汇率: 加载中...", action: nil, keyEquivalent: "")
    private let updateTimeItem = NSMenuItem(title: "更新时间: --", action: nil, keyEquivalent: "")
    private let dataSourceItem = NSMenuItem(title: "数据源: --", action: nil, keyEquivalent: "")

    // MARK: - Init
    override init() {
        super.init()
        setupStatusItem()
        setupWebSocketCallbacks()
        observeSettingsChanges()
        startDataFetching()

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

        // Data source mode
        dataSourceItem.isEnabled = false
        menu.addItem(dataSourceItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh Now (only relevant for HTTP mode)
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
            // In WebSocket mode, reconnect to get fresh subscription
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
        if lastGoldResult == nil {
            statusItem.button?.title = "Au --.-/g"
        } else {
            // Keep last known price but indicate staleness in menu
            statusItem.button?.title = (statusItem.button?.title ?? "Au ⌛")
                .replacingOccurrences(of: "Au ¥", with: "Au ⚠¥")
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
        let modeLabel = currentMode == "websocket" ? "WebSocket" : "HTTP 轮询"

        switch wsConnectionState {
        case .connected:
            dataSourceItem.title = "数据源: \(modeLabel) ✅"
        case .connecting:
            dataSourceItem.title = "数据源: \(modeLabel) ⏳"
        case .disconnected:
            if currentMode == "websocket" {
                dataSourceItem.title = "数据源: \(modeLabel) ❌ (自动重连中)"
            } else {
                dataSourceItem.title = "数据源: \(modeLabel)"
            }
        case .error(let msg):
            dataSourceItem.title = "数据源: \(modeLabel) ❌ \(msg)"
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
