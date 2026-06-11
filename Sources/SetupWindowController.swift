import Cocoa

/// First-launch / no-API-key window.
/// Blocks data fetching until the user provides a valid AllTick API token.
final class SetupWindowController: NSObject {

    private var window: NSWindow?
    private let apiKeyField = NSTextField(frame: .zero)
    private let hintLabel = NSTextField(frame: .zero)
    private var saveButton: NSButton!

    var onDismiss: (() -> Void)?

    func showWindow() {
        if window == nil { buildWindow() }

        // Temporarily promote to .regular so the Edit menu (⌘V etc.) works
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        window?.makeFirstResponder(apiKeyField)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }

    // MARK: - Build

    private func buildWindow() {
        let width: CGFloat = 460
        let height: CGFloat = 280

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "欢迎使用 GoldBar"
        win.isReleasedWhenClosed = false
        // Allow closing — user can configure later via Settings
        win.delegate = self

        guard let contentView = win.contentView else { return }

        // --- Subtitle ---
        let subtitleLabel = NSTextField(wrappingLabelWithString:
            "GoldBar 需要 AllTick API Key 才能获取实时金价数据。\n请前往 alltick.co 注册并获取免费 Token。")
        subtitleLabel.alignment = .center
        subtitleLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- API Key field ---
        apiKeyField.placeholderString = "粘贴你的 AllTick API Key (⌘V)"
        apiKeyField.isBordered = true
        apiKeyField.bezelStyle = .squareBezel
        apiKeyField.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        apiKeyField.formatter = SingleLineFormatter()
        apiKeyField.cell?.usesSingleLineMode = true
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false

        // --- Buttons ---
        let getKeyButton = NSButton(
            title: "获取免费 API Key", target: self, action: #selector(openAllTick))
        getKeyButton.bezelStyle = .rounded

        saveButton = NSButton(
            title: "开始使用", target: self, action: #selector(saveAndStart))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.isEnabled = false

        let buttonRow = NSStackView(views: [getKeyButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.distribution = .fill
        buttonRow.spacing = 12
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        // --- Hint ---
        hintLabel.stringValue = ""
        hintLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .systemRed
        hintLabel.alignment = .center
        hintLabel.isEditable = false
        hintLabel.isBordered = false
        hintLabel.drawsBackground = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        // --- Track field changes ---
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSControl.textDidChangeNotification,
            object: apiKeyField
        )

        // Layout
        contentView.addSubview(subtitleLabel)
        contentView.addSubview(apiKeyField)
        contentView.addSubview(buttonRow)
        contentView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            // Extra top padding to avoid overlap with title bar
            subtitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 36),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            apiKeyField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            apiKeyField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            apiKeyField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            apiKeyField.heightAnchor.constraint(equalToConstant: 28),

            buttonRow.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 20),
            buttonRow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            hintLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])

        window = win
    }

    // MARK: - Actions

    @objc private func textDidChange() {
        let trimmed = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        saveButton.isEnabled = !trimmed.isEmpty
        hintLabel.stringValue = ""
    }

    @objc private func saveAndStart() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            hintLabel.stringValue = "请输入有效的 API Key"
            return
        }

        guard key.count >= 16 else {
            hintLabel.stringValue = "API Key 格式不正确，请检查后重试"
            return
        }

        Preferences.shared.apiKey = key
        hintLabel.stringValue = ""

        // Demote back to accessory (menu-bar-only) mode
        NSApp.setActivationPolicy(.accessory)
        window?.close()
        onDismiss?()
    }

    @objc private func openAllTick() {
        if let url = URL(string: "https://alltick.co") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - NSWindowDelegate

extension SetupWindowController: NSWindowDelegate {

    func windowWillClose(_ notification: Notification) {
        // If user closes window without configuring a key,
        // keep the app alive and demote to menu-bar-only mode.
        if !Preferences.shared.hasAPIKey {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
