import Foundation

/// WebSocket-based gold price service using AllTick's real-time push API.
/// Protocol summary:
///   - Connect: wss://quote.alltick.co/quote-b-ws-api?token=TOKEN
///   - Heartbeat (cmd_id=22000) every 10 seconds
///   - Subscribe (cmd_id=22004) with symbol_list [GOLD]
///   - Push data (cmd_id=22998) contains price, tick_time, etc.
final class WebSocketService: NSObject {

    // MARK: - Callbacks
    var onPriceUpdate: ((GoldPriceResult) -> Void)?
    var onConnectionStateChange: ((ConnectionState) -> Void)?

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Constants
    private let wsBaseURL = "wss://quote.alltick.co/quote-b-ws-api"
    private let heartbeatInterval: TimeInterval = 10.0
    private let maxReconnectDelay: TimeInterval = 60.0
    private let symbol = "GOLD"

    // MARK: - Internal state
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var heartbeatTimer: DispatchSourceTimer?
    private var reconnectTimer: DispatchSourceTimer?
    private var state: ConnectionState = .disconnected {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.onConnectionStateChange?(self?.state ?? .disconnected)
            }
        }
    }
    private var seqID: UInt32 = 0
    private var reconnectDelay: TimeInterval = 2.0
    private var wantsConnection = false
    private var heartbeatFailures = 0

    // MARK: - Dispatch queue
    private let wsQueue = DispatchQueue(label: "com.goldbar.websocket", qos: .utility)

    // MARK: - Init
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    deinit {
        disconnect()
    }

    // MARK: - Public API

    func connect() {
        wantsConnection = true
        reconnectDelay = 2.0
        performConnect()
    }

    func disconnect() {
        wantsConnection = false
        cancelTimers()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        state = .disconnected
    }

    // MARK: - Connection

    private func performConnect() {
        guard wantsConnection else { return }

        guard let apiKey = Preferences.shared.apiKey else {
            state = .error("请先配置 API Key")
            return
        }

        state = .connecting

        var components = URLComponents(string: wsBaseURL)!
        components.queryItems = [URLQueryItem(name: "token", value: apiKey)]

        guard let url = components.url else {
            state = .error("无效的 WebSocket URL")
            return
        }

        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        // Wait for the connection to open, then start heartbeat + subscribe
        waitForConnection()
    }

    private func waitForConnection() {
        webSocketTask?.sendPing { [weak self] error in
            guard let self = self, self.wantsConnection else { return }

            if error != nil {
                // Connection failed — clean up and schedule reconnect.
                // Don't rely on didClose: a network drop may not produce a clean TCP close.
                self.wsQueue.async {
                    self.webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                    self.webSocketTask = nil
                    self.state = .disconnected
                    self.scheduleReconnect()
                }
                return
            }

            self.wsQueue.async {
                self.state = .connected
                self.reconnectDelay = 2.0        // reset backoff
                self.heartbeatFailures = 0        // reset heartbeat health
                self.startHeartbeat()
                self.subscribe()
                self.startReceiving()
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        cancelHeartbeat()

        let timer = DispatchSource.makeTimerSource(queue: wsQueue)
        timer.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.sendHeartbeat()
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func sendHeartbeat() {
        guard webSocketTask != nil else { return }
        seqID += 1
        let message: [String: Any] = [
            "cmd_id": 22000,
            "seq_id": seqID,
            "trace": UUID().uuidString,
            "data": [:] as [String: Any]
        ]
        sendJSON(message) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.heartbeatFailures = 0
            } else {
                self.heartbeatFailures += 1
                if self.heartbeatFailures >= 3 {
                    // 3 consecutive heartbeat failures → assume dead, reconnect
                    self.webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                    self.webSocketTask = nil
                    self.cancelHeartbeat()
                    self.state = .disconnected
                    if self.wantsConnection {
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }

    // MARK: - Subscribe

    private func subscribe() {
        seqID += 1
        let message: [String: Any] = [
            "cmd_id": 22004,
            "seq_id": seqID,
            "trace": UUID().uuidString,
            "data": [
                "symbol_list": [
                    ["code": symbol]
                ]
            ]
        ]
        sendJSON(message)
    }

    // MARK: - Receive loop

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            self.handleReceive(result)
        }
    }

    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                wsQueue.async { [weak self] in
                    self?.handleTextMessage(text)
                }
            case .data(let data):
                if let text = String(data: data, encoding: .utf8) {
                    wsQueue.async { [weak self] in
                        self?.handleTextMessage(text)
                    }
                }
            @unknown default:
                break
            }
            // Continue receiving
            if wantsConnection {
                startReceiving()
            }

        case .failure:
            // Connection broken — force reconnect, don't wait for didClose
            wsQueue.async { [weak self] in
                guard let self = self else { return }
                self.webSocketTask?.cancel(with: .abnormalClosure, reason: nil)
                self.webSocketTask = nil
                self.cancelHeartbeat()
                self.state = .disconnected
                if self.wantsConnection {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmdID = json["cmd_id"] as? Int else {
            return
        }

        // Any successful receive means the connection is alive
        heartbeatFailures = 0

        switch cmdID {
        case 22001:
            // Heartbeat response — connection is alive
            break

        case 22005:
            // Subscribe response
            if let ret = json["ret"] as? Int, ret == 200 {
                print("[WebSocket] Subscription confirmed")
            } else {
                let msg = json["msg"] as? String ?? "unknown"
                print("[WebSocket] Subscription error: \(msg)")
            }

        case 22998:
            // Real-time trade tick push — this is the gold price data!
            parseTradeTick(json)

        default:
            break
        }
    }

    // MARK: - Parse trade tick

    private func parseTradeTick(_ json: [String: Any]) {
        guard let dataDict = json["data"] as? [String: Any],
              let priceStr = dataDict["price"] as? String,
              let price = Double(priceStr) else {
            return
        }

        let tickTime: Date
        if let tickTimeStr = dataDict["tick_time"] as? String,
           let tickTimeMs = Double(tickTimeStr) {
            tickTime = Date(timeIntervalSince1970: tickTimeMs / 1000.0)
        } else {
            tickTime = Date()
        }

        let result = GoldPriceResult(
            priceUSDPerOunce: price,
            tickTime: tickTime,
            seq: dataDict["seq"] as? String ?? ""
        )

        DispatchQueue.main.async { [weak self] in
            self?.onPriceUpdate?(result)
        }
    }

    // MARK: - Send helper

    private func sendJSON(_ dict: [String: Any], completion: ((Bool) -> Void)? = nil) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else {
            completion?(false)
            return
        }
        webSocketTask?.send(.string(text)) { error in
            completion?(error == nil)
        }
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        guard wantsConnection else { return }
        cancelReconnect()

        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 1.5, maxReconnectDelay)

        let timer = DispatchSource.makeTimerSource(queue: wsQueue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.performConnect()
        }
        timer.resume()
        reconnectTimer = timer
    }

    // MARK: - Cleanup

    private func cancelTimers() {
        cancelHeartbeat()
        cancelReconnect()
    }

    private func cancelHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func cancelReconnect() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }
}

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        // Handled via ping in waitForConnection()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        wsQueue.async { [weak self] in
            guard let self = self else { return }
            self.cancelHeartbeat()
            self.state = .disconnected

            if self.wantsConnection {
                self.scheduleReconnect()
            }
        }
    }
}
