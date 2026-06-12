import Foundation

/// Minimal single-connection-at-a-time HTTP server on localhost.
/// Serves JSON status at GET /, GET /price, GET /health.
final class MiniHTTPServer {

    private let queue = DispatchQueue(label: "com.goldbar.http", qos: .utility)
    private var socketFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var port: UInt16 = 9188
    private var running = false

    func start(port: UInt16) {
        guard !running else { return }
        self.port = port
        running = true
        queue.async { [weak self] in
            self?.runLoop()
        }
    }

    func stop() {
        running = false
        source?.cancel()
        source = nil
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
    }

    // MARK: - Run loop

    private func runLoop() {
        socketFD = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            print("[HTTP] socket() failed: \(errno)")
            running = false; return
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, "0.0.0.0", &addr.sin_addr)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            print("[HTTP] bind(:\(port)) failed: \(errno)")
            Darwin.close(socketFD); socketFD = -1
            running = false; return
        }

        guard Darwin.listen(socketFD, 4) == 0 else {
            print("[HTTP] listen() failed: \(errno)")
            Darwin.close(socketFD); socketFD = -1
            running = false; return
        }

        print("[HTTP] Listening on http://localhost:\(port)")

        while running {
            let clientFD = Darwin.accept(socketFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR { continue }
                break
            }
            handle(clientFD)
            Darwin.close(clientFD)
        }

        Darwin.close(socketFD)
        socketFD = -1
        running = false
    }

    // MARK: - Request handling

    private func handle(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 2048)
        let n = Darwin.read(fd, &buf, buf.count)
        guard n > 0 else { return }

        let request = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        let path = parts[1]

        let (statusCode, body) = response(for: path)
        guard let bodyData = body.data(using: .utf8) else { return }

        let header = """
            HTTP/1.1 \(statusCode) \(statusText(statusCode))\r
            Content-Type: application/json; charset=utf-8\r
            Access-Control-Allow-Origin: *\r
            Connection: close\r
            Content-Length: \(bodyData.count)\r
            \r\n
            """

        guard let headerData = header.data(using: .utf8) else { return }
        var response = Data()
        response.append(headerData)
        response.append(bodyData)

        response.withUnsafeBytes { buf in
            _ = Darwin.write(fd, buf.baseAddress!, response.count)
        }
    }

    private func response(for path: String) -> (Int, String) {
        switch path {
        case "/health":
            return (200, #"{"status":"ok"}"#)
        case "/price":
            let snap = StatusSnapshot.shared.snapshot()
            let gold = snap["gold"] as? [String: Any] ?? [:]
            let data: [String: Any] = ["price": gold]
            return (200, jsonString(data))
        default:
            let data = StatusSnapshot.shared.snapshot()
            return (200, jsonString(data))
        }
    }

    private func jsonString(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }
}
