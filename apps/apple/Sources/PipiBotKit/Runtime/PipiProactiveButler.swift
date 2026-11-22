// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Jarvis Proactive Butler Engine:
// - Daily morning / pre-meeting briefings (Calendar + Reminders + Git)
// - Natural-language schedule parsing for user routines/reminders
// - Mac health & GitHub release sentinel with anti-fatigue cooldown

import Foundation

public struct PipiSentinelAlert: Sendable, Equatable {
    public let category: String
    public let title: String
    public let body: String

    public init(category: String, title: String, body: String) {
        self.category = category
        self.title = title
        self.body = body
    }
}

public enum PipiScheduleParser {
    /// Parses colloquial Chinese/English time expressions into an interval in minutes & normalized label.
    public static func parseIntervalMinutes(from hint: String, fallback: Int = 1440) -> (minutes: Int, isOneShot: Bool, display: String) {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard !lower.isEmpty else {
            return (max(1, fallback), false, "每 \(max(1, fallback)) 分钟")
        }

        // One-shot relative reminders: "30分钟后", "2小时后", "in 15 min"
        if let mins = firstIntMatching(pattern: #"(\d+)\s*(分钟|分|min|mins|minute|minutes)\s*(后|later)?"#, in: lower),
           (lower.contains("后") || lower.contains("later") || lower.contains("in ")) {
            return (max(1, mins), true, "\(mins) 分钟后")
        }
        if let hrs = firstIntMatching(pattern: #"(\d+)\s*(小时|时|hr|hrs|hour|hours)\s*(后|later)?"#, in: lower),
           (lower.contains("后") || lower.contains("later") || lower.contains("in ")) {
            return (max(1, hrs * 60), true, "\(hrs) 小时后")
        }

        // Recurring: "每30分钟", "每2小时", "每天早上9点"
        if let mins = firstIntMatching(pattern: #"(?:每|every)\s*(\d+)\s*(分钟|分|min|minute)"#, in: lower) {
            return (max(1, mins), false, "每 \(mins) 分钟")
        }
        if let hrs = firstIntMatching(pattern: #"(?:每|every)\s*(\d+)\s*(小时|时|hour|hr)"#, in: lower) {
            return (max(1, hrs * 60), false, "每 \(hrs) 小时")
        }
        if lower.contains("每小时") || lower.contains("hourly") || lower.contains("every hour") {
            return (60, false, "每小时")
        }
        if lower.contains("每天") || lower.contains("每日") || lower.contains("早报") || lower.contains("daily") || lower.contains("every morning") || lower.contains("every day") {
            return (1440, false, trimmed)
        }
        if lower.contains("每周") || lower.contains("weekly") {
            return (1440 * 7, false, trimmed)
        }
        return (max(1, fallback), false, trimmed)
    }

    private static func firstIntMatching(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2 else { return nil }
        let numStr = ns.substring(with: match.range(at: 1))
        return Int(numStr)
    }
}

public enum PipiProactiveButler {

    /// Builds a lively daily briefing combining calendar events, reminders, and workspace git status.
    public static func buildDailyBriefing(
        calendarSummary: String,
        workspaceDirectory: String,
        recentFailedRunsCount: Int
    ) async -> String {
        let gitSummary = await collectWorkspaceGitSummary(workspaceDirectory: workspaceDirectory)
        var sections: [String] = [
            "☀️ 早安！PiPi 给你整理好了今天的简报："
        ]
        if !calendarSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("📅 日程与提醒：\n\(calendarSummary)")
        } else {
            sections.append("📅 日程与提醒：今天暂时没有即将到期的日程或提醒，节奏很轻松～")
        }
        if !gitSummary.isEmpty {
            sections.append("🛠️ 工作区动态：\n\(gitSummary)")
        }
        if recentFailedRunsCount > 0 {
            sections.append("⚠️ 昨晚有 \(recentFailedRunsCount) 条任务执行异常，随时回复我让我帮你排查！")
        }
        sections.append("有啥需要我先动手的，直接微信跟我说一声就行 ✨")
        return sections.joined(separator: "\n\n")
    }

    /// Probes macOS disk usage, runaway CPU processes, and optional GitHub update availability.
    public static func inspectSystemSentinel(
        availableUpdateVersion: String?
    ) async -> [PipiSentinelAlert] {
        var alerts: [PipiSentinelAlert] = []
        #if os(macOS)
        // 1. Check root disk free space
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let freeBytes = (attrs[.systemFreeSize] as? NSNumber)?.int64Value,
           let totalBytes = (attrs[.systemSize] as? NSNumber)?.int64Value,
           totalBytes > 0 {
            let freeGB = Double(freeBytes) / 1_073_741_824.0
            let usedRatio = 1.0 - (Double(freeBytes) / Double(totalBytes))
            if freeGB < 10.0 || usedRatio > 0.92 {
                let pct = Int((usedRatio * 100).rounded())
                alerts.append(PipiSentinelAlert(
                    category: "disk_low",
                    title: "Mac 磁盘空间告急",
                    body: String(format: "硬盘已经用了 %d%%，只剩 %.1f GB 可用啦 😅 要不要我帮你扫一下大文件或清理构建缓存？", pct, freeGB)
                ))
            }
        }

        // 2. Check for runaway CPU process (> 180% CPU)
        if let runaway = await detectRunawayCPUProcess() {
            alerts.append(PipiSentinelAlert(
                category: "cpu_runaway_\(runaway.name)",
                title: "发现高占用进程",
                body: "进程 `\(runaway.name)` (PID \(runaway.pid)) CPU 占用飙到了 \(runaway.cpu)% 🔥 如果不是你在跑编译，回复我帮你查查它！"
            ))
        }
        #endif

        // 3. GitHub Release update alert
        if let newVer = availableUpdateVersion, !newVer.isEmpty {
            alerts.append(PipiSentinelAlert(
                category: "update_\(newVer)",
                title: "PiPiBot 有新版本啦",
                body: "检测到 GitHub Release 新版本 v\(newVer) 🚀 在微信回复「更新」或在 Mac 设置页点一下就能自动升级！"
            ))
        }
        return alerts
    }

    private static func collectWorkspaceGitSummary(workspaceDirectory: String) async -> String {
        #if os(macOS)
        let expanded = (workspaceDirectory as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: (expanded as NSString).appendingPathComponent(".git")) else {
            return ""
        }
        return await Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' '); last=$(git log -1 --pretty='%h %s (%cr)' 2>/dev/null); echo \"分支：$branch · 未提交改动：$dirty 项\\n最近提交：$last\""]
            proc.currentDirectoryURL = URL(fileURLWithPath: expanded)
            proc.standardInput = FileHandle.nullDevice
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
        #else
        return ""
        #endif
    }

    #if os(macOS)
    private static func detectRunawayCPUProcess() async -> (pid: String, cpu: String, name: String)? {
        await Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/ps")
            proc.arguments = ["-Ao", "pid,pcpu,comm", "-r"]
            proc.standardInput = FileHandle.nullDevice
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: .newlines).dropFirst().prefix(5) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 3, let cpu = Double(parts[1]), cpu >= 180.0 else { continue }
                let pid = String(parts[0])
                let cmd = URL(fileURLWithPath: String(parts[2])).lastPathComponent
                if cmd == "WindowServer" || cmd == "kernel_task" { continue }
                return (pid, String(format: "%.0f", cpu), cmd)
            }
            return nil
        }.value
    }
    #endif
}
