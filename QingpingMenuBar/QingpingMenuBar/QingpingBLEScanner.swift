// QingpingBLEScanner.swift
// Passive BLE scanner that reads Qingping device advertisements without pairing.
// The CGDN1 (Air Monitor Lite) broadcasts sensor data on service UUID 0xFDCD
// using a TLV (Type-Length-Value) format. Updates arrive every 5-10 seconds.

import Foundation
import CoreBluetooth

/// Delegate protocol for receiving parsed BLE readings.
protocol QingpingBLEScannerDelegate: AnyObject {
    func scanner(_ scanner: QingpingBLEScanner, didReceiveReading reading: AirQualityReading, deviceName: String?)
    func scanner(_ scanner: QingpingBLEScanner, didUpdateState state: CBManagerState)
}

final class QingpingBLEScanner: NSObject {

    weak var delegate: QingpingBLEScannerDelegate?

    private var centralManager: CBCentralManager?
    private static let qingpingServiceUUID = CBUUID(string: "FDCD")

    // CGDN1 device type identifiers (original and newer firmware variant)
    private static let cgdn1DeviceTypes: Set<UInt8> = [0x0E, 0x24]

    // TLV xdata type identifiers
    private enum XDataType: UInt8 {
        case tempHumidity = 0x01
        case battery      = 0x02
        case pm           = 0x12
        case co2          = 0x13
    }

    // MARK: - Lifecycle

    func startScanning() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
        // Scanning starts in centralManagerDidUpdateState once Bluetooth is ready
    }

    func stopScanning() {
        centralManager?.stopScan()
    }

    // MARK: - Parsing

    /// Parses the raw service data from a Qingping BLE advertisement.
    /// Returns nil if the data is malformed or not from a CGDN1 device.
    private func parseAdvertisement(_ data: Data) -> AirQualityReading? {
        // Minimum: 8 byte header + at least 3 bytes for one TLV block
        guard data.count >= 11 else { return nil }

        let deviceType = data[1]
        guard Self.cgdn1DeviceTypes.contains(deviceType) else { return nil }

        var temperature: Double?
        var humidity: Double?
        var co2: Double?
        var pm25: Double?
        var pm10: Double?
        var battery: Double?

        // Parse TLV blocks starting at byte 8
        var offset = 8
        while offset + 2 <= data.count {
            let typeId = data[offset]
            let length = Int(data[offset + 1])
            let payloadStart = offset + 2

            guard payloadStart + length <= data.count else { break }

            let payload = data[payloadStart..<(payloadStart + length)]

            switch XDataType(rawValue: typeId) {
            case .tempHumidity where length == 4:
                // Int16 little-endian temperature (tenths of °C)
                let rawTemp = Int16(payload[payloadStart]) | (Int16(payload[payloadStart + 1]) << 8)
                temperature = Double(rawTemp) / 10.0
                // UInt16 little-endian humidity (tenths of %)
                let rawHumi = UInt16(payload[payloadStart + 2]) | (UInt16(payload[payloadStart + 3]) << 8)
                humidity = Double(rawHumi) / 10.0

            case .battery where length == 1:
                battery = Double(payload[payloadStart])

            case .pm where length == 4:
                let rawPm25 = UInt16(payload[payloadStart]) | (UInt16(payload[payloadStart + 1]) << 8)
                let rawPm10 = UInt16(payload[payloadStart + 2]) | (UInt16(payload[payloadStart + 3]) << 8)
                pm25 = Double(rawPm25)
                pm10 = Double(rawPm10)

            case .co2 where length == 2:
                let rawCo2 = UInt16(payload[payloadStart]) | (UInt16(payload[payloadStart + 1]) << 8)
                co2 = Double(rawCo2)

            default:
                break // Unknown or unexpected-length block — skip
            }

            offset = payloadStart + length
        }

        // Only return a reading if we got at least one sensor value
        guard temperature != nil || co2 != nil || pm25 != nil else { return nil }

        return AirQualityReading(
            timestamp: .now,
            temperature: temperature,
            humidity: humidity,
            co2: co2,
            pm25: pm25,
            pm10: pm10,
            battery: battery,
            tvoc: nil
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension QingpingBLEScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        delegate?.scanner(self, didUpdateState: central.state)

        if central.state == .poweredOn {
            // Scan for Qingping advertisements; allow duplicates so we get
            // continuous updates (the device broadcasts every ~5-10 seconds)
            central.scanForPeripherals(
                withServices: [Self.qingpingServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Extract service data for UUID 0xFDCD
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let data = serviceData[Self.qingpingServiceUUID] else { return }

        guard let reading = parseAdvertisement(data) else { return }

        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String

        delegate?.scanner(self, didReceiveReading: reading, deviceName: name)
    }
}
