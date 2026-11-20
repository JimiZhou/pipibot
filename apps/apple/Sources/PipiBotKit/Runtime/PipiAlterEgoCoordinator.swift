// PiPiBot — Clean-room MIT implementation.
// Wave 3 (#05): Meta / AlterEgo In-Chat Autonomous Background Delegation with
// Isolated Writable `playground/<taskId>/` + Same-Session Read-Only Sharing + Steer / Cancel / Resume.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import Foundation

// MARK: - 1. Public Delegation Contracts

public struct PipiDelegationStep: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, Equatable {
        case running
        case succeeded
        case failed
    }

    public let id: String
    public var title: String
    public var status: Status
    public var detail: String?
    public let timestamp: String

    public init(
        id: String = "stp_\(UUID().uuidString.prefix(6).lowercased())",
        title: String,
        status: Status = .running,
        detail: String? = nil,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.timestamp = timestamp
    }
}

public struct PipiDelegationDirective: Codable, Equatable, Sendable {
    public var title: String
    public var goal: String
    public var expectedArtifacts: [String]?
    public var reason: String?

    public init(title: String, goal: String, expectedArtifacts: [String]? = nil, reason: String? = nil) {
        self.title = title
        self.goal = goal
        self.expectedArtifacts = expectedArtifacts
        self.reason = reason
    }
}

public struct PipiAlterEgoTask: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionId: String
    public let botId: String
    public var title: String
    public var goal: String
    public var status: PipiDelegationTaskStatus
    public let playgroundPath: String
    public var steps: [PipiDelegationStep]
    public var steerInstructions: [String]
    public var artifacts: [String]
    public var resultSummary: String?
    public var errorMessage: String?
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "ae_\(UUID().uuidString.prefix(8).lowercased())",
        sessionId: String,
        botId: String,
        title: String,
        goal: String,
        status: PipiDelegationTaskStatus = .queued,
        playgroundPath: String,
        steps: [PipiDelegationStep] = [],
        steerInstructions: [String] = [],
        artifacts: [String] = [],
        resultSummary: String? = nil,
        errorMessage: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sessionId = sessionId
        self.botId = botId
        self.title = title
        self.goal = goal
        self.status = status
        self.playgroundPath = playgroundPath
        self.steps = steps
        self.steerInstructions = steerInstructions
        self.artifacts = artifacts
        self.resultSummary = resultSummary
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PipiAlterEgoError: Error, LocalizedError, Sendable, Equatable {
    case unknownTask(String)
    case invalidPath(String)
    case pathTraversalDenied(String)
    case crossSessionDenied
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unknownTask(let id): return "Unknown AlterEgo task: \(id)"
        case .invalidPath(let p): return "Invalid playground path: \(p)"
        case .pathTraversalDenied(let p): return "Path traversal rejected outside playground: \(p)"
        case .crossSessionDenied: return "cross_session_denied: AlterEgo tasks may only read playgrounds in the same session."
        case .cancelled: return "AlterEgo task cancelled."
        }
    }
}

public struct PipiAlterEgoRunnerContext: Sendable {
    public let taskId: String
    public let sessionId: String
    public let botId: String
    public let title: String
    public let goal: String
    public let consumeSteerInstructions: @Sendable () async -> [String]
    public let reportStep: @Sendable (String, PipiDelegationStep.Status, String?) async -> Void
    public let writeArtifact: @Sendable (String, String) async throws -> URL
    public let readSessionArtifact: @Sendable (String, String) async throws -> String
}

public typealias PipiAlterEgoRunner = @Sendable (PipiAlterEgoRunnerContext) async throws -> String

// MARK: - 2. Autonomous Delegation Directive Detector

public enum PipiDelegationDetector {
    private static let longTaskKeywords: [String] = [
        "deep research", "comprehensive report", "full audit", "benchmark across",
        "background task", "parallel draft", "深度调研", "全面审计", "批量重构",
        "后台并行", "完整竞品分析", "系统对比报告", "整理全部文件"
    ]

    public static func extractDirective(from text: String) -> PipiDelegationDirective? {
        guard let startRange = text.range(of: "<pipibot_delegate>", options: .caseInsensitive),
              let endRange = text.range(of: "</pipibot_delegate>", options: .caseInsensitive, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        let jsonStr = String(text[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonStr.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(PipiDelegationDirective.self, from: data) else {
            return nil
        }
        let cleanTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGoal = parsed.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanGoal.isEmpty else { return nil }
        return PipiDelegationDirective(
            title: cleanTitle,
            goal: cleanGoal,
            expectedArtifacts: parsed.expectedArtifacts,
            reason: parsed.reason
        )
    }

    public static func shouldAutoDelegate(prompt: String) -> Bool {
        let lower = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.count >= 12 else { return false }
        return longTaskKeywords.contains { lower.contains($0) }
    }
}

// MARK: - 3. PipiAlterEgoCoordinator

@MainActor
public final class PipiAlterEgoCoordinator {
    public let rootURL: URL
    public var onChange: (() -> Void)?

    private weak var scheduler: PipiModelScheduler?
    private let defaultRunner: PipiAlterEgoRunner

    public private(set) var tasks: [PipiAlterEgoTask] = []
    private var pendingSteers: [String: [String]] = [:]
    private var activeSwiftTasks: [String: Task<Void, Never>] = [:]

    public init(
        rootURL: URL,
        scheduler: PipiModelScheduler? = nil,
        defaultRunner: PipiAlterEgoRunner? = nil
    ) {
        self.rootURL = rootURL
        self.scheduler = scheduler
        self.defaultRunner = defaultRunner ?? Self.makeDefaultOfflineRunner()
    }

    public func attachScheduler(_ scheduler: PipiModelScheduler?) {
        self.scheduler = scheduler
    }

    public func restorePersistedTasks(_ persisted: [PipiAlterEgoTask]) {
        self.tasks = persisted.map { task in
            var copy = task
            if copy.status == .running || copy.status == .queued {
                copy.status = .paused
            }
            return copy
        }
    }

    public func tasks(forSession sessionId: String) -> [PipiAlterEgoTask] {
        tasks
            .filter { $0.sessionId == sessionId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func task(id: String) -> PipiAlterEgoTask? {
        tasks.first(where: { $0.id == id })
    }

    public static func sanitizeSegment(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        })
        return cleaned.isEmpty || cleaned == "." || cleaned == ".." ? "item" : cleaned
    }

    public func playgroundDirectory(sessionId: String, taskId: String) -> URL {
        rootURL
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(Self.sanitizeSegment(sessionId), isDirectory: true)
            .appendingPathComponent("playground", isDirectory: true)
            .appendingPathComponent(Self.sanitizeSegment(taskId), isDirectory: true)
    }

    private static func resolveConfinedPath(baseDir: URL, relativePath: String) throws -> URL {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            throw PipiAlterEgoError.invalidPath(relativePath)
        }
        let baseStd = baseDir.standardizedFileURL
        let targetStd = baseStd.appendingPathComponent(trimmed).standardizedFileURL
        let basePrefix = baseStd.path.hasSuffix("/") ? baseStd.path : baseStd.path + "/"
        guard targetStd.path.hasPrefix(basePrefix) else {
            throw PipiAlterEgoError.pathTraversalDenied(relativePath)
        }
        return targetStd
    }

    // MARK: - Spawn, Steer, Cancel, Resume

    @discardableResult
    public func spawnTask(
        sessionId: String,
        botId: String,
        title: String,
        goal: String,
        endpointKey: String = "alter-ego",
        runner: PipiAlterEgoRunner? = nil
    ) -> PipiAlterEgoTask {
        let id = "ae_\(UUID().uuidString.prefix(8).lowercased())"
        let pgDir = playgroundDirectory(sessionId: sessionId, taskId: id)
        try? FileManager.default.createDirectory(at: pgDir, withIntermediateDirectories: true)

        let task = PipiAlterEgoTask(
            id: id,
            sessionId: sessionId,
            botId: botId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .queued,
            playgroundPath: pgDir.path
        )
        tasks.insert(task, at: 0)
        pendingSteers[id] = []
        onChange?()
        launchExecution(taskId: id, endpointKey: endpointKey, runner: runner ?? defaultRunner)
        return task
    }

    @discardableResult
    public func steerTask(id: String, instruction: String) -> Bool {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = tasks.firstIndex(where: { $0.id == id }) else { return false }
        tasks[idx].steerInstructions.append(trimmed)
        tasks[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        pendingSteers[id, default: []].append(trimmed)
        onChange?()
        return true
    }

    @discardableResult
    public func cancelTask(id: String) -> Bool {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return false }
        activeSwiftTasks[id]?.cancel()
        activeSwiftTasks.removeValue(forKey: id)
        if !tasks[idx].status.isTerminal {
            tasks[idx].status = .cancelled
            tasks[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            onChange?()
            return true
        }
        return false
    }

    @discardableResult
    public func resumeTask(
        id: String,
        additionalInstruction: String? = nil,
        endpointKey: String = "alter-ego",
        runner: PipiAlterEgoRunner? = nil
    ) -> PipiAlterEgoTask? {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        if let extra = additionalInstruction, !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = steerTask(id: id, instruction: extra)
        }
        if tasks[idx].status == .running || tasks[idx].status == .queued {
            return tasks[idx]
        }
        tasks[idx].status = .queued
        tasks[idx].errorMessage = nil
        tasks[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        onChange?()
        launchExecution(taskId: id, endpointKey: endpointKey, runner: runner ?? defaultRunner)
        return tasks[idx]
    }

    public func waitForTask(id: String) async -> PipiAlterEgoTask? {
        if let active = activeSwiftTasks[id] {
            await active.value
        }
        return task(id: id)
    }

    // MARK: - Isolated Write & Same-Session Read-Only Artifact Access

    public func writeArtifact(taskId: String, relativePath: String, content: String) throws -> URL {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else {
            throw PipiAlterEgoError.unknownTask(taskId)
        }
        let baseDir = URL(fileURLWithPath: tasks[idx].playgroundPath, isDirectory: true)
        let target = try Self.resolveConfinedPath(baseDir: baseDir, relativePath: relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let clean = PipiWikiTextUtilities.scrubSecrets(content)
        try Data(clean.utf8).write(to: target, options: .atomic)
        let normalizedRel = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tasks[idx].artifacts.contains(normalizedRel) {
            tasks[idx].artifacts.append(normalizedRel)
            tasks[idx].artifacts.sort()
        }
        tasks[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        onChange?()
        return target
    }

    public func readSessionArtifact(readerTaskId: String, sourceTaskId: String, relativePath: String) throws -> String {
        guard let reader = task(id: readerTaskId), let source = task(id: sourceTaskId) else {
            throw PipiAlterEgoError.unknownTask(sourceTaskId)
        }
        guard reader.sessionId == source.sessionId else {
            throw PipiAlterEgoError.crossSessionDenied
        }
        let baseDir = URL(fileURLWithPath: source.playgroundPath, isDirectory: true)
        let target = try Self.resolveConfinedPath(baseDir: baseDir, relativePath: relativePath)
        return try String(contentsOf: target, encoding: .utf8)
    }

    // MARK: - Execution Pipeline via PipiModelScheduler (.delegatedTask)

    private func launchExecution(taskId: String, endpointKey: String, runner: @escaping PipiAlterEgoRunner) {
        let swiftTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.activeSwiftTasks.removeValue(forKey: taskId)
                self.onChange?()
            }

            var lease: PipiScheduledLease?
            do {
                if let scheduler = self.scheduler {
                    lease = try await scheduler.acquire(
                        endpointKey: endpointKey,
                        priority: .delegatedTask,
                        canYield: { true }
                    )
                }
                if Task.isCancelled { throw CancellationError() }
                guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }) else { return }
                self.tasks[idx].status = .running
                self.tasks[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
                self.onChange?()

                let snap = self.tasks[idx]
                let ctx = PipiAlterEgoRunnerContext(
                    taskId: snap.id,
                    sessionId: snap.sessionId,
                    botId: snap.botId,
                    title: snap.title,
                    goal: snap.goal,
                    consumeSteerInstructions: { @MainActor [weak self] in
                        guard let self else { return [] }
                        let drained = self.pendingSteers[taskId] ?? []
                        self.pendingSteers[taskId] = []
                        return drained
                    },
                    reportStep: { @MainActor [weak self] title, status, detail in
                        guard let self, let i = self.tasks.firstIndex(where: { $0.id == taskId }) else { return }
                        self.tasks[i].steps.append(PipiDelegationStep(title: title, status: status, detail: detail))
                        self.tasks[i].updatedAt = ISO8601DateFormatter().string(from: Date())
                        self.onChange?()
                    },
                    writeArtifact: { @MainActor [weak self] relPath, body in
                        guard let self else { throw PipiAlterEgoError.cancelled }
                        return try self.writeArtifact(taskId: taskId, relativePath: relPath, content: body)
                    },
                    readSessionArtifact: { @MainActor [weak self] sourceId, relPath in
                        guard let self else { throw PipiAlterEgoError.cancelled }
                        return try self.readSessionArtifact(readerTaskId: taskId, sourceTaskId: sourceId, relativePath: relPath)
                    }
                )

                let summary = try await runner(ctx)
                lease?.release()
                lease = nil

                if Task.isCancelled { throw CancellationError() }
                if let i = self.tasks.firstIndex(where: { $0.id == taskId }) {
                    self.tasks[i].status = .completed
                    self.tasks[i].resultSummary = summary
                    self.tasks[i].updatedAt = ISO8601DateFormatter().string(from: Date())
                }
            } catch is CancellationError {
                lease?.release()
                if let i = self.tasks.firstIndex(where: { $0.id == taskId }) {
                    self.tasks[i].status = .cancelled
                    self.tasks[i].updatedAt = ISO8601DateFormatter().string(from: Date())
                }
            } catch {
                lease?.release()
                if let i = self.tasks.firstIndex(where: { $0.id == taskId }) {
                    self.tasks[i].status = .failed
                    self.tasks[i].errorMessage = error.localizedDescription
                    self.tasks[i].updatedAt = ISO8601DateFormatter().string(from: Date())
                }
            }
        }
        activeSwiftTasks[taskId] = swiftTask
    }

    private static func makeDefaultOfflineRunner() -> PipiAlterEgoRunner {
        { ctx in
            await ctx.reportStep("Analyzing delegated objective", .running, nil)
            let steers = await ctx.consumeSteerInstructions()
            var lines = ["# \(ctx.title)", "", "Goal: \(ctx.goal)"]
            if !steers.isEmpty {
                lines.append("")
                lines.append("## Mid-Flight Steer Directives")
                lines.append(contentsOf: steers.map { "- \($0)" })
            }
            _ = try await ctx.writeArtifact("result.md", lines.joined(separator: "\n"))
            await ctx.reportStep("Wrote deliverable to playground/result.md", .succeeded, "result.md")
            return "Completed \"\(ctx.title)\" (saved playground/result.md)."
        }
    }
}
