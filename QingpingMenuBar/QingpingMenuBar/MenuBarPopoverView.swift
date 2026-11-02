// MenuBarPopoverView.swift
// The main popover UI shown when the user clicks the menu bar icon.
// Contains the header (device name, battery, staleness), sensor rows with sparklines,
// expandable Swift Charts detail views, settings panel, and footer controls.
// Also defines supporting types: SensorRow, ExpandedChartView, SparklineView,
// Trend, MenuBarMetric, TemperatureUnit, and their UserDefaults-backed settings.

import SwiftUI
import ServiceManagement
import Charts

struct MenuBarPopoverView: View {
    var viewModel: AirQualityViewModel
    @State private var showSettings: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            if let error = viewModel.errorMessage {
                errorBanner(error)
                    .padding(16)
            }

            if viewModel.reading != .placeholder || viewModel.errorMessage == nil {
                sensorList
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            if showSettings {
                settingsSection
                    .padding(16)
            }

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(viewModel.deviceName)
                        .font(.headline)
                    if let battery = viewModel.reading.battery {
                        HStack(spacing: 2) {
                            Image(systemName: batteryIcon(battery))
                                .font(.caption2)
                            Text("\(Int(battery))%")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                if viewModel.isDeviceOffline {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                            .font(.caption2)
                        Text("Device offline")
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                } else if viewModel.reading != .placeholder {
                    HStack(spacing: 4) {
                        if viewModel.isStale {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                        Text("\(viewModel.reading.timestamp, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(viewModel.isStale ? .yellow : .secondary)
                    }
                }
            }
            Spacer()
            overallBadge
        }
    }

    private var overallBadge: some View {
        let level = AirQualityThresholds.overallLevel(reading: viewModel.reading)
        return HStack(spacing: 4) {
            Image(systemName: level.systemImage)
            Text(level.rawValue)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(level.color)
    }

    // MARK: - Sensor List with Sparklines

    private var sensorList: some View {
        VStack(spacing: 6) {
            if let co2 = viewModel.reading.co2 {
                SensorRow(
                    title: "CO₂", icon: "carbon.dioxide.cloud",
                    value: "\(Int(co2))", unit: "ppm",
                    level: AirQualityThresholds.co2Level(co2),
                    history: viewModel.co2History,
                    thresholdColor: { AirQualityThresholds.co2Level($0).color }
                )
            }
            if let pm25 = viewModel.reading.pm25 {
                SensorRow(
                    title: "PM2.5", icon: "aqi.medium",
                    value: String(format: "%.0f", pm25), unit: "µg/m³",
                    level: AirQualityThresholds.pm25Level(pm25),
                    history: viewModel.pm25History,
                    thresholdColor: { AirQualityThresholds.pm25Level($0).color }
                )
            }
            if let pm10 = viewModel.reading.pm10 {
                SensorRow(
                    title: "PM10", icon: "aqi.low",
                    value: String(format: "%.0f", pm10), unit: "µg/m³",
                    level: AirQualityThresholds.pm10Level(pm10),
                    history: viewModel.pm10History,
                    thresholdColor: { AirQualityThresholds.pm10Level($0).color }
                )
            }
            if let temp = viewModel.reading.temperature {
                let unit = viewModel.temperatureUnit
                SensorRow(
                    title: "Temp", icon: "thermometer.medium",
                    value: String(format: "%.1f", unit.convert(temp)), unit: unit.symbol,
                    level: AirQualityThresholds.temperatureLevel(temp),
                    history: viewModel.tempHistory,
                    thresholdColor: { AirQualityThresholds.temperatureLevel($0).color }
                )
            }
            if let humidity = viewModel.reading.humidity {
                SensorRow(
                    title: "Humidity", icon: "humidity",
                    value: String(format: "%.0f", humidity), unit: "%",
                    level: AirQualityThresholds.humidityLevel(humidity),
                    history: viewModel.humidityHistory,
                    thresholdColor: { AirQualityThresholds.humidityLevel($0).color }
                )
            }
        }
    }

    private func batteryIcon(_ percent: Double) -> String {
        switch percent {
        case ..<25:  return "battery.25percent"
        case ..<50:  return "battery.50percent"
        case ..<75:  return "battery.75percent"
        default:     return "battery.100percent"
        }
    }

    // MARK: - Settings Section

    @State private var appKey: String = CredentialsStore.appKey ?? ""
    @State private var appSecret: String = CredentialsStore.appSecret ?? ""
    @State private var saved: Bool = false
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var editingCredentials: Bool = false
    @State private var selectedMetric: MenuBarMetric = MenuBarMetric.from(stored: MenuBarMetricSetting.metric)
    @State private var selectedTempUnit: TemperatureUnit = .current
    @State private var selectedDataSource: DataSource = DataSource.from(stored: DataSourceSetting.source)
    @State private var esphomeHost: String = CredentialsStore.esphomeHost ?? ESPHomeSettings.defaultHost
    @State private var esphomeUsername: String = CredentialsStore.esphomeUsername ?? ""
    @State private var esphomePassword: String = CredentialsStore.esphomePassword ?? ""

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Data source
            HStack {
                Text("Data Source")
                    .font(.caption)
                Spacer()
                Picker("Data Source", selection: $selectedDataSource) {
                    ForEach(DataSource.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .labelsHidden()
                .font(.caption)
            }
            .onChange(of: selectedDataSource) { _, newValue in
                viewModel.dataSource = newValue
            }

            // Credentials (only shown in Cloud API mode)
            if selectedDataSource == .cloudAPI, CredentialsStore.hasCredentials && !editingCredentials {
                HStack {
                    Label("API connected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Edit") {
                        editingCredentials = true
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            } else if selectedDataSource == .cloudAPI {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Credentials")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("App Key", text: $appKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    SecureField("App Secret", text: $appSecret)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    HStack {
                        Button("Save") {
                            CredentialsStore.appKey = appKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            CredentialsStore.appSecret = appSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                            editingCredentials = false
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }
                        .font(.caption)
                        .disabled(appKey.isEmpty || appSecret.isEmpty)

                        if CredentialsStore.hasCredentials {
                            Button("Cancel") {
                                appKey = CredentialsStore.appKey ?? ""
                                appSecret = CredentialsStore.appSecret ?? ""
                                editingCredentials = false
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }

                        if saved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            } else if selectedDataSource == .esphome {
                // ESPHome web_server connection (only shown in Local mode)
                VStack(alignment: .leading, spacing: 6) {
                    Text("ESPHome Dashboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Host", text: $esphomeHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    TextField("Username", text: $esphomeUsername)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    SecureField("Password", text: $esphomePassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    HStack {
                        Button("Save") {
                            CredentialsStore.esphomeHost = esphomeHost.trimmingCharacters(in: .whitespacesAndNewlines)
                            CredentialsStore.esphomeUsername = esphomeUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                            CredentialsStore.esphomePassword = esphomePassword
                            viewModel.connectESPHome()
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                        }
                        .font(.caption)
                        .disabled(esphomeHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if saved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }
            }

            // Menu bar metric
            HStack {
                Text("Menu Bar Metric")
                    .font(.caption)
                Spacer()
                Picker("Menu Bar Metric", selection: $selectedMetric) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        Text(metric.label(unit: viewModel.temperatureUnit)).tag(metric)
                    }
                }
                .labelsHidden()
                .font(.caption)
            }
            .onChange(of: selectedMetric) { _, newValue in
                MenuBarMetricSetting.metric = newValue.rawValue
                viewModel.menuBarMetric = newValue
            }

            // Temperature unit
            HStack {
                Text("Temperature")
                    .font(.caption)
                Spacer()
                Picker("Temperature", selection: $selectedTempUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .font(.caption)
            }
            .onChange(of: selectedTempUnit) { _, newValue in
                TemperatureUnitSetting.unit = newValue.rawValue
                viewModel.temperatureUnit = newValue
            }

            // Launch at login
            HStack {
                Text("Launch at login")
                    .font(.caption)
                Spacer()
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Launch at login toggle failed — revert UI
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if viewModel.dataSource == .cloudAPI {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
            } else {
                // Live-stream indicator (BLE and ESPHome)
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.caption2)
                    Text("Live")
                        .font(.caption)
                }
                .foregroundStyle(.green)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettings.toggle()
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()
                .frame(width: 12)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

// MARK: - Sensor Row with Sparkline

/// A single metric row showing title, value, trend arrow, and a sparkline.
/// Tapping expands it to show an interactive Swift Charts detail view.
struct SensorRow: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let level: QualityLevel
    let history: [HistoryPoint]
    let thresholdColor: (Double) -> Color

    @State private var expanded = false

    private var trend: Trend {
        Trend.from(history: history)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value)
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(level.color)
                        Text(unit)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if trend != .stable {
                            Image(systemName: trend.systemImage)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(trend.color(for: level))
                        }
                    }
                }
                .frame(maxWidth: expanded ? .infinity : 110, alignment: .leading)

                if !expanded, history.count >= 2 {
                    SparklineView(points: history, thresholdColor: thresholdColor)
                        .frame(height: 32)
                        .frame(maxWidth: .infinity)
                } else if !expanded {
                    Spacer()
                }
            }

            if expanded && history.count >= 2 {
                ExpandedChartView(points: history, unit: unit, thresholdColor: thresholdColor)
                    .frame(height: 120)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                expanded.toggle()
            }
        }
    }
}

// MARK: - Expanded Chart View

/// Interactive 24h chart using Swift Charts. Shows threshold-colored line segments
/// with Catmull-Rom interpolation and a hover cursor with tooltip annotation.
struct ExpandedChartView: View {
    let points: [HistoryPoint]
    let unit: String
    let thresholdColor: (Double) -> Color

    @State private var selectedPoint: HistoryPoint?

    private var yMin: Double {
        let values = points.map(\.value)
        let dataMin = values.min() ?? 0
        let dataMax = values.max() ?? 1
        let pad = max((dataMax - dataMin) * 0.1, 1)
        return max(0, dataMin - pad)
    }

    private var yMax: Double {
        let values = points.map(\.value)
        let dataMin = values.min() ?? 0
        let dataMax = values.max() ?? 1
        let pad = max((dataMax - dataMin) * 0.1, 1)
        return dataMax + pad
    }

    /// Splits points into runs of the same threshold color. Adjacent segments overlap
    /// by one point so the line appears continuous across color transitions.
    private var segments: [ChartSegment] {
        guard points.count >= 2 else { return [] }
        var result: [ChartSegment] = []
        var currentColor = thresholdColor(points[0].value)
        var currentPoints = [points[0]]

        for i in 1..<points.count {
            let color = thresholdColor(points[i].value)
            if color != currentColor {
                result.append(ChartSegment(color: currentColor, points: currentPoints))
                currentColor = color
                currentPoints = [points[i - 1]]
            }
            currentPoints.append(points[i])
        }
        result.append(ChartSegment(color: currentColor, points: currentPoints))
        return result
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
            ForEach(segment.points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value),
                    series: .value("Segment", idx)
                )
                .foregroundStyle(segment.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
        }
    }

    @ChartContentBuilder
    private var cursorMarks: some ChartContent {
        if let selected = selectedPoint {
            PointMark(
                x: .value("Time", selected.timestamp),
                y: .value("Value", selected.value)
            )
            .foregroundStyle(thresholdColor(selected.value))
            .symbolSize(30)
        }
    }

    private func annotationLabel(for point: HistoryPoint) -> some View {
        VStack(spacing: 2) {
            Text(point.timestamp, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
            Text("\(formatValue(point.value)) \(unit)")
                .fontWeight(.semibold)
                .foregroundStyle(thresholdColor(point.value))
        }
        .font(.system(size: 9).monospacedDigit())
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
    }

    var body: some View {
        Chart {
            lineMarks
            cursorMarks
        }
        .tint(.primary)
        .chartYScale(domain: yMin ... yMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.system(size: 8))
                            .foregroundColor(.primary.opacity(0.5))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let num = value.as(Double.self) {
                        Text(formatValue(num))
                            .font(.system(size: 8))
                            .foregroundColor(.primary.opacity(0.5))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geo[plotFrame].origin
                                let x = location.x - origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedPoint = closestPoint(to: date)
                                }
                            case .ended:
                                selectedPoint = nil
                            }
                        }

                    if let selected = selectedPoint,
                       let plotFrame = proxy.plotFrame {
                        let frame = geo[plotFrame]
                        if let xPos: CGFloat = proxy.position(forX: selected.timestamp) {
                            // Dashed vertical line
                            Path { path in
                                path.move(to: CGPoint(x: frame.origin.x + xPos, y: frame.origin.y))
                                path.addLine(to: CGPoint(x: frame.origin.x + xPos, y: frame.origin.y + frame.height))
                            }
                            .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

                            // Annotation tooltip
                            annotationLabel(for: selected)
                                .position(x: frame.origin.x + xPos, y: frame.origin.y - 4)
                        }
                    }
                }
            }
        }
    }

    private func closestPoint(to date: Date) -> HistoryPoint? {
        points.min(by: { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) })
    }

    private func formatValue(_ value: Double) -> String {
        if abs(value) >= 100 {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.1f", value)
        }
    }
}

/// A contiguous run of history points sharing the same threshold color.
nonisolated struct ChartSegment {
    let color: Color
    let points: [HistoryPoint]
}

// MARK: - Sparkline View

/// Compact line chart using Swift Charts with threshold-colored segments
/// and Catmull-Rom interpolation for smooth curves. No axes — just the line.
struct SparklineView: View {
    let points: [HistoryPoint]
    let thresholdColor: (Double) -> Color

    private var yMin: Double {
        let values = points.map(\.value)
        let dataMin = values.min() ?? 0
        let dataMax = values.max() ?? 1
        let pad = max((dataMax - dataMin) * 0.3, 1)
        return max(0, dataMin - pad)
    }

    private var yMax: Double {
        let values = points.map(\.value)
        let dataMin = values.min() ?? 0
        let dataMax = values.max() ?? 1
        let pad = max((dataMax - dataMin) * 0.3, 1)
        return dataMax + pad
    }

    private var segments: [ChartSegment] {
        guard points.count >= 2 else { return [] }
        var result: [ChartSegment] = []
        var currentColor = thresholdColor(points[0].value)
        var currentPoints = [points[0]]

        for i in 1..<points.count {
            let color = thresholdColor(points[i].value)
            if color != currentColor {
                result.append(ChartSegment(color: currentColor, points: currentPoints))
                currentColor = color
                currentPoints = [points[i - 1]]
            }
            currentPoints.append(points[i])
        }
        result.append(ChartSegment(color: currentColor, points: currentPoints))
        return result
    }

    var body: some View {
        Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                ForEach(segment.points) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value),
                        series: .value("Segment", idx)
                    )
                    .foregroundStyle(segment.color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yMin ... yMax)
    }
}

// MARK: - Trend

/// Indicates whether a metric is rising, falling, or stable over the last hour.
/// Compares the average of the most recent hour to the average of the prior hours.
nonisolated enum Trend {
    case rising
    case falling
    case stable

    var systemImage: String {
        switch self {
        case .rising:  return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable:  return ""
        }
    }

    func color(for level: QualityLevel) -> Color {
        switch (self, level) {
        case (.falling, .good), (.falling, .moderate):
            return .green   // falling toward good
        case (.rising, .poor), (.rising, .veryPoor):
            return .red     // rising toward worse
        default:
            return .secondary
        }
    }

    /// Compare the average of the last hour to the average of the hour before that.
    /// Requires at least 2 points. Uses a 5% threshold to avoid noise.
    static func from(history: [HistoryPoint]) -> Trend {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let recentPoints = history.filter { $0.timestamp >= oneHourAgo }
        let olderPoints = history.filter { $0.timestamp < oneHourAgo }

        guard !recentPoints.isEmpty, !olderPoints.isEmpty else { return .stable }

        let recentAvg = recentPoints.map(\.value).reduce(0, +) / Double(recentPoints.count)
        let olderAvg = olderPoints.map(\.value).reduce(0, +) / Double(olderPoints.count)

        guard olderAvg > 0 else { return .stable }
        let change = (recentAvg - olderAvg) / olderAvg

        if change > 0.05 { return .rising }
        if change < -0.05 { return .falling }
        return .stable
    }
}

// MARK: - Menu Bar Metric

/// Which sensor metric to display in the menu bar icon.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case co2 = "co2"
    case pm25 = "pm25"
    case pm10 = "pm10"
    case temperature = "temperature"
    case humidity = "humidity"

    var id: String { rawValue }

    func label(unit: TemperatureUnit = .current) -> String {
        switch self {
        case .co2:         return "CO₂ (ppm)"
        case .pm25:        return "PM2.5 (µg/m³)"
        case .pm10:        return "PM10 (µg/m³)"
        case .temperature: return "Temperature (\(unit.symbol))"
        case .humidity:    return "Humidity (%)"
        }
    }

    static func from(stored: String) -> MenuBarMetric {
        MenuBarMetric(rawValue: stored) ?? .co2
    }
}

enum MenuBarMetricSetting {
    private static let key = "menuBarMetric"
    static var metric: String {
        get { UserDefaults.standard.string(forKey: key) ?? "co2" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Temperature Unit

/// Display unit for temperature. The API always returns Celsius;
/// conversion to Fahrenheit is done client-side for display only.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .celsius:    return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var symbol: String { label }

    func convert(_ celsius: Double) -> Double {
        switch self {
        case .celsius:    return celsius
        case .fahrenheit: return celsius * 9 / 5 + 32
        }
    }

    static var current: TemperatureUnit {
        TemperatureUnit(rawValue: TemperatureUnitSetting.unit) ?? .celsius
    }
}

enum TemperatureUnitSetting {
    private static let key = "temperatureUnit"
    static var unit: String {
        get { UserDefaults.standard.string(forKey: key) ?? "celsius" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Data Source

/// How the app gets sensor data from the device.
enum DataSource: String, CaseIterable, Identifiable {
    case cloudAPI = "cloudAPI"
    case ble = "ble"
    /// A device running ESPHome firmware, read from its web_server over the local network.
    case esphome = "esphome"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloudAPI: return "Cloud API"
        case .ble:      return "Bluetooth"
        case .esphome:  return "Local (ESPHome)"
        }
    }

    static func from(stored: String) -> DataSource {
        DataSource(rawValue: stored) ?? .ble
    }
}

enum DataSourceSetting {
    private static let key = "dataSource"
    static var source: String {
        get { UserDefaults.standard.string(forKey: key) ?? "ble" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - ESPHome Settings

enum ESPHomeSettings {
    /// mDNS name of the cgdn1.yaml ESPHome build.
    static let defaultHost = "cgdn1.local"
}

// MARK: - Poll Settings

/// How often the app polls the Qingping API for new data.
/// The device uploads every 10 min, but we poll every 60s to catch uploads promptly.
enum PollSettings {
    static let interval: TimeInterval = 60
}
