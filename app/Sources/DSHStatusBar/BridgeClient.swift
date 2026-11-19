import Foundation

/// 与 DSH Host 桥通信：轮询 bridge.json → SSE 状态流 → 命令 POST。
/// 所有 UI 回调都在主线程。
final class BridgeClient: NSObject {
    var onState: ((BridgeState) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?
    var onLog: ((String) -> Void)?

    private let bridgeFile: URL
    private var bridgeInfo: BridgeInfo?
    private var session: URLSession?
    private var streamTask: URLSessionDataTask?
    private var pollTimer: Timer?
    private var watchdogTimer: Timer?
    private var retryTimer: Timer?

    private var buffer = Data()
    private var eventName: String?
    private var dataLines: [String] = []
    private var lastEventAt = Date.distantPast
    private var isConnected = false
    private var reconnectDelay: TimeInterval = 0.5
    private var reconnectScheduled = false
    private var started = false
    private var pendingCommands: [CommandRequest] = []

    init(bridgeFile: URL) {
        self.bridgeFile = bridgeFile
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: AppConfig.pollInterval, repeats: true) { [weak self] _ in
            self?.refreshBridgeFile()
        }
        pollTimer?.tolerance = 0.4
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.watchdog()
        }
        watchdogTimer?.tolerance = 0.5
        refreshBridgeFile()
    }

    func stop() {
        started = false
        pollTimer?.invalidate(); pollTimer = nil
        watchdogTimer?.invalidate(); watchdogTimer = nil
        retryTimer?.invalidate(); retryTimer = nil
        cancelStream()
        session?.invalidateAndCancel(); session = nil
        setConnected(false)
    }

    // MARK: - bridge.json 轮询

    private func refreshBridgeFile() {
        guard started else { return }
        guard let data = try? Data(contentsOf: bridgeFile),
              let info = try? JSONDecoder().decode(BridgeInfo.self, from: data) else {
            if bridgeInfo != nil {
                bridgeInfo = nil
                cancelStream()
                setConnected(false)
                log("bridge.json 消失")
            }
            return
        }
        if let current = bridgeInfo, current == info {
            if !isConnected && streamTask == nil { connect() }
            return
        }
        bridgeInfo = info
        log("发现桥：\(info.origin)")
        connect()
    }

    private func connect() {
        guard started, let info = bridgeInfo else { return }
        cancelStream()
        guard let url = URL(string: "\(info.origin)/dsh-status/stream") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(info.token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.timeoutInterval = 60

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 86_400
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = newSession
        buffer.removeAll()
        eventName = nil
        dataLines.removeAll()
        lastEventAt = Date()
        let task = newSession.dataTask(with: request)
        streamTask = task
        task.resume()
        fetchInitialState(info: info)
    }

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func fetchInitialState(info: BridgeInfo) {
        guard let url = URL(string: "\(info.origin)/dsh-status/state") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(info.token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            if let error { self.log("state 拉取失败：\(error.localizedDescription)"); return }
            guard let data, let state = try? JSONDecoder().decode(BridgeState.self, from: data) else { return }
            DispatchQueue.main.async {
                self.onState?(state)
                self.setConnected(true)
                self.lastEventAt = Date()
            }
        }.resume()
    }

    private func scheduleReconnect() {
        guard started, !reconnectScheduled else { return }
        reconnectScheduled = true
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 5.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.reconnectScheduled = false
            guard self.started, self.bridgeInfo != nil, self.streamTask == nil else { return }
            self.connect()
        }
    }

    private func watchdog() {
        guard started, isConnected else { return }
        if Date().timeIntervalSince(lastEventAt) > AppConfig.staleAfter {
            setConnected(false)
            log("SSE 超时，重连")
            cancelStream()
            scheduleReconnect()
        }
    }

    private func setConnected(_ value: Bool) {
        guard isConnected != value else { return }
        isConnected = value
        onConnectionChange?(value)
        if value {
            reconnectDelay = 0.5
            flushPendingCommands()
        }
    }

    // MARK: - 命令

    /// 让 Host 删掉焦点会话的临时「已完成」行（面板行尾 × 触发）；不经过队列，失败只记日志。
    func dismissSession(_ sessionId: String) {
        guard let info = bridgeInfo,
              let url = URL(string: "\(info.origin)/dsh-status/command") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(info.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(CommandRequest(type: "dismiss", sessionId: sessionId))
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error == nil, (200..<300).contains(status) { return }
            DispatchQueue.main.async {
                self?.log("忽略失败（\(status)），可再点一次")
            }
        }.resume()
    }

    func sendOpenSession(_ sessionId: String) {
        let command = CommandRequest(type: "openSession", sessionId: sessionId)
        pendingCommands.append(command)
        flushPendingCommands()
        scheduleCommandRetryIfNeeded()
    }

    private func flushPendingCommands() {
        guard isConnected, let info = bridgeInfo, !pendingCommands.isEmpty else { return }
        guard let url = URL(string: "\(info.origin)/dsh-status/command") else { return }
        let batch = pendingCommands
        pendingCommands.removeAll()
        for command in batch {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(info.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(command)
            request.timeoutInterval = 5
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                DispatchQueue.main.async {
                    if error != nil || !(200..<300).contains(status) {
                        self.log("命令发送失败（\(status)），稍后重试")
                        self.pendingCommands.append(command)
                        self.scheduleCommandRetryIfNeeded()
                    } else {
                        self.log("已发送 openSession(\(command.sessionId))")
                    }
                }
            }.resume()
        }
    }

    private func scheduleCommandRetryIfNeeded() {
        guard !pendingCommands.isEmpty, retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.pendingCommands.isEmpty {
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                return
            }
            self.flushPendingCommands()
        }
    }

    // MARK: - SSE 解析

    private func ingest(_ data: Data) {
        lastEventAt = Date()
        buffer.append(data)
        while let range = buffer.range(of: Data("\n\n".utf8)) {
            let chunk = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard let text = String(data: chunk, encoding: .utf8) else { continue }
            parseEvent(text)
        }
    }

    private func parseEvent(_ text: String) {
        var name: String?
        var payload: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).replacingOccurrences(of: "\r", with: "")
            if line.hasPrefix(":") { continue } // 注释 / 心跳
            if line.hasPrefix("event:") {
                name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                payload.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }
        guard let name, !payload.isEmpty else { return }
        let json = payload.joined(separator: "\n")
        guard let data = json.data(using: .utf8) else { return }
        switch name {
        case "state":
            if let state = try? JSONDecoder().decode(BridgeState.self, from: data) {
                DispatchQueue.main.async {
                    self.onState?(state)
                    self.setConnected(true)
                }
            }
        default:
            break
        }
    }

    private func log(_ message: String) {
        onLog?(message)
    }
}

// MARK: - URLSessionDataDelegate

extension BridgeClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        ingest(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.started else { return }
            self.streamTask = nil
            self.setConnected(false)
            if let error, (error as NSError).code != NSURLErrorCancelled {
                self.log("SSE 断开：\(error.localizedDescription)")
            }
            self.scheduleReconnect()
        }
    }
}
