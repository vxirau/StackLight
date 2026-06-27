import SwiftUI

struct StacklightView: View {
    @EnvironmentObject private var monitor: StackMonitor

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TabView {
                MonitorView()
                    .tabItem {
                        Label("Monitor", systemImage: "waveform.path.ecg")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
            .padding(.top, 4)
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            StackMark(
                availableCount: monitor.availableCount,
                totalCount: monitor.totalCount,
                size: 30,
                showsStatusLights: true
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("StackLight")
                    .font(.headline)
                Text("Local context stack monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await monitor.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(monitor.isRefreshing)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            Text(lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = monitor.lastUpdated else {
            return "Waiting for first refresh"
        }
        return "Updated \(lastUpdated.formatted(date: .omitted, time: .standard))"
    }
}

struct StackMark: View {
    let availableCount: Int
    let totalCount: Int
    let size: CGFloat
    let showsStatusLights: Bool

    private var normalizedAvailability: Double {
        guard totalCount > 0 else { return 0 }
        return Double(availableCount) / Double(totalCount)
    }

    private var primaryDot: Color {
        normalizedAvailability > 0 ? .cyan : .secondary
    }

    private var secondaryDot: Color {
        normalizedAvailability >= 0.75 ? .green : .secondary.opacity(0.65)
    }

    var body: some View {
        ZStack {
            stylizedS
                .foregroundStyle(.primary)

            if showsStatusLights {
                Circle()
                    .fill(primaryDot)
                    .frame(width: size * 0.13, height: size * 0.13)
                    .shadow(color: primaryDot.opacity(0.75), radius: size * 0.08)
                    .offset(x: size * 0.22, y: size * 0.02)

                Circle()
                    .fill(secondaryDot)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .shadow(color: secondaryDot.opacity(0.65), radius: size * 0.07)
                    .offset(x: size * 0.22, y: size * 0.27)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("StackLight")
    }

    private var stylizedS: some View {
        ZStack {
            Capsule()
                .frame(width: size * 0.78, height: size * 0.18)
                .offset(x: size * 0.03, y: -size * 0.28)

            Capsule()
                .frame(width: size * 0.78, height: size * 0.18)
                .offset(x: -size * 0.03, y: 0)

            Capsule()
                .frame(width: size * 0.78, height: size * 0.18)
                .offset(x: size * 0.03, y: size * 0.28)

            Capsule()
                .frame(width: size * 0.2, height: size * 0.45)
                .offset(x: -size * 0.31, y: -size * 0.14)

            Capsule()
                .frame(width: size * 0.2, height: size * 0.45)
                .offset(x: size * 0.31, y: size * 0.14)
        }
    }
}

private struct MonitorView: View {
    @EnvironmentObject private var monitor: StackMonitor

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(monitor.snapshots) { snapshot in
                    ToolRow(snapshot: snapshot)
                }
            }
            .padding(10)
        }
    }
}

private struct ToolRow: View {
    @EnvironmentObject private var monitor: StackMonitor
    let snapshot: ToolSnapshot
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if snapshot.usage.memoryBytes > 0 || snapshot.usage.cpuPercent > 0 {
                    HStack(spacing: 6) {
                        MetricPill(symbol: "speedometer", title: "CPU", value: snapshot.usage.cpuLabel)
                        MetricPill(symbol: "memorychip", title: "Memory", value: snapshot.usage.memoryLabel)
                        if !snapshot.usage.pids.isEmpty {
                            MetricPill(symbol: "number", title: "PID", value: pidSummary)
                        }
                    }
                }

                if !snapshot.metrics.isEmpty {
                    MetricBoard(metrics: snapshot.metrics)
                }

                if snapshot.tool.kind == .graphify {
                    graphifyControls
                } else {
                    standardControls
                }

                if !snapshot.tool.notes.isEmpty {
                    Label(snapshot.tool.notes, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)
        } label: {
            ToolHeader(snapshot: snapshot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pidSummary: String {
        if snapshot.usage.pids.count <= 2 {
            return snapshot.usage.pids.map(String.init).joined(separator: ", ")
        }
        let visible = snapshot.usage.pids.prefix(2).map(String.init).joined(separator: ", ")
        return "\(visible) +\(snapshot.usage.pids.count - 2)"
    }

    private var standardControls: some View {
        HStack {
            Button {
                Task { await monitor.startDashboard(snapshot) }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(!snapshot.tool.canStart)
            .controlSize(.small)

            Button {
                monitor.openDashboard(snapshot)
            } label: {
                Label("Open", systemImage: "safari")
            }
            .disabled(snapshot.tool.dashboard == nil)
            .controlSize(.small)

            Button(role: .destructive) {
                Task { await monitor.stopDashboard(snapshot) }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!snapshot.tool.canStop || !snapshot.isAvailable)
            .controlSize(.small)

            Spacer()
        }
    }

    private var graphifyControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let selected = monitor.selectedGraphifyProject {
                Text(selected.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Button {
                    monitor.chooseGraphifyProject()
                } label: {
                    Label("Choose", systemImage: "folder")
                }
                .controlSize(.small)

                Button {
                    monitor.openGraphifyStaticDashboard()
                } label: {
                    Label("Open static", systemImage: "safari")
                }
                .disabled(monitor.selectedGraphifyProject == nil)
                .controlSize(.small)

                Button {
                    Task { await monitor.startGraphifyServer() }
                } label: {
                    Label("Start server", systemImage: "play.fill")
                }
                .disabled(monitor.selectedGraphifyProject == nil)
                .controlSize(.small)

                Button(role: .destructive) {
                    Task { await monitor.stopDashboard(snapshot) }
                } label: {
                    Label("Stop server", systemImage: "stop.fill")
                }
                .disabled(snapshot.usage.pids.isEmpty)
                .controlSize(.small)

                Spacer()
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var monitor: StackMonitor

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolCatalog
                Divider()
                addToolForm
            }
            .padding(12)
        }
    }

    private var toolCatalog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Tool Catalog", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Button {
                    monitor.openConfigFolder()
                } label: {
                    Label("Open JSON", systemImage: "folder")
                }
            }

            ForEach(monitor.tools) { tool in
                HStack(spacing: 10) {
                    Image(systemName: tool.isBuiltIn ? "lock.fill" : "slider.horizontal.3")
                        .foregroundStyle(tool.isBuiltIn ? Color.secondary : Color.blue)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.system(size: 13, weight: .medium))
                        Text(toolSummary(tool))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if !tool.isBuiltIn {
                        Button(role: .destructive) {
                            monitor.removeCustomTool(tool)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var addToolForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add Monitor", systemImage: "plus.circle")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Name")
                    TextField("My local tool", text: $monitor.draft.name)
                }
                GridRow {
                    Text("Subtitle")
                    TextField("What this monitor watches", text: $monitor.draft.subtitle)
                }
                GridRow {
                    Text("Dashboard")
                    TextField("http://127.0.0.1:9000", text: $monitor.draft.dashboardURL)
                }
                GridRow {
                    Text("Ports")
                    TextField("9000, 9001", text: $monitor.draft.ports)
                }
                GridRow {
                    Text("Stop ports")
                    TextField("9000", text: $monitor.draft.stopPorts)
                }
                GridRow {
                    Text("Start command")
                    TextField("nohup my-tool dashboard --host 127.0.0.1 --port 9000 >/tmp/my-tool.log 2>&1 &", text: $monitor.draft.startCommand)
                }
                GridRow {
                    Text("Metrics command")
                    TextField("my-tool status | sed -n '1,6p'", text: $monitor.draft.metricsCommand)
                }
                GridRow {
                    Text("Presence command")
                    TextField("test -d \"$HOME/.my-tool\" && echo installed", text: $monitor.draft.presenceCommand)
                }
                GridRow {
                    Text("Notes")
                    TextField("Local-only dashboard", text: $monitor.draft.notes)
                }
            }
            .font(.caption)

            HStack {
                Button {
                    monitor.addDraftTool()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(monitor.draft.definition == nil)

                Button(role: .destructive) {
                    monitor.resetCustomTools()
                } label: {
                    Label("Remove Custom", systemImage: "arrow.counterclockwise")
                }

                Spacer()
            }
        }
    }

    private func toolSummary(_ tool: ToolDefinition) -> String {
        var parts: [String] = []
        if !tool.ports.isEmpty {
            parts.append("ports \(tool.ports.map(String.init).joined(separator: ","))")
        }
        if tool.dashboard != nil {
            parts.append("dashboard")
        }
        if tool.canStart {
            parts.append("startable")
        }
        if parts.isEmpty {
            return tool.subtitle.isEmpty ? "No dashboard" : tool.subtitle
        }
        return parts.joined(separator: " · ")
    }
}

private struct ToolHeader: View {
    let snapshot: ToolSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(snapshot.isAvailable ? Color.green : Color.gray.opacity(0.6))
                .frame(width: 9, height: 9)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(snapshot.tool.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(snapshot.isAvailable ? "Available" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(snapshot.isAvailable ? .green : .secondary)
                }

                if !snapshot.tool.subtitle.isEmpty {
                    Text(snapshot.tool.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(snapshot.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MetricBoard: View {
    let metrics: [ToolMetric]

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(metrics) { metric in
                HStack(spacing: 6) {
                    Image(systemName: metric.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(metric.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(metric.value)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

private struct MetricPill: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.background.opacity(0.7), in: Capsule())
    }
}
