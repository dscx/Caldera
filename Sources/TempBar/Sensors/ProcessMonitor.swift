import Foundation

struct ProcessCPUUsage: Identifiable, Equatable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpuPercent: Double
}

/// Shells out to `ps` for a CPU-sorted process snapshot, rather than
/// bridging libproc directly — this is the same data Activity Monitor and
/// `top` are built on, and `ps -r` already does the sorting.
///
/// There's no OS API that maps a specific SMC temperature key to the
/// process heating it, so this is deliberately a system-wide "what's busy
/// right now" hint shown alongside a hot reading, not a precise cause.
enum ProcessMonitor {
    static func topProcesses(limit: Int = 5) -> [ProcessCPUUsage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pid=,pcpu=,comm=", "-r"]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [ProcessCPUUsage] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]), let cpu = Double(parts[1]) else { continue }
            let name = (String(parts[2]) as NSString).lastPathComponent
            results.append(ProcessCPUUsage(pid: pid, name: name, cpuPercent: cpu))
            if results.count >= limit { break }
        }
        return results
    }
}
