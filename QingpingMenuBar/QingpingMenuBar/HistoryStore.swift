// HistoryStore.swift
// Persists BLE history to disk as JSON in Application Support.
// Loaded on launch and saved after each new data point is appended.
// Each metric is stored as a separate file to keep writes small.

import Foundation

enum HistoryStore {

    private static let directory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("QingpingMenuBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Public

    static func load(metric: String) -> [HistoryPoint] {
        let url = directory.appendingPathComponent("\(metric).json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let stored = (try? JSONDecoder().decode([StoredPoint].self, from: data)) ?? []
        return stored.map { HistoryPoint(timestamp: Date(timeIntervalSince1970: $0.ts), value: $0.v) }
    }

    static func save(metric: String, points: [HistoryPoint]) {
        let url = directory.appendingPathComponent("\(metric).json")
        let stored = points.map { StoredPoint(ts: $0.timestamp.timeIntervalSince1970, v: $0.value) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Prunes points older than 24 hours from an array.
    static func pruned(_ points: [HistoryPoint]) -> [HistoryPoint] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return points.filter { $0.timestamp > cutoff }
    }
}

// MARK: - Lightweight Codable wrapper (avoids UUID overhead from HistoryPoint)

private struct StoredPoint: Codable {
    let ts: TimeInterval
    let v: Double
}
