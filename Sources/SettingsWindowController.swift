import Cocoa

/// Notification posted when settings that affect data fetching change
extension Notification.Name {
    static let goldBarSettingsChanged = Notification.Name("GoldBarSettingsChanged")
}

/// Settings window — allows the user to configure API key, data source, and exchange rate
final class SettingsWindowController: NSObject {

    private var window: NSWindow?

    // MARK: - Controls
    private let apiKeyField = NSTextField(frame: .zero)
    private let dataSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fontSizeSlider = NSSlider(frame: .zero)
    private let fontSizeLabel = NSTextField(labelWithString: "11 pt")
    private let baselineSlider = NSSlider(frame: .zero)
    private let baselineLabel = NSTextField(labelWithString: "-0.5 pt")
    private let rateModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let manualRateField = NSTextField(frame: .zero)
    private let statusLabel = NSTextField(frame: .zero)

    /// Captured slider values — decoupled from NSSlider's internal state
    private var pendingFontSize: Double = Preferences.defaultFontSize
    private var pendingBaselineOffset: Double = Preferences.defaultBaselineOffset

    func showWindow() {
        if window == nil {
            buildWindow()
        }
        window?.makeKeyAndOrderFront(nil)
        refreshFields()
    }

    // MARK: - Build UI

    private func buildWindow() {
        let width: CGFloat = 480
        let height: CGFloat = 390

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "GoldBar 设置"
        win.minSize = NSSize(width: 420, height: 270)
        win.center()
        win.isReleasedWhenClosed = false

        guard let contentView = win.contentView else { return }

        // --- Labels ---
        let apiKeyLabel = makeLabel("API Key:")
        let dataSourceLabel = makeLabel("数据源:")
        let rateModeLabel = makeLabel("汇率模式:")
        let manualRateLabel = makeLabel("手动汇率:")

        // --- API Key field ---
        apiKeyField.placeholderString = "输入你的 AllTick API Key"
        apiKeyField.isBordered = true
        apiKeyField.bezelStyle = .squareBezel
        apiKeyField.formatter = SingleLineFormatter()
        apiKeyField.cell?.usesSingleLineMode = true
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // --- Data source popup ---
        dataSourcePopup.addItems(withTitles: [
            "HTTP 轮询 (省资源，每15秒)",
            "WebSocket 实时推送 (秒级更新)"
        ])
        dataSourcePopup.toolTip = "HTTP: 定时拉取数据，节省资源。WebSocket: 长连接实时推送，更新更快"

        // --- Font size slider (integer steps, no tick marks) ---
        let fontSizeLabelLeft = makeLabel("显示大小:")
        fontSizeSlider.minValue = Preferences.minFontSize
        fontSizeSlider.maxValue = Preferences.maxFontSize
        fontSizeSlider.doubleValue = Preferences.shared.fontSize
        fontSizeSlider.isContinuous = true
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeChanged)
        fontSizeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        fontSizeLabel.alignment = .center
        fontSizeLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- Baseline offset slider (0.5 pt steps) ---
        let baselineLabelLeft = makeLabel("垂直偏移:")
        baselineSlider.minValue = Preferences.minBaselineOffset
        baselineSlider.maxValue = Preferences.maxBaselineOffset
        baselineSlider.doubleValue = Preferences.shared.baselineOffset
        baselineSlider.isContinuous = true
        baselineSlider.target = self
        baselineSlider.action = #selector(baselineChanged)
        baselineLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        baselineLabel.alignment = .center
        baselineLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- Rate mode popup ---
        rateModePopup.addItems(withTitles: ["自动获取 (推荐)", "手动输入"])
        rateModePopup.target = self
        rateModePopup.action = #selector(rateModeChanged)

        // --- Manual rate field ---
        manualRateField.placeholderString = "例如: 6.79"
        manualRateField.isBordered = true
        manualRateField.bezelStyle = .squareBezel
        manualRateField.formatter = NumberFormatter()
        (manualRateField.formatter as? NumberFormatter)?.allowsFloats = true
        (manualRateField.formatter as? NumberFormatter)?.minimumFractionDigits = 2
        (manualRateField.formatter as? NumberFormatter)?.maximumFractionDigits = 6

        // --- Buttons ---
        let saveButton = NSButton(
            title: "保存", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let cancelButton = NSButton(
            title: "取消", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded

        // --- Status label ---
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3

        // --- Row stack views ---
        let apiKeyRow = makeRow(label: apiKeyLabel, control: apiKeyField)
        let dataSourceRow = makeRow(label: dataSourceLabel, control: dataSourcePopup)
        let fontSizeRow = makeRow(label: fontSizeLabelLeft, control: fontSizeSlider, trailing: fontSizeLabel)
        let baselineRow = makeRow(label: baselineLabelLeft, control: baselineSlider, trailing: baselineLabel)
        let rateModeRow = makeRow(label: rateModeLabel, control: rateModePopup)
        let manualRateRow = makeRow(label: manualRateLabel, control: manualRateField)

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill
        buttonRow.spacing = 12
        buttonRow.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // --- Separator before data source ---
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // --- Main stack ---
        let mainStack = NSStackView(views: [
            apiKeyRow,
            separator,
            dataSourceRow,
            fontSizeRow,
            baselineRow,
            rateModeRow,
            manualRateRow,
            buttonRow,
            statusLabel
        ])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.distribution = .fill
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.setCustomSpacing(10, after: apiKeyRow)    // gap before separator
        mainStack.setCustomSpacing(10, after: separator)     // gap after separator
        mainStack.setCustomSpacing(20, after: manualRateRow)

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),

            // Separator stretches full width
            separator.leadingAnchor.constraint(equalTo: mainStack.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),

            // Rows stretch full width
            apiKeyRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            dataSourceRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            fontSizeRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            baselineRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            rateModeRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            manualRateRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),

            // Fixed label widths for alignment
            apiKeyLabel.widthAnchor.constraint(equalToConstant: 80),
            dataSourceLabel.widthAnchor.constraint(equalToConstant: 80),
            rateModeLabel.widthAnchor.constraint(equalToConstant: 80),
            manualRateLabel.widthAnchor.constraint(equalToConstant: 80),
        ])

        window = win
    }

    /// Create a horizontal row: [label | control]
    private func makeRow(label: NSTextField, control: NSView) -> NSStackView {
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// Create a horizontal row: [label | control | trailingLabel] (e.g. slider + value)
    private func makeRow(label: NSTextField, control: NSView, trailing: NSView) -> NSStackView {
        let row = NSStackView(views: [label, control, trailing])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - Field population

    private func refreshFields() {
        let prefs = Preferences.shared
        apiKeyField.stringValue = prefs.apiKey ?? ""
        apiKeyField.placeholderString = prefs.hasAPIKey
            ? "输入你的 AllTick API Key"
            : "⚠️ 请先粘贴你的 AllTick API Key 以开始使用"
        pendingFontSize = prefs.fontSize
        pendingBaselineOffset = prefs.baselineOffset
        fontSizeSlider.doubleValue = pendingFontSize
        fontSizeLabel.stringValue = String(format: "%.0f pt", pendingFontSize)
        baselineSlider.doubleValue = pendingBaselineOffset
        baselineLabel.stringValue = String(format: "%+.1f pt", pendingBaselineOffset)
        dataSourcePopup.selectItem(at: prefs.dataSourceMode == "websocket" ? 1 : 0)
        rateModePopup.selectItem(at: prefs.exchangeRateMode == "manual" ? 1 : 0)
        manualRateField.stringValue = String(format: "%.4f", prefs.manualExchangeRate)
        manualRateField.isEnabled = prefs.exchangeRateMode == "manual"

        // Show cache / connection status
        var lines: [String] = []

        if prefs.exchangeRateMode == "auto",
           let lastRate = prefs.lastExchangeRate,
           let lastUpdate = prefs.lastExchangeRateUpdate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM-dd HH:mm"
            lines.append("当前汇率: \(String(format: "%.4f", lastRate)) (更新于 \(formatter.string(from: lastUpdate)))")
        }

        if prefs.dataSourceMode == "websocket" {
            lines.append("💡 WebSocket 模式: 建立连接后秒级更新，无需手动刷新")
        } else {
            lines.append("💡 HTTP 模式: 每15秒自动拉取，节省系统资源")
        }

        statusLabel.stringValue = lines.joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func rateModeChanged() {
        let isManual = rateModePopup.indexOfSelectedItem == 1
        manualRateField.isEnabled = isManual
    }

    @objc private func fontSizeChanged() {
        // Only capture — don't write back to slider (avoids re-entrancy)
        pendingFontSize = fontSizeSlider.doubleValue.rounded()
        fontSizeLabel.stringValue = String(format: "%.0f pt", pendingFontSize)
    }

    @objc private func baselineChanged() {
        pendingBaselineOffset = (baselineSlider.doubleValue * 2.0).rounded() / 2.0
        baselineLabel.stringValue = String(format: "%+.1f pt", pendingBaselineOffset)
    }

    @objc private func saveSettings() {
        let prefs = Preferences.shared
        let newKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if newKey.isEmpty {
            showAlert(message: "API Key 不能为空")
            return
        }

        let oldDataSourceMode = prefs.dataSourceMode
        let oldAPIKey = prefs.apiKey

        prefs.apiKey = newKey
        prefs.dataSourceMode = dataSourcePopup.indexOfSelectedItem == 1 ? "websocket" : "http"
        prefs.fontSize = pendingFontSize
        prefs.baselineOffset = pendingBaselineOffset
        prefs.exchangeRateMode = rateModePopup.indexOfSelectedItem == 1 ? "manual" : "auto"

        if let manualRate = Double(manualRateField.stringValue), manualRate > 0 {
            prefs.manualExchangeRate = manualRate
        }

        // Notify if data source mode or API key changed (so MenuBarController can switch)
        if prefs.dataSourceMode != oldDataSourceMode || prefs.apiKey != oldAPIKey {
            NotificationCenter.default.post(
                name: .goldBarSettingsChanged, object: nil)
        }

        statusLabel.stringValue = "✅ 设置已保存 — 若切换数据源将立即生效"
        statusLabel.textColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.statusLabel.textColor = .secondaryLabelColor
            self?.refreshFields()
        }
    }

    @objc private func closeWindow() {
        window?.close()
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "提示"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")
        alert.beginSheetModal(for: window!, completionHandler: nil)
    }
}
