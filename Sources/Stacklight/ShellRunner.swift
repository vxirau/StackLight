import Darwin
import Foundation

struct ShellResult {
    let output: String
    let exitCode: Int32
    let timedOut: Bool
}

enum ShellRunner {
    static func run(_ command: String, timeout: TimeInterval = 6) async -> ShellResult {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                return ShellResult(output: error.localizedDescription, exitCode: 127, timedOut: false)
            }

            let deadline = Date().addingTimeInterval(timeout)
            var timedOut = false
            while process.isRunning && Date() < deadline {
                usleep(50_000)
            }

            if process.isRunning {
                timedOut = true
                process.terminate()
                usleep(200_000)
                if process.isRunning {
                    process.interrupt()
                }
            }

            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: outData, as: UTF8.self)
            let err = String(decoding: errData, as: UTF8.self)
            let combined = [out, err].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")

            return ShellResult(output: combined.trimmingCharacters(in: .whitespacesAndNewlines), exitCode: process.terminationStatus, timedOut: timedOut)
        }.value
    }
}
