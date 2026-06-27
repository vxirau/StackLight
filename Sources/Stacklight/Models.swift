import Foundation

struct ToolDefinition: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var subtitle: String
    var dashboardURL: String
    var ports: [Int]
    var startCommand: String
    var stopPorts: [Int]
    var metricsCommand: String
    var presenceCommand: String
    var notes: String
    var kind: ToolKind
    var isBuiltIn: Bool

    var dashboard: URL? {
        guard !dashboardURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return URL(string: dashboardURL)
    }

    var canStart: Bool {
        !startCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStop: Bool {
        !stopPorts.isEmpty
    }
}

enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case generic
    case agentmemory
    case graphify
    case installPresence

    var id: String { rawValue }
}

struct ProcessUsage: Equatable {
    var pids: [Int] = []
    var cpuPercent: Double = 0
    var memoryBytes: Int64 = 0
    var commands: [String] = []

    var memoryLabel: String {
        ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory)
    }

    var cpuLabel: String {
        String(format: "%.1f%%", cpuPercent)
    }
}

struct ToolMetric: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var value: String
    var symbol: String
}

struct ToolSnapshot: Identifiable, Equatable {
    let tool: ToolDefinition
    var isAvailable: Bool = false
    var usage = ProcessUsage()
    var metrics: [ToolMetric] = []
    var detail: String = "Not checked yet"

    var id: String { tool.id }
}

enum ToolCatalog {
    static let builtIns: [ToolDefinition] = [
        ToolDefinition(
            id: "agentmemory",
            name: "agentmemory",
            subtitle: "Memory API and viewer",
            dashboardURL: "http://localhost:3113",
            ports: [3111, 3113],
            startCommand: "launchctl kickstart -k gui/$(id -u)/com.agentmemory.server 2>/dev/null || nohup agentmemory >/tmp/stacklight-agentmemory.log 2>&1 &",
            stopPorts: [3113],
            metricsCommand: "",
            presenceCommand: "",
            notes: "Stops only the viewer port; the memory API stays available when possible.",
            kind: .agentmemory,
            isBuiltIn: true
        ),
        ToolDefinition(
            id: "lean-ctx",
            name: "lean-ctx",
            subtitle: "Context runtime dashboard",
            dashboardURL: "http://127.0.0.1:3333",
            ports: [3333],
            startCommand: "nohup lean-ctx dashboard --host=127.0.0.1 --port=3333 --open=none >/tmp/stacklight-lean-ctx-dashboard.log 2>&1 &",
            stopPorts: [3333],
            metricsCommand: "lean-ctx config show 2>/dev/null | col -b | sed -n '1,14p'",
            presenceCommand: "",
            notes: "Dashboard is local-only and is not started automatically.",
            kind: .generic,
            isBuiltIn: true
        ),
        ToolDefinition(
            id: "codebase-memory-mcp",
            name: "codebase-memory-mcp",
            subtitle: "Repository graph UI",
            dashboardURL: "http://127.0.0.1:9749",
            ports: [9749],
            startCommand: "nohup codebase-memory-mcp --ui=true --port=9749 >/tmp/stacklight-codebase-memory-ui.log 2>&1 &",
            stopPorts: [9749],
            metricsCommand: "codebase-memory-mcp config list 2>/dev/null | sed -n '1,8p'",
            presenceCommand: "",
            notes: "Uses whichever codebase-memory-mcp is first on PATH.",
            kind: .generic,
            isBuiltIn: true
        ),
        ToolDefinition(
            id: "headroom",
            name: "Headroom",
            subtitle: "Local optimization proxy dashboard",
            dashboardURL: "http://127.0.0.1:8787/dashboard",
            ports: [8787],
            startCommand: "HEADROOM_TELEMETRY=off HEADROOM_UPDATE_CHECK=off HEADROOM_LANGFUSE_ENABLED=0 nohup headroom proxy --host 127.0.0.1 --port 8787 --no-telemetry >/tmp/stacklight-headroom-proxy.log 2>&1 &",
            stopPorts: [8787],
            metricsCommand: "curl -fsS http://127.0.0.1:8787/stats 2>/dev/null | sed -n '1,6p'",
            presenceCommand: "",
            notes: "Proxy remains off until you start it here or from a terminal.",
            kind: .generic,
            isBuiltIn: true
        ),
        ToolDefinition(
            id: "graphify",
            name: "Graphify",
            subtitle: "Static graph dashboard and optional local MCP server",
            dashboardURL: "",
            ports: [8080],
            startCommand: "",
            stopPorts: [8080],
            metricsCommand: "",
            presenceCommand: "",
            notes: "Static dashboard opens from the selected project graphify-out folder.",
            kind: .graphify,
            isBuiltIn: true
        ),
        ToolDefinition(
            id: "ponytail",
            name: "Ponytail",
            subtitle: "Local skill/tooling layer",
            dashboardURL: "",
            ports: [],
            startCommand: "",
            stopPorts: [],
            metricsCommand: "",
            presenceCommand: "test -d \"$HOME/.local/share/agent-stack/ponytail\" && echo installed",
            notes: "No dashboard found; status is based on local checkout/install presence.",
            kind: .installPresence,
            isBuiltIn: true
        )
    ]
}

struct ToolDraft: Equatable {
    var id: String = UUID().uuidString
    var name: String = ""
    var subtitle: String = ""
    var dashboardURL: String = ""
    var ports: String = ""
    var startCommand: String = ""
    var stopPorts: String = ""
    var metricsCommand: String = ""
    var presenceCommand: String = ""
    var notes: String = ""

    var definition: ToolDefinition? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return ToolDefinition(
            id: id,
            name: trimmedName,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            dashboardURL: dashboardURL.trimmingCharacters(in: .whitespacesAndNewlines),
            ports: Self.parsePorts(ports),
            startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            stopPorts: Self.parsePorts(stopPorts),
            metricsCommand: metricsCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            presenceCommand: presenceCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .generic,
            isBuiltIn: false
        )
    }

    static func parsePorts(_ value: String) -> [Int] {
        value
            .split { $0 == "," || $0 == " " || $0 == "\n" || $0 == "\t" }
            .compactMap { Int($0) }
    }
}
