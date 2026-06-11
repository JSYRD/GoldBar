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
        let width: CGFloat = 420
        let height: CGFloat = 240

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "GoldBar 设置"
        win.center()
        win.isReleasedWhenClosed = false

        guard let contentView = win.contentView else { return }

        // Disable auto-resizing mask
        let allFields: [NSView] = [apiKeyField, rateModePopup, manualRateField, statusLabel]
        allFields.forEach { $0.translatesAutoresizingMaskIntoConstraints = false }

        // --- API Key row ---
        let apiKeyLabel = makeLabel("API Key:")
        contentView.addSubview(apiKeyLabel)
        apiKeyField.placeholderString = "输入你的 AllTick API Key"
        apiKeyField.isBordered = true
        apiKeyField.bezelStyle = .squareBezel
        contentView.addSubview(apiKeyField)

        // --- Rate mode row ---
        let rateModeLabel = makeLabel("汇率模式:")
        contentView.addSubview(rateModeLabel)
        rateModePopup.addItems(withTitles: ["自动获取 (推荐)", "手动输入"])
        rateModePopup.target = self
        rateModePopup.action = #selector(rateModeChanged)
        contentView.addSubview(rateModePopup)

        // --- Manual rate row ---
        let manualRateLabel = makeLabel("手动汇率:")
        contentView.addSubview(manualRateLabel)
        manualRateField.placeholderString = "例如: 6.79"
        manualRateField.isBordered = true
        manualRateField.bezelStyle = .squareBezel
        manualRateField.formatter = NumberFormatter()
        (manualRateField.formatter as? NumberFormatter)?.allowsFloats = true
        (manualRateField.formatter as? NumberFormatter)?.minimumFractionDigits = 2
        (manualRateField.formatter as? NumberFormatter)?.maximumFractionDigits = 6
        contentView.addSubview(manualRateField)

        // --- Buttons ---
        let saveButton = NSButton(
            title: "保存", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let cancelButton = NSButton(
            title: "取消", target: self, action: #selector(closeWindow))
        cancelButton.bezelStyle = .rounded
        contentView.addSubview(cancelButton)

        // --- Status label ---
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        contentView.addSubview(statusLabel)

        // Layout
        let views: [String: NSView] = [
            "apiKeyLabel": apiKeyLabel, "apiKeyField": apiKeyField,
            "rateModeLabel": rateModeLabel, "rateModePopup": rateModePopup,
            "manualRateLabel": manualRateLabel, "manualRateField": manualRateField,
            "saveButton": saveButton, "cancelButton": cancelButton,
            "statusLabel": statusLabel
        ]

        let metrics: [String: CGFloat] = [
            "margin": 20, "spacing": 12, "fieldH": 24,
            "labelW": 80, "buttonW": 90
        ]

        contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|-margin-[apiKeyLabel(==labelW)]-spacing-[apiKeyField]-margin-|",
            metrics: metrics, views: views))
        contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|-margin-[rateModeLabel(==labelW)]-spacing-[rateModePopup]-margin-|",
            metrics: metrics, views: views))
        contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|-margin-[manualRateLabel(==labelW)]-spacing-[manualRateField]-margin-|",
            metrics: metrics, views: views))
        contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:[cancelButton(==buttonW)]-spacing-[saveButton(==buttonW)]-margin-|",
            metrics: metrics, views: views))
        contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|-margin-[statusLabel]-margin-|",
            metrics: metrics, views: views))

        contentView.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:|-margin-[apiKeyLabel(==fieldH)]-spacing-[rateModeLabel(==fieldH)]-spacing-[manualRateLabel(==fieldH)]-20-[saveButton(==28)]-spacing-[statusLabel]",
            metrics: metrics, views: views))

        // Align fields with their labels
        NSLayoutConstraint.activate([
            apiKeyField.centerYAnchor.constraint(equalTo: apiKeyLabel.centerYAnchor),
            apiKeyField.heightAnchor.constraint(equalToConstant: 24),
            rateModePopup.centerYAnchor.constraint(equalTo: rateModeLabel.centerYAnchor),
            rateModePopup.heightAnchor.constraint(equalToConstant: 24),
            manualRateField.centerYAnchor.constraint(equalTo: manualRateLabel.centerYAnchor),
            manualRateField.heightAnchor.constraint(equalToConstant: 24),
            cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])

        window = win
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
