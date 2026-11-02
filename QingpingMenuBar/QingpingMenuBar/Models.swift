// Models.swift
// Codable data models matching the Qingping Cloud API JSON responses, plus
// app-level types used for UI display (AirQualityReading, HistoryPoint).
// All types are `nonisolated` and `Sendable` so they can cross actor boundaries
// freely (the API client is its own actor, the UI is MainActor).

import Foundation

// MARK: - OAuth Token Response

nonisolated struct OAuthTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - Device List Response

nonisolated struct DeviceListResponse: Codable, Sendable {
    let total: Int?
    let devices: [Device]
}

nonisolated struct Device: Codable, Identifiable, Sendable {
    let info: DeviceInfo
    let data: DeviceData

    var id: String { info.mac }
}

nonisolated struct DeviceInfo: Codable, Sendable {
    let mac: String
    let product: ProductInfo?
    let name: String?
    let version: String?
    let createdAt: Int?
    let status: DeviceStatus?
    let connectionType: String?

    enum CodingKeys: String, CodingKey {
        case mac, product, name, version, status
        case createdAt = "created_at"
        case connectionType = "connection_type"
    }
}

nonisolated struct DeviceStatus: Codable, Sendable {
    let offline: Bool?
}

nonisolated struct ProductInfo: Codable, Sendable {
    let id: Int?
    let code: String?
    let name: String?
    let enName: String?

    enum CodingKeys: String, CodingKey {
        case id, code, name
        case enName = "en_name"
    }
}

/// Raw sensor data from the device. Each field is wrapped in SensorValue
/// because the API returns `{ "value": 21.1 }` rather than bare numbers.
nonisolated struct DeviceData: Codable, Sendable {
    let timestamp: SensorValue<Int>?
    let battery: SensorValue<Double>?
    let temperature: SensorValue<Double>?
    let humidity: SensorValue<Double>?
    let co2: SensorValue<Double>?
    let pm25: SensorValue<Double>?
    let pm10: SensorValue<Double>?
    let tvoc: SensorValue<Double>?
}

/// Generic wrapper for the API's `{ "value": T }` pattern.
nonisolated struct SensorValue<T: Codable & Sendable>: Codable, Sendable {
    let value: T
}

// MARK: - History Response

nonisolated struct HistoryResponse: Codable, Sendable {
    let total: Int?
    let data: [HistoryDataPoint]?
}

nonisolated struct HistoryDataPoint: Codable, Sendable {
    let timestamp: SensorValue<Int>?
    let temperature: SensorValue<Double>?
    let humidity: SensorValue<Double>?
    let co2: SensorValue<Double>?
    let pm25: SensorValue<Double>?
    let pm10: SensorValue<Double>?
}

// MARK: - Unified Reading

/// Flattened representation of a single device reading, used by the UI layer.
nonisolated struct AirQualityReading: Equatable, Sendable {
    let timestamp: Date
    let temperature: Double?
    let humidity: Double?
    let co2: Double?
    let pm25: Double?
    let pm10: Double?
    let battery: Double?
    let tvoc: Double?

    /// Empty reading used before any data is fetched.
    static let placeholder = AirQualityReading(
        timestamp: .now,
        temperature: nil,
        humidity: nil,
        co2: nil,
        pm25: nil,
        pm10: nil,
        battery: nil,
        tvoc: nil
    )
}

// MARK: - History Point (for charts)

/// A single data point for sparkline and expanded charts.
/// Equality ignores `id` so two points with the same timestamp+value are equal.
nonisolated struct HistoryPoint: Identifiable, Equatable, Sendable {
    let id = UUID()
    let timestamp: Date
    let value: Double

    static func == (lhs: HistoryPoint, rhs: HistoryPoint) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.value == rhs.value
    }
}
