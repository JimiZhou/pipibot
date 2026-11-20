// PiPiBot — Clean-room MIT implementation.
// Wave 2 (#03): First-batch macOS Native Signal Collector (EventKit Calendar/Reminders,
// Local Git/Workspace FS, Device Telemetry, Local Chat/Notes) with Testable Protocol Seam.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import Foundation

#if os(macOS) && canImport(EventKit)
@preconcurrency import EventKit
#endif

// MARK: - 1. Native Signal Provider Seam & Authorization Snapshot

public enum PipiEventKitAuthState: String, Codable, Sendable, Equatable {
    case notDetermined = "not_determined"
    case authorized
    case denied
    case unavailable

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .notDetermined: return lang == .zhHans ? "未授权" : "Not Requested"
        case .authorized: return lang == .zhHans ? "已授权" : "Authorized"
        case .denied: return lang == .zhHans ? "已拒绝" : "Denied"
        case .unavailable: return lang == .zhHans ? "不可用" : "Unavailable"
        }
    }
}

public struct PipiNativeSignalCollectorInput: Sendable {
    public var enabledSources: Set<PipiProactiveSourceKind>
    public var workspaceDirectories: [String]
    public var recentProfileNote: String
    public var now: Date

    public init(
        enabledSources: Set<PipiProactiveSourceKind> = Set(PipiProactiveSourceKind.allCases),
        workspaceDirectories: [String] = [],
        recentProfileNote: String = "",
        now: Date = Date()
    ) {
        self.enabledSources = enabledSources
        self.workspaceDirectories = workspaceDirectories
        self.recentProfileNote = recentProfileNote
        self.now = now
    }
}

public protocol PipiNativeSignalProvider: Sendable {
    func collectSignals(input: PipiNativeSignalCollectorInput) async -> [PipiProactiveSignal]
    func calendarAuthorizationState() -> PipiEventKitAuthState
    func remindersAuthorizationState() -> PipiEventKitAuthState
    func requestCalendarAccess() async -> PipiEventKitAuthState
    func requestRemindersAccess() async -> PipiEventKitAuthState
}

// MARK: - 2. Default macOS Native Signal Collector (iOS-Safe Stub Fallback)

public struct PipiMacNativeSignalCollector: PipiNativeSignalProvider {
    public init() {}

    public func calendarAuthorizationState() -> PipiEventKitAuthState {
        #if os(macOS) && canImport(EventKit)
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    public func remindersAuthorizationState() -> PipiEventKitAuthState {
        #if os(macOS) && canImport(EventKit)
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted, .writeOnly:
            return .denied
        @unknown default:
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    public func requestCalendarAccess() async -> PipiEventKitAuthState {
        #if os(macOS) && canImport(EventKit)
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            return calendarAuthorizationState()
        }
        #else
        return .unavailable
        #endif
    }

    public func requestRemindersAccess() async -> PipiEventKitAuthState {
        #if os(macOS) && canImport(EventKit)
        let store = EKEventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            return granted ? .authorized : .denied
        } catch {
            return remindersAuthorizationState()
        }
        #else
        return .unavailable
        #endif
    }

    public func collectSignals(input: PipiNativeSignalCollectorInput) async -> [PipiProactiveSignal] {
        var signals: [PipiProactiveSignal] = []

        if input.enabledSources.contains(.calendarEventKit) {
            signals.append(contentsOf: collectCalendarSignals(now: input.now))
        }
        if input.enabledSources.contains(.remindersEventKit) {
            signals.append(contentsOf: await collectReminderSignals(now: input.now))
        }
        if input.enabledSources.contains(.gitWorkspace) {
            signals.append(contentsOf: collectGitWorkspaceSignals(directories: input.workspaceDirectories))
        }
        if input.enabledSources.contains(.deviceTelemetry) {
            signals.append(contentsOf: collectDeviceTelemetrySignals())
        }
        if input.enabledSources.contains(.chatPocketNote) {
            signals.append(contentsOf: collectLocalNoteSignals(note: input.recentProfileNote))
        }

        return signals
    }

    // MARK: - Source 1: Apple EventKit Calendar (macOS Native)

    private func collectCalendarSignals(now: Date) -> [PipiProactiveSignal] {
        #if os(macOS) && canImport(EventKit)
        guard calendarAuthorizationState() == .authorized else { return [] }
        let store = EKEventStore()
        let end = now.addingTimeInterval(24 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
        let iso = ISO8601DateFormatter()

        return events.map { ev in
            let title = (ev.title ?? "Calendar Event").trimmingCharacters(in: .whitespacesAndNewlines)
            let location = (ev.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (ev.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let detailParts = [
                location.isEmpty ? nil : "Location: \(location)",
                notes.isEmpty ? nil : String(notes.prefix(180))
            ].compactMap { $0 }
            let content = detailParts.isEmpty
                ? "Upcoming calendar event: \(title)"
                : detailParts.joined(separator: " · ")

            return PipiProactiveSignal(
                source: .calendarEventKit,
                kind: "upcoming_event",
                matter: title,
                title: title,
                content: content,
                dueAtIso: iso.string(from: ev.startDate),
                supportsPrepare: true
            )
        }
        #else
        return []
        #endif
    }

    // MARK: - Source 2: Apple EventKit Reminders (macOS Native)

    private func collectReminderSignals(now: Date) async -> [PipiProactiveSignal] {
        #if os(macOS) && canImport(EventKit)
        guard remindersAuthorizationState() == .authorized else { return [] }
        let store = EKEventStore()
        let end = now.addingTimeInterval(48 * 3600)
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: now.addingTimeInterval(-24 * 3600),
            ending: end,
            calendars: nil
        )
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { fetched in
                let iso = ISO8601DateFormatter()
                let mapped: [PipiProactiveSignal] = (fetched ?? []).prefix(6).map { rem in
                    let title = (rem.title ?? "Reminder").trimmingCharacters(in: .whitespacesAndNewlines)
                    let dueDate = rem.dueDateComponents?.date
                    let notes = (rem.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let content = notes.isEmpty ? "Incomplete Apple Reminder: \(title)" : String(notes.prefix(180))
                    return PipiProactiveSignal(
                        source: .remindersEventKit,
                        kind: "due_reminder",
                        matter: title,
                        title: title,
                        content: content,
                        dueAtIso: dueDate.map { iso.string(from: $0) },
                        supportsPrepare: true
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
        #else
        return []
        #endif
    }

    // MARK: - Source 3: Local Git / Workspace FS (macOS Native)

    private func collectGitWorkspaceSignals(directories: [String]) -> [PipiProactiveSignal] {
        #if os(macOS)
        var results: [PipiProactiveSignal] = []
        var visited = Set<String>()
        for rawDir in directories.prefix(5) {
            let path = rawDir.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, visited.insert(path).inserted else { continue }
            let gitDir = (path as NSString).appendingPathComponent(".git")
            guard FileManager.default.fileExists(atPath: gitDir) else { continue }

            let folderName = URL(fileURLWithPath: path).lastPathComponent
            let dirtyOut = Self.runGitCommand(["status", "--porcelain"], in: path) ?? ""
            let dirtyLines = dirtyOut
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let aheadOut = Self.runGitCommand(["rev-list", "--count", "@{u}..HEAD"], in: path)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
            let aheadCount = Int(aheadOut) ?? 0

            if dirtyLines.count >= 5 || aheadCount >= 1 {
                var fragments: [String] = []
                if !dirtyLines.isEmpty { fragments.append("\(dirtyLines.count) uncommitted change(s)") }
                if aheadCount > 0 { fragments.append("\(aheadCount) unpushed commit(s)") }
                results.append(PipiProactiveSignal(
                    source: .gitWorkspace,
                    kind: "dirty_repo",
                    matter: "git:\(folderName)",
                    title: "\(folderName) · Git Workspace",
                    content: "Local repo \(folderName) has \(fragments.joined(separator: ", ")).",
                    workspacePath: path,
                    supportsPrepare: true
                ))
            }
        }
        return results
        #else
        return []
        #endif
    }

    #if os(macOS)
    private static func runGitCommand(_ args: [String], in directory: String) -> String? {
        guard let gitBin = PipiNativeMacRuntime.findExecutable("git") ?? (FileManager.default.isExecutableFile(atPath: "/usr/bin/git") ? "/usr/bin/git" : nil) else {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: gitBin)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - Source 4: Mac Device Telemetry

    private func collectDeviceTelemetrySignals() -> [PipiProactiveSignal] {
        let host = PipiNativeMacRuntime.sampleHostTelemetry()
        var results: [PipiProactiveSignal] = []
        if host.memoryUsedPct >= 88.0 {
            results.append(PipiProactiveSignal(
                source: .deviceTelemetry,
                kind: "memory_pressure",
                matter: "mac_memory_pressure",
                title: "Mac Memory Pressure (\(Int(host.memoryUsedPct.rounded()))%)",
                content: "\(host.displayName) memory usage is at \(Int(host.memoryUsedPct.rounded()))%. Consider pausing heavy local tasks.",
                isUrgent: host.memoryUsedPct >= 95.0,
                supportsPrepare: false
            ))
        }
        if let disk = host.diskUsedPct, disk >= 90.0 {
            results.append(PipiProactiveSignal(
                source: .deviceTelemetry,
                kind: "disk_pressure",
                matter: "mac_disk_pressure",
                title: "Mac Disk Space Low (\(Int(disk.rounded()))% used)",
                content: "\(host.displayName) disk usage reached \(Int(disk.rounded()))%.",
                isUrgent: disk >= 96.0,
                supportsPrepare: false
            ))
        }
        return results
    }

    // MARK: - Source 5: Local Notes / Follow-up Cues

    private func collectLocalNoteSignals(note: String) -> [PipiProactiveSignal] {
        let lines = note
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- [ ] ") || $0.lowercased().hasPrefix("todo:") }
        return lines.prefix(3).map { line in
            let cleaned = line
                .replacingOccurrences(of: "- [ ] ", with: "")
                .replacingOccurrences(of: "TODO:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            return PipiProactiveSignal(
                source: .chatPocketNote,
                kind: "note_todo",
                matter: String(cleaned.prefix(48)),
                title: String(cleaned.prefix(64)),
                content: "Open follow-up from personal notes: \(cleaned)",
                supportsPrepare: true
            )
        }
    }
}
