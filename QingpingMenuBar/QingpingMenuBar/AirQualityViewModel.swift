// AirQualityViewModel.swift
// Central state manager for the app. Supports three data sources:
// - Cloud API: polls the Qingping REST API every 60 seconds (requires credentials)
// - BLE: passively scans for device advertisements every ~5-10 seconds (no cloud needed)
// - ESPHome: streams live states from a device running ESPHome firmware over the LAN
// Uses @Observable (not ObservableObject) for Swift 6.2 compatibility.

import Foundation
import SwiftUI
import AppKit
import CoreBluetooth

@Observable
@MainActor
final class AirQualityViewModel {

    // MARK: - Observable State (drives UI updates)

    var reading: AirQualityReading = .placeholder
    var deviceName: String = "—"
    var isLoading: Bool = false
    var errorMessage: String?
    var lastUpdated: Date?

    var co2History: [HistoryPoint] = []
    var pm25History: [HistoryPoint] = []
    var pm10History: [HistoryPoint] = []
    var tempHistory: [HistoryPoint] = []
    var humidityHistory: [HistoryPoint] = []

    var menuBarMetric: MenuBarMetric = MenuBarMetric.from(stored: MenuBarMetricSetting.metric)
    var temperatureUnit: TemperatureUnit = .current
    var isDeviceOffline: Bool = false
    var dataSource: DataSource = DataSource.from(stored: DataSourceSetting.source) {
        didSet { switchDataSource() }
    }
    var bluetoothState: CBManagerState = .unknown

    /// Reading is considered stale if older than 15 minutes (API) or 60 seconds (BLE, ESPHome).
    var isStale: Bool {
        guard reading != .placeholder else { return false }
        let threshold: TimeInterval = dataSource == .cloudAPI ? 900 : 60
        return Date().timeIntervalSince(reading.timestamp) > threshold
    }

    // MARK: - Private (not observed — won't trigger view redraws)

    private var api = QingpingAPIClient()
    private var timer: Timer?
    private let bleScanner = QingpingBLEScanner()
    private let esphome = ESPHomeClient()
    @ObservationIgnored private var deviceMac: String?
    @ObservationIgnored private var hasPushedDeviceSettings = false
    @ObservationIgnored private var lastHistoryFetch: Date = .distantPast
    @ObservationIgnored private var lastBLEHistoryAppend: Date = .distantPast

    // MARK: - Lifecycle

    init() {
        bleScanner.delegate = self
        esphome.onReading = { [weak self] newReading in
            self?.didReceiveLocalReading(newReading, deviceName: nil)
        }
        esphome.onError = { [weak self] message in
            self?.errorMessage = message
        }
        switchDataSource()

        // Restart after wake from sleep
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.dataSource == .cloudAPI {
                    self.api = QingpingAPIClient()
                    self.startPolling()
                } else if self.dataSource == .esphome {
                    // Fresh connection instead of waiting out the dead socket's timeout
                    self.connectESPHome()
                }
                // BLE resumes automatically — CoreBluetooth handles reconnection
            }
        }
    }

    // MARK: - Data Source Switching

    private func switchDataSource() {
        DataSourceSetting.source = dataSource.rawValue

        // Clear history to avoid mixing data from different sources
        clearHistory()

        switch dataSource {
        case .cloudAPI:
            bleScanner.stopScanning()
            esphome.stop()
            api = QingpingAPIClient()
            startPolling()
        case .ble:
            stopPolling()
            esphome.stop()
            errorMessage = nil
            loadBLEHistory()
            bleScanner.startScanning()
        case .esphome:
            stopPolling()
            bleScanner.stopScanning()
            errorMessage = nil
            // Same physical sensor as BLE, so it shares the persisted local history
            loadBLEHistory()
            connectESPHome()
        }
    }

    /// (Re)connects to the ESPHome device with the saved settings.
    func connectESPHome() {
        guard dataSource == .esphome else { return }
        let host = CredentialsStore.esphomeHost ?? ESPHomeSettings.defaultHost
        deviceName = host
        esphome.start(
            host: host,
            username: CredentialsStore.esphomeUsername ?? "",
            password: CredentialsStore.esphomePassword ?? ""
        )
    }

    private func clearHistory() {
        co2History = []
        pm25History = []
        pm10History = []
        tempHistory = []
        humidityHistory = []
        lastHistoryFetch = .distantPast
    }

    // MARK: - Cloud API Polling

    func startPolling() {
        Task { await refresh() }

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: PollSettings.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Fetches the latest reading from the cloud API.
    func refresh() async {
        // In BLE mode, refresh just re-triggers scanning (no API call)
        guard dataSource == .cloudAPI else { return }

        guard let appKey = CredentialsStore.appKey,
              let appSecret = CredentialsStore.appSecret else {
            errorMessage = "No API credentials configured. Open Settings to add them."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let (newReading, device) = try await api.fetchLatestReading(
                appKey: appKey,
                appSecret: appSecret
            )

            reading = newReading
            deviceMac = device.info.mac
            isDeviceOffline = device.info.status?.offline ?? false
            deviceName = device.info.name
                ?? device.info.product?.enName
                ?? device.info.product?.name
                ?? "Qingping Monitor"
            lastUpdated = .now

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false

        // Non-critical tasks — run after UI updates, failures won't show errors
        if reading != .placeholder {
            if !hasPushedDeviceSettings {
                hasPushedDeviceSettings = true
                await pushOptimalDeviceSettings()
            }

            let timeSinceLastFetch = Date().timeIntervalSince(lastHistoryFetch)
            let age = lastUpdated.map { Date().timeIntervalSince($0) } ?? .infinity
            if timeSinceLastFetch > 600 || age > 900 {
                await fetchHistory()
            }
        }
    }

    // MARK: - Cloud API History

    func fetchHistory() async {
        guard let appKey = CredentialsStore.appKey,
              let appSecret = CredentialsStore.appSecret,
              let mac = deviceMac else {
            return
        }

        do {
            let points = try await api.fetchHistory(
                appKey: appKey,
                appSecret: appSecret,
                mac: mac
            )
            lastHistoryFetch = .now

            co2History = points.compactMap { p in
                guard let ts = p.timestamp?.value, let v = p.co2?.value else { return nil }
                return HistoryPoint(timestamp: Date(timeIntervalSince1970: TimeInterval(ts)), value: v)
            }
            pm25History = points.compactMap { p in
                guard let ts = p.timestamp?.value, let v = p.pm25?.value else { return nil }
                return HistoryPoint(timestamp: Date(timeIntervalSince1970: TimeInterval(ts)), value: v)
            }
            pm10History = points.compactMap { p in
                guard let ts = p.timestamp?.value, let v = p.pm10?.value else { return nil }
                return HistoryPoint(timestamp: Date(timeIntervalSince1970: TimeInterval(ts)), value: v)
            }
            tempHistory = points.compactMap { p in
                guard let ts = p.timestamp?.value, let v = p.temperature?.value else { return nil }
                return HistoryPoint(timestamp: Date(timeIntervalSince1970: TimeInterval(ts)), value: v)
            }
            humidityHistory = points.compactMap { p in
                guard let ts = p.timestamp?.value, let v = p.humidity?.value else { return nil }
                return HistoryPoint(timestamp: Date(timeIntervalSince1970: TimeInterval(ts)), value: v)
            }

            let maxPoints = 500
            if co2History.count > maxPoints { co2History = Array(co2History.suffix(maxPoints)) }
            if pm25History.count > maxPoints { pm25History = Array(pm25History.suffix(maxPoints)) }
            if pm10History.count > maxPoints { pm10History = Array(pm10History.suffix(maxPoints)) }
            if tempHistory.count > maxPoints { tempHistory = Array(tempHistory.suffix(maxPoints)) }
            if humidityHistory.count > maxPoints { humidityHistory = Array(humidityHistory.suffix(maxPoints)) }
        } catch {
            // History fetch failed silently — current reading still works
        }
    }

    // MARK: - BLE History (persisted to disk)

    /// Loads BLE history from Application Support on launch.
    private func loadBLEHistory() {
        co2History = HistoryStore.pruned(HistoryStore.load(metric: "co2"))
        pm25History = HistoryStore.pruned(HistoryStore.load(metric: "pm25"))
        pm10History = HistoryStore.pruned(HistoryStore.load(metric: "pm10"))
        tempHistory = HistoryStore.pruned(HistoryStore.load(metric: "temp"))
        humidityHistory = HistoryStore.pruned(HistoryStore.load(metric: "humidity"))
    }

    /// Saves all BLE history arrays to disk.
    private func saveBLEHistory() {
        HistoryStore.save(metric: "co2", points: co2History)
        HistoryStore.save(metric: "pm25", points: pm25History)
        HistoryStore.save(metric: "pm10", points: pm10History)
        HistoryStore.save(metric: "temp", points: tempHistory)
        HistoryStore.save(metric: "humidity", points: humidityHistory)
    }

    /// Appends the current BLE reading to history arrays and persists to disk.
    /// Throttled to once per 30 seconds to avoid excessive writes.
    private func appendBLEHistory(_ reading: AirQualityReading) {
        let now = Date()
        guard now.timeIntervalSince(lastBLEHistoryAppend) >= 30 else { return }
        lastBLEHistoryAppend = now

        let maxPoints = 500
        if let v = reading.co2 {
            co2History.append(HistoryPoint(timestamp: now, value: v))
            if co2History.count > maxPoints { co2History.removeFirst() }
        }
        if let v = reading.pm25 {
            pm25History.append(HistoryPoint(timestamp: now, value: v))
            if pm25History.count > maxPoints { pm25History.removeFirst() }
        }
        if let v = reading.pm10 {
            pm10History.append(HistoryPoint(timestamp: now, value: v))
            if pm10History.count > maxPoints { pm10History.removeFirst() }
        }
        if let v = reading.temperature {
            tempHistory.append(HistoryPoint(timestamp: now, value: v))
            if tempHistory.count > maxPoints { tempHistory.removeFirst() }
        }
        if let v = reading.humidity {
            humidityHistory.append(HistoryPoint(timestamp: now, value: v))
            if humidityHistory.count > maxPoints { humidityHistory.removeFirst() }
        }

        saveBLEHistory()
    }

    /// Applies a live reading from BLE or ESPHome and records it in the local history.
    private func didReceiveLocalReading(_ newReading: AirQualityReading, deviceName name: String?) {
        reading = newReading
        isDeviceOffline = false
        lastUpdated = .now
        errorMessage = nil

        if let name { deviceName = name }

        appendBLEHistory(newReading)
    }

    // MARK: - Device Settings

    private func pushOptimalDeviceSettings() async {
        guard let appKey = CredentialsStore.appKey,
              let appSecret = CredentialsStore.appSecret,
              let mac = deviceMac else { return }

        do {
            try await api.updateDeviceSettings(
                appKey: appKey,
                appSecret: appSecret,
                mac: mac,
                reportInterval: 600,
                collectInterval: 60
            )
        } catch {
            // Device settings push failed — not critical
        }
    }
}

// MARK: - BLE Scanner Delegate

extension AirQualityViewModel: QingpingBLEScannerDelegate {

    func scanner(_ scanner: QingpingBLEScanner, didReceiveReading newReading: AirQualityReading, deviceName name: String?) {
        didReceiveLocalReading(mergedWithCurrent(newReading), deviceName: name)
    }

    /// A packet may carry only some readings (ESPHome's broadcast rotates T/RH + CO2, PM + CO2 and
    /// T/RH + battery), so keep the last known value of anything this one leaves out.
    private func mergedWithCurrent(_ new: AirQualityReading) -> AirQualityReading {
        guard reading != .placeholder else { return new }
        return AirQualityReading(
            timestamp: new.timestamp,
            temperature: new.temperature ?? reading.temperature,
            humidity: new.humidity ?? reading.humidity,
            co2: new.co2 ?? reading.co2,
            pm25: new.pm25 ?? reading.pm25,
            pm10: new.pm10 ?? reading.pm10,
            battery: new.battery ?? reading.battery,
            tvoc: new.tvoc ?? reading.tvoc
        )
    }

    func scanner(_ scanner: QingpingBLEScanner, didUpdateState state: CBManagerState) {
        bluetoothState = state
        switch state {
        case .poweredOff:
            errorMessage = "Bluetooth is turned off."
        case .unauthorized:
            errorMessage = "Bluetooth access not authorized. Check System Settings > Privacy."
        case .unsupported:
            errorMessage = "This Mac does not support Bluetooth Low Energy."
        case .poweredOn:
            errorMessage = nil
        default:
            break
        }
    }
}
