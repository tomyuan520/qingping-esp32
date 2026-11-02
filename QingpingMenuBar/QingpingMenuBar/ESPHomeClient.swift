// ESPHomeClient.swift
// Streams live sensor states from a CGDN1 running ESPHome firmware, which sends neither the
// stock BLE advertisements nor uploads to the Qingping cloud. Reads the ESPHome web_server's
// Server-Sent Events stream (`/events`): on connect it sends every entity's state, then one
// "state" event per sensor update, e.g. data: {"id":"sensor/CO2","value":840,"state":"840 ppm"}.
// Reconnects by itself after errors. Login (basic or digest) is answered via a task delegate.

import Foundation

final class ESPHomeClient {

    /// Called with the merged reading after each sensor update.
    var onReading: ((AirQualityReading) -> Void)?
    /// Called with a user-facing message on failure, or nil once connected.
    var onError: ((String?) -> Void)?

    private var task: Task<Void, Never>?

    // Latest value per sensor; events arrive one sensor at a time
    private var temperature: Double?
    private var humidity: Double?
    private var co2: Double?
    private var pm25: Double?
    private var pm10: Double?
    private var battery: Double?

    private static let retryDelay: Duration = .seconds(5)

    // MARK: - Lifecycle

    func start(host: String, username: String, password: String) {
        stop()
        task = Task { [weak self] in
            await self?.run(host: host, username: username, password: password)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Stream

    private func run(host: String, username: String, password: String) async {
        guard let url = URL(string: "http://\(host)/events") else {
            onError?("Invalid ESPHome host \"\(host)\".")
            return
        }

        let config = URLSessionConfiguration.ephemeral
        // The device pings every 30 s, so a quiet minute means the stream is dead
        config.timeoutIntervalForRequest = 90
        config.timeoutIntervalForResource = .infinity
        let session = URLSession(configuration: config)
        let delegate = ESPHomeAuthDelegate(
            host: url.host() ?? host,
            port: url.port ?? 80,
            username: username,
            password: password
        )
        defer { session.invalidateAndCancel() }

        while !Task.isCancelled {
            do {
                try await stream(url: url, session: session, delegate: delegate)
                onError?("Lost connection to \(host).")
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                onError?(Self.message(for: error, host: host))
            }
            try? await Task.sleep(for: Self.retryDelay)
        }
    }

    private func stream(url: URL, session: URLSession, delegate: ESPHomeAuthDelegate) async throws {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        guard let http = response as? HTTPURLResponse else {
            throw ESPHomeError.invalidResponse
        }
        guard http.statusCode != 401 else { throw ESPHomeError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw ESPHomeError.httpError(statusCode: http.statusCode)
        }
        onError?(nil)

        // `lines` drops blank lines, so dispatch on each "data:" line instead of on the
        // blank line that ends an event; ESPHome sends single-line data.
        var event = "message"
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                if event == "state" {
                    apply(Data(line.dropFirst(5).utf8))
                }
                event = "message"
            }
        }
    }

    // MARK: - Parsing

    /// Updates one sensor from a "state" event and publishes the merged reading.
    private func apply(_ json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let id = object["id"] as? String else { return }
        // A sensor with no reading yet sends "value": null (state "NA")
        let value = object["value"] as? Double

        switch id {
        case "sensor/CO2":           co2 = value
        case "sensor/PM2.5":         pm25 = value
        case "sensor/PM10":          pm10 = value
        case "sensor/Temperature":   temperature = value
        case "sensor/Humidity":      humidity = value
        case "sensor/Battery level": battery = value
        default: return // Other entities (diagnostics, switches, ...) aren't shown
        }

        onReading?(AirQualityReading(
            timestamp: .now,
            temperature: temperature,
            humidity: humidity,
            co2: co2,
            pm25: pm25,
            pm10: pm10,
            battery: battery,
            tvoc: nil
        ))
    }

    private static func message(for error: Error, host: String) -> String {
        if let error = error as? ESPHomeError {
            return error.localizedDescription
        }
        if let error = error as? URLError {
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "Can't find \(host) on this network."
            case .cannotConnectToHost, .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return "Can't reach \(host)."
            default:
                break
            }
        }
        return "ESPHome connection failed: \(error.localizedDescription)"
    }
}

// MARK: - Login

/// Answers the web_server's basic or digest login challenge once, and only for the configured
/// host and port; a rejected login falls through to the 401 response, which `stream` reports.
/// Redirects are refused so the login can't be sent anywhere else. The web_server is plain
/// HTTP: a basic login is readable on the network, a digest login is not.
nonisolated final class ESPHomeAuthDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let host: String
    let port: Int
    let username: String
    let password: String

    init(host: String, port: Int, username: String, password: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        let method = space.authenticationMethod
        // Digest only: the connection is plain HTTP, so answering a Basic challenge would hand the
        // password (base64) to anything that answers as the device. The CGDN1 dashboard uses digest.
        guard method == NSURLAuthenticationMethodHTTPDigest,
              space.host.caseInsensitiveCompare(host) == .orderedSame, space.port == port,
              challenge.previousFailureCount == 0, !username.isEmpty else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(user: username, password: password, persistence: .forSession))
    }

    // Completion-handler form: the async variant crashes the Swift 6.2 compiler (SILGen
    // emitNativeToForeignThunk) in this nonisolated NSObject subclass.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

// MARK: - Errors

nonisolated enum ESPHomeError: LocalizedError, Sendable {
    case unauthorized
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "ESPHome login rejected. Check the username and password in Settings."
        case .invalidResponse:
            return "Received an invalid response from the device."
        case .httpError(let code):
            return "ESPHome request failed (HTTP \(code))."
        }
    }
}
