import Cocoa

/// Settings window — allows the user to configure API key and exchange rate
final class SettingsWindowController: NSObject {

    private var window: NSWindow?

    // MARK: - Controls
    private let apiKeyField = NSTextField(frame: .zero)
    private let rateModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let manualRateField = NSTextField(frame: .zero)
    private let statusLabel = NSTextField(frame: .zero)

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
        let height: CGFloat = 260

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "GoldBar 设置"
        win.minSize = NSSize(width: 420, height: 220)
        win.center()
        win.isReleasedWhenClosed = false

        guard let contentView = win.contentView else { return }

        // --- Labels ---
        let apiKeyLabel = makeLabel("API Key:")
        let rateModeLabel = makeLabel("汇率模式:")
        let manualRateLabel = makeLabel("手动汇率:")

        // --- API Key field ---
        apiKeyField.placeholderString = "输入你的 AllTick API Key"
        apiKeyField.isBordered = true
        apiKeyField.bezelStyle = .squareBezel
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

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

        // --- Row stack views ---
        let apiKeyRow = makeRow(label: apiKeyLabel, control: apiKeyField)
        let rateModeRow = makeRow(label: rateModeLabel, control: rateModePopup)
        let manualRateRow = makeRow(label: manualRateLabel, control: manualRateField)

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill
        buttonRow.spacing = 12
        // Push buttons to the right
        buttonRow.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // --- Main stack ---
        let mainStack = NSStackView(views: [
            apiKeyRow,
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
        mainStack.setCustomSpacing(20, after: manualRateRow)

        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),

            // Rows stretch full width
            apiKeyRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            rateModeRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            manualRateRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: mainStack.trailingAnchor),

            // Fixed label widths for alignment
            apiKeyLabel.widthAnchor.constraint(equalToConstant: 80),
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

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: - Field population

    private func refreshFields() {
        let prefs = Preferences.shared
        apiKeyField.stringValue = prefs.apiKey
        rateModePopup.selectItem(at: prefs.exchangeRateMode == "manual" ? 1 : 0)
        manualRateField.stringValue = String(format: "%.4f", prefs.manualExchangeRate)
        manualRateField.isEnabled = prefs.exchangeRateMode == "manual"

        // Show cache status
        if prefs.exchangeRateMode == "auto",
           let lastRate = prefs.lastExchangeRate,
           let lastUpdate = prefs.lastExchangeRateUpdate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "MM-dd HH:mm"
            statusLabel.stringValue =
                "当前汇率: \(String(format: "%.4f", lastRate)) (更新于 \(formatter.string(from: lastUpdate)))"
        } else {
            statusLabel.stringValue = ""
        }
    }

    // MARK: - Actions

    @objc private func rateModeChanged() {
        let isManual = rateModePopup.indexOfSelectedItem == 1
        manualRateField.isEnabled = isManual
    }

    @objc private func saveSettings() {
        let prefs = Preferences.shared
        let newKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if newKey.isEmpty {
            showAlert(message: "API Key 不能为空")
            return
        }

        prefs.apiKey = newKey
        prefs.exchangeRateMode = rateModePopup.indexOfSelectedItem == 1 ? "manual" : "auto"

        if let manualRate = Double(manualRateField.stringValue), manualRate > 0 {
            prefs.manualExchangeRate = manualRate
        }

        statusLabel.stringValue = "✅ 设置已保存"
        statusLabel.textColor = .systemGreen

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
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
