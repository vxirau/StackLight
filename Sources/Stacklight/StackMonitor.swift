import AppKit
import Foundation

@MainActor
final class StackMonitor: ObservableObject {
    @Published var tools: [ToolDefinition] = []
    @Published var snapshots: [ToolSnapshot] = []
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    @Published var hiddenMetricKeys: Set<String> = []
    @Published var selectedGraphifyProject: URL? {
        didSet {
            UserDefaults.standard.set(selectedGraphifyProject?.path, forKey: "selectedGraphifyProject")
        }
    }
    @Published var draft = ToolDraft()

    private var refreshTask: Task<Void, Never>?
    private let storeURL: URL
    private let hiddenMetricsKey = "hiddenMetricKeys"

    var overallSymbol: String {
        let available = snapshots.filter(\.isAvailable).count
        if available == 0 { return "circle" }
        if available == snapshots.count { return "circle.fill" }
        return "circle.lefthalf.filled"
    }

    var availableCount: Int {
        snapshots.filter(\.isAvailable).count
    }

    var totalCount: Int {
        snapshots.count
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("StackLight", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("tools.json")

        if let path = UserDefaults.standard.string(forKey: "selectedGraphifyProject") {
            selectedGraphifyProject = URL(fileURLWithPath: path)
        }
        hiddenMetricKeys = Set(UserDefaults.standard.stringArray(forKey: hiddenMetricsKey) ?? [])

        loadTools()
        snapshots = tools.map { ToolSnapshot(tool: $0) }
    }

    func startLoop() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let activeTools = tools
        let project = selectedGraphifyProject
        let updated = await withTaskGroup(of: ToolSnapshot.self) { group in
            for tool in activeTools {
                group.addTask {
                    await Self.snapshot(for: tool, graphifyProject: project)
                }
            }

            var values: [ToolSnapshot] = []
            for await snapshot in group {
                values.append(snapshot)
            }
            return values.sorted { lhs, rhs in
                let left = activeTools.firstIndex { $0.id == lhs.id } ?? 0
                let right = activeTools.firstIndex { $0.id == rhs.id } ?? 0
                return left < right
            }
        }

        snapshots = updated
        lastUpdated = Date()
        isRefreshing = false
    }

    func startDashboard(_ snapshot: ToolSnapshot) async {
        guard snapshot.tool.canStart else { return }
        _ = await ShellRunner.run(snapshot.tool.startCommand, timeout: 2)
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func stopDashboard(_ snapshot: ToolSnapshot) async {
        await stopDashboardPorts(snapshot.tool.stopPorts)
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func toggleDashboard(_ snapshot: ToolSnapshot) async {
        if snapshot.dashboardRunning {
            await stopDashboard(snapshot)
        } else if snapshot.tool.kind == .graphify {
            await startGraphifyServer()
        } else {
            await startDashboard(snapshot)
        }
    }

    func stopAllDashboards() async {
        let ports = snapshots.flatMap { $0.tool.stopPorts }
        guard !ports.isEmpty else { return }
        await stopDashboardPorts(ports)
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func openDashboard(_ snapshot: ToolSnapshot) {
        if snapshot.tool.kind == .graphify {
            openGraphifyStaticDashboard()
            return
        }
        guard let url = snapshot.tool.dashboard else { return }
        NSWorkspace.shared.open(url)
    }

    private func stopDashboardPorts(_ ports: [Int]) async {
        let joined = Set(ports).sorted().map(String.init).joined(separator: " ")
        guard !joined.isEmpty else { return }
        let command = """
        for port in \(joined); do
          for pid in $(lsof -tiTCP:$port -sTCP:LISTEN 2>/dev/null); do
            kill "$pid" 2>/dev/null || true
          done
        done
        """
        _ = await ShellRunner.run(command, timeout: 4)
    }

    func chooseGraphifyProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Graphify project"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let selectedGraphifyProject {
            panel.directoryURL = selectedGraphifyProject
        }

        if panel.runModal() == .OK {
            selectedGraphifyProject = panel.url
            Task { await refresh() }
        }
    }

    func openGraphifyStaticDashboard() {
        guard let selectedGraphifyProject else { return }
        let dashboard = selectedGraphifyProject.appendingPathComponent("graphify-out/graph.html")
        NSWorkspace.shared.open(dashboard)
    }

    func startGraphifyServer() async {
        guard let selectedGraphifyProject else { return }
        let graph = selectedGraphifyProject.appendingPathComponent("graphify-out/graph.json").path
        let command = """
        test -f '\(graph)' && nohup python3 -m graphify.serve '\(graph)' --transport http --host 127.0.0.1 --port 8080 >/tmp/stacklight-graphify-server.log 2>&1 &
        """
        _ = await ShellRunner.run(command, timeout: 2)
        try? await Task.sleep(for: .seconds(1))
        await refresh()
    }

    func addDraftTool() {
        guard let definition = draft.definition else { return }
        tools.append(definition)
        draft = ToolDraft()
        saveCustomTools()
        snapshots = tools.map { tool in
            snapshots.first(where: { $0.id == tool.id }) ?? ToolSnapshot(tool: tool)
        }
        Task { await refresh() }
    }

    func removeCustomTool(_ tool: ToolDefinition) {
        guard !tool.isBuiltIn else { return }
        tools.removeAll { $0.id == tool.id }
        snapshots.removeAll { $0.id == tool.id }
        saveCustomTools()
    }

    func resetCustomTools() {
        tools = ToolCatalog.builtIns
        snapshots = tools.map { ToolSnapshot(tool: $0) }
        saveCustomTools()
        Task { await refresh() }
    }

    func openConfigFolder() {
        NSWorkspace.shared.open(storeURL.deletingLastPathComponent())
    }

    func isMetricVisible(tool: ToolDefinition, metric: ToolMetric) -> Bool {
        !hiddenMetricKeys.contains(metricKey(tool: tool, metric: metric))
    }

    func setMetric(_ metric: ToolMetric, for tool: ToolDefinition, visible: Bool) {
        let key = metricKey(tool: tool, metric: metric)
        if visible {
            hiddenMetricKeys.remove(key)
        } else {
            hiddenMetricKeys.insert(key)
        }
        UserDefaults.standard.set(Array(hiddenMetricKeys).sorted(), forKey: hiddenMetricsKey)
    }

    func visibleMetrics(for snapshot: ToolSnapshot) -> [ToolMetric] {
        snapshot.metrics.filter { isMetricVisible(tool: snapshot.tool, metric: $0) }
    }

    private func metricKey(tool: ToolDefinition, metric: ToolMetric) -> String {
        "\(tool.id)::\(metric.title)"
    }

    private func loadTools() {
        let custom: [ToolDefinition]
        if let data = try? Data(contentsOf: storeURL),
           let decoded = try? JSONDecoder().decode([ToolDefinition].self, from: data) {
            custom = decoded
        } else {
            custom = []
        }
        tools = ToolCatalog.builtIns + custom.map { tool in
            var mutable = tool
            mutable.isBuiltIn = false
            return mutable
        }
    }

    private func saveCustomTools() {
        let custom = tools.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private static func snapshot(for tool: ToolDefinition, graphifyProject: URL?) async -> ToolSnapshot {
        var snapshot = ToolSnapshot(tool: tool)
        let dashboardPids = await pidsForPorts(tool.stopPorts)
        snapshot.dashboardRunning = !dashboardPids.isEmpty

        if tool.kind == .installPresence {
            let result = await ShellRunner.run(tool.presenceCommand, timeout: 3)
            snapshot.isAvailable = result.exitCode == 0 && !result.output.isEmpty
            snapshot.detail = serviceDetail(
                tool: tool,
                isAvailable: snapshot.isAvailable,
                dashboardRunning: snapshot.dashboardRunning,
                presenceText: snapshot.isAvailable ? result.output : nil
            )
            return snapshot
        }

        let pids = await pidsForPorts(tool.ports)
        var presenceText: String?
        if !tool.presenceCommand.isEmpty && pids.isEmpty {
            let result = await ShellRunner.run(tool.presenceCommand, timeout: 3)
            if result.exitCode == 0 && !result.output.isEmpty {
                presenceText = result.output
            }
        }

        snapshot.isAvailable = !pids.isEmpty || presenceText != nil
        snapshot.usage = await usageForPids(pids.isEmpty ? dashboardPids : pids)
        snapshot.detail = serviceDetail(
            tool: tool,
            isAvailable: snapshot.isAvailable,
            dashboardRunning: snapshot.dashboardRunning,
            presenceText: presenceText
        )

        switch tool.kind {
        case .agentmemory:
            snapshot.metrics = await agentMemoryMetrics()
        case .graphify:
            snapshot.metrics = graphifyMetrics(project: graphifyProject)
            if let graphifyProject {
                let dashboard = graphifyProject.appendingPathComponent("graphify-out/graph.html")
                let graph = graphifyProject.appendingPathComponent("graphify-out/graph.json")
                if FileManager.default.fileExists(atPath: dashboard.path) {
                    snapshot.detail = "Static dashboard found"
                } else if FileManager.default.fileExists(atPath: graph.path) {
                    snapshot.detail = "graph.json found; graph.html missing"
                } else {
                    snapshot.detail = "No graphify-out graph found for selected project"
                }
                snapshot.isAvailable = snapshot.isAvailable || FileManager.default.fileExists(atPath: dashboard.path)
                snapshot.dashboardRunning = snapshot.dashboardRunning || !dashboardPids.isEmpty
                if snapshot.isAvailable {
                    snapshot.detail = serviceDetail(
                        tool: tool,
                        isAvailable: true,
                        dashboardRunning: snapshot.dashboardRunning,
                        presenceText: presenceText ?? "Static graph available"
                    )
                }
            } else {
                snapshot.detail = serviceDetail(
                    tool: tool,
                    isAvailable: snapshot.isAvailable,
                    dashboardRunning: snapshot.dashboardRunning,
                    presenceText: presenceText ?? "Choose a project to open graphify-out/graph.html"
                )
            }
        case .generic, .installPresence:
            if !tool.metricsCommand.isEmpty {
                snapshot.metrics = await commandMetrics(tool.metricsCommand)
            }
        }

        return snapshot
    }

    private static func serviceDetail(tool: ToolDefinition, isAvailable: Bool, dashboardRunning: Bool, presenceText: String? = nil) -> String {
        let dashboard = dashboardRunning ? "dashboard running" : "dashboard stopped"
        let presence = presenceText?
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        if tool.ports.isEmpty {
            if isAvailable {
                return [presence?.isEmpty == false ? presence! : "Installed", dashboard].joined(separator: "; ")
            }
            return "Not installed; \(dashboard)"
        }

        let monitored = tool.ports.map(String.init).joined(separator: ", ")
        if tool.canStart || tool.canStop {
            return "\(isAvailable ? "Service available" : "Service not detected") on \(monitored); \(dashboard)"
        }
        return isAvailable ? "Listening on \(monitored)" : "No listener on \(monitored)"
    }

    private static func pidsForPorts(_ ports: [Int]) async -> [Int] {
        guard !ports.isEmpty else { return [] }
        let joined = ports.map(String.init).joined(separator: " ")
        let result = await ShellRunner.run("for port in \(joined); do lsof -nP -tiTCP:$port -sTCP:LISTEN 2>/dev/null; done | sort -u", timeout: 3)
        return result.output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func usageForPids(_ pids: [Int]) async -> ProcessUsage {
        guard !pids.isEmpty else { return ProcessUsage() }
        let pidList = pids.map(String.init).joined(separator: ",")
        let result = await ShellRunner.run("ps -o pid=,pcpu=,rss=,comm= -p \(pidList)", timeout: 3)
        var usage = ProcessUsage(pids: pids)

        for line in result.output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }
            usage.cpuPercent += Double(parts[1]) ?? 0
            usage.memoryBytes += (Int64(parts[2]) ?? 0) * 1024
            if parts.count == 4 {
                usage.commands.append(String(parts[3]))
            }
        }

        return usage
    }

    private static func agentMemoryMetrics() async -> [ToolMetric] {
        let result = await ShellRunner.run("agentmemory status | col -b", timeout: 8)
        guard result.exitCode == 0 else { return [] }
        var metrics: [ToolMetric] = []
        let mappings: [(needle: String, title: String, symbol: String)] = [
            ("Sessions:", "Sessions", "bubble.left.and.bubble.right"),
            ("Observations:", "Observations", "eye"),
            ("Memories:", "Memories", "brain"),
            ("Graph:", "Graph", "point.3.connected.trianglepath.dotted"),
            ("Token savings:", "Token savings", "chart.line.downtrend.xyaxis"),
            ("Full context:", "Full context", "text.alignleft"),
            ("Injected:", "Injected", "arrow.down.doc"),
            ("Provider:", "Provider", "network"),
            ("Embeddings:", "Embeddings", "square.stack.3d.up")
        ]

        for rawLine in result.output.split(whereSeparator: \.isNewline).map(String.init) {
            let line = cleanedMetricLine(rawLine)
            guard !line.isEmpty else { continue }
            for mapping in mappings where line.contains(mapping.needle) {
                let value = valueAfterMarker(mapping.needle, in: line)
                if !value.isEmpty {
                    metrics.append(ToolMetric(title: mapping.title, value: value, symbol: mapping.symbol))
                }
            }
        }
        return metrics
    }

    private static func commandMetrics(_ command: String) async -> [ToolMetric] {
        let result = await ShellRunner.run(command, timeout: 4)
        guard result.exitCode == 0, !result.output.isEmpty else { return [] }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { cleanedMetricLine(String($0)) }
            .filter { !$0.isEmpty }
            .filter { !$0.allSatisfy { character in character == "-" || character == "=" || character == " " } }
            .prefix(6)
            .enumerated()
            .map { index, line in metric(from: line, fallbackIndex: index) }
    }

    private static func graphifyMetrics(project: URL?) -> [ToolMetric] {
        guard let project else { return [] }
        let graph = project.appendingPathComponent("graphify-out/graph.json")
        guard let data = try? Data(contentsOf: graph),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var metrics: [ToolMetric] = []
        if let nodes = object["nodes"] as? [Any] {
            metrics.append(ToolMetric(title: "Nodes", value: "\(nodes.count)", symbol: "circle.hexagongrid"))
        }
        if let edges = object["edges"] as? [Any] {
            metrics.append(ToolMetric(title: "Edges", value: "\(edges.count)", symbol: "arrow.triangle.branch"))
        }
        if let files = object["files"] as? [Any] {
            metrics.append(ToolMetric(title: "Files", value: "\(files.count)", symbol: "doc.text"))
        }
        return metrics
    }

    private static func metric(from line: String, fallbackIndex: Int) -> ToolMetric {
        if let separator = line.firstIndex(of: ":") ?? line.firstIndex(of: "=") {
            let title = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty && !value.isEmpty {
                return ToolMetric(title: title, value: value, symbol: "gauge.with.dots.needle.50percent")
            }
        }
        return ToolMetric(title: "Metric \(fallbackIndex + 1)", value: line, symbol: "gauge.with.dots.needle.50percent")
    }

    private static func valueAfterMarker(_ marker: String, in line: String) -> String {
        guard let range = line.range(of: marker) else { return "" }
        return String(line[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedMetricLine(_ line: String) -> String {
        let drawingCharacters = CharacterSet(charactersIn: "│┃║╎╏┆┇┊┋─━═╌╍┄┅┈┉┌┐└┘┏┓┗┛╭╮╰╯├┤┬┴┼╞╡╤╧╪")
        return line
            .components(separatedBy: drawingCharacters)
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
