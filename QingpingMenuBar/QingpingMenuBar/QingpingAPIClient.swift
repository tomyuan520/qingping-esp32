// QingpingAPIClient.swift
// Actor-isolated HTTP client for the Qingping (Cleargrass) Cloud API.
// Handles OAuth2 client credentials flow, device data fetching, settings updates,
// and paginated 24h history retrieval. Uses an ephemeral URLSession to avoid
// caching API responses to disk.

import Foundation

actor QingpingAPIClient {

    // MARK: - Endpoints

    private static let tokenURL = URL(string: "https://oauth.cleargrass.com/oauth2/token")!
    private static let devicesURL = URL(string: "https://apis.cleargrass.com/v1/apis/devices")!
    private static let settingsURL = URL(string: "https://apis.cleargrass.com/v1/apis/devices/settings")!
    private static let historyURL = URL(string: "https://apis.cleargrass.com/v1/apis/devices/data")!

    // MARK: - State

    private var cachedToken: String?
    private var tokenExpiry: Date = .distantPast
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = URLSession(configuration: config)
    }


    // MARK: - Public API

    /// Fetches the latest reading from the first device on the account.
    func fetchLatestReading(appKey: String, appSecret: String) async throws -> (AirQualityReading, Device) {
        let token = try await getToken(appKey: appKey, appSecret: appSecret)
        let devices = try await fetchDevices(token: token)

        guard let device = devices.first else {
            throw QingpingError.noDevices
        }

        let reading = mapToReading(device.data)
        return (reading, device)
    }

    /// Updates device reporting and collection intervals.
    func updateDeviceSettings(
        appKey: String,
        appSecret: String,
        mac: String,
        reportInterval: Int,
        collectInterval: Int
    ) async throws {
        let token = try await getToken(appKey: appKey, appSecret: appSecret)

        var components = URLComponents(url: Self.settingsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "mac": [mac],
            "report_interval": reportInterval,
            "collect_interval": collectInterval
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        try validateResponse(response, data: data)
    }

    /// Fetches 24h of historical data, paginating in batches of 200 points.
    /// Capped at 20 pages (4000 points) as a safety limit.
    func fetchHistory(appKey: String, appSecret: String, mac: String) async throws -> [HistoryDataPoint] {
        let token = try await getToken(appKey: appKey, appSecret: appSecret)

        let endTime = Int(Date().timeIntervalSince1970)
        let startTime = endTime - (24 * 3600)
        var allPoints: [HistoryDataPoint] = []
        var currentStart = startTime

        let maxPages = 20
        var page = 0
        while currentStart < endTime, page < maxPages {
            page += 1
            var components = URLComponents(url: Self.historyURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "mac", value: mac),
                URLQueryItem(name: "start_time", value: String(currentStart)),
                URLQueryItem(name: "end_time", value: String(endTime)),
                URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000))),
                URLQueryItem(name: "limit", value: "200"),
            ]

            var request = URLRequest(url: components.url!, timeoutInterval: 30)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)

            let historyResponse = try JSONDecoder().decode(HistoryResponse.self, from: data)

            guard let points = historyResponse.data, !points.isEmpty else {
                break
            }

            allPoints.append(contentsOf: points)

            // Fewer than 200 means we've reached the end of available data
            if points.count < 200 {
                break
            }

            // Advance past the last returned timestamp to fetch the next page
            if let lastTimestamp = points.last?.timestamp?.value {
                currentStart = lastTimestamp + 1
            } else {
                break
            }
        }

        return allPoints
    }

    // MARK: - OAuth Token

    /// Returns a cached token if still valid, otherwise fetches a new one.
    /// Uses HTTP Basic auth with base64-encoded appKey:appSecret.
    private func getToken(appKey: String, appSecret: String) async throws -> String {
        // Return cached token if it won't expire in the next 60 seconds
        if let token = cachedToken, tokenExpiry > Date().addingTimeInterval(60) {
            return token
        }
        // Clear expired token from memory
        cachedToken = nil

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"

        let credentials = "\(appKey):\(appSecret)"
        guard let credData = credentials.data(using: .utf8) else {
            throw QingpingError.invalidCredentials
        }
        let base64Creds = credData.base64EncodedString()
        request.setValue("Basic \(base64Creds)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=client_credentials&scope=device_full_access"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

        cachedToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        return tokenResponse.accessToken
    }

    // MARK: - Devices

    private func fetchDevices(token: String) async throws -> [Device] {
        var components = URLComponents(url: Self.devicesURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            let deviceResponse = try JSONDecoder().decode(DeviceListResponse.self, from: data)
            return deviceResponse.devices
        } catch {
            throw QingpingError.decodingFailed(detail: String(describing: error))
        }
    }

    // MARK: - Helpers

    /// Validates that the response is a successful HTTP status (2xx).
    private func validateResponse(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw QingpingError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            // Store body for debugging but don't expose it in user-facing error messages
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
            throw QingpingError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    /// Converts raw DeviceData into a flat AirQualityReading for the UI.
    private func mapToReading(_ data: DeviceData) -> AirQualityReading {
        let date: Date
        if let ts = data.timestamp?.value {
            date = Date(timeIntervalSince1970: TimeInterval(ts))
        } else {
            date = .now
        }

        return AirQualityReading(
            timestamp: date,
            temperature: data.temperature?.value,
            humidity: data.humidity?.value,
            co2: data.co2?.value,
            pm25: data.pm25?.value,
            pm10: data.pm10?.value,
            battery: data.battery?.value,
            tvoc: data.tvoc?.value
        )
    }
}

// MARK: - Errors

/// API errors with user-friendly descriptions. The HTTP error intentionally
/// hides the response body from the user to avoid leaking internal API details.
nonisolated enum QingpingError: LocalizedError, Sendable {
    case invalidCredentials
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case noDevices
    case decodingFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid API credentials."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .httpError(let code, _):
            return "Qingping API request failed (HTTP \(code))."
        case .noDevices:
            return "No devices found on your Qingping account."
        case .decodingFailed(let detail):
            return "Failed to parse API response: \(detail)"
        }
    }
}
