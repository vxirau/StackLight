# Tool Catalog Format

Custom monitors are stored as an array of JSON objects in:

```text
~/Library/Application Support/StackLight/tools.json
```

Fields:

- `id`: stable unique string.
- `name`: display name.
- `subtitle`: short description.
- `dashboardURL`: local URL to open.
- `ports`: local listener ports that indicate availability.
- `startCommand`: shell command used to start the dashboard.
- `stopPorts`: dashboard listener ports to kill when stopping the dashboard. Do not include core service ports unless the dashboard and service are the same process.
- `metricsCommand`: shell command whose first lines are shown as metrics.
- `presenceCommand`: shell command used to report installed/available state when no ports exist.
- `notes`: small operator note shown in the UI.
- `kind`: `generic`, `agentmemory`, `graphify`, or `installPresence`.
- `isBuiltIn`: should be `false` for custom monitors.

Minimal custom monitor:

```json
[
  {
    "id": "my-tool",
    "name": "My Tool",
    "subtitle": "Local dashboard",
    "dashboardURL": "http://127.0.0.1:9000",
    "ports": [9000],
    "startCommand": "nohup my-tool dashboard --host 127.0.0.1 --port 9000 >/tmp/my-tool.log 2>&1 &",
    "stopPorts": [9000],
    "metricsCommand": "my-tool status | sed -n '1,6p'",
    "presenceCommand": "",
    "notes": "Local-only dashboard.",
    "kind": "generic",
    "isBuiltIn": false
  }
]
```
