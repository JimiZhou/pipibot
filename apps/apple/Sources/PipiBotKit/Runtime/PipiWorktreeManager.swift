import Foundation

// MARK: - Git Worktree Isolation & Diff Review Manager

public enum PipiWorktreeError: LocalizedError, Sendable {
    case unsupportedPlatform
    case notAGitRepository(String)
    case gitCommandFailed(String)
    case mergeConflict(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Git worktree operations are only available on macOS/Linux hosts."
        case .notAGitRepository(let path):
            return "Path is not inside a Git repository: \(path)"
        case .gitCommandFailed(let msg):
            return "Git command failed: \(msg)"
        case .mergeConflict(let msg):
            return "Merge conflict detected: \(msg)"
        }
    }
}

public enum PipiWorktreeManager {

    /// Smart auto-isolation policy:
    /// - Always isolate when project/task explicitly requests `alwaysUseWorktree`.
    /// - Automatically isolate when running in group parallel lanes or when another active task already targets the same repo.
    /// - For single 1v1 tasks with no concurrency conflict, default to editing the active branch directly.
    public static func shouldIsolateWithWorktree(
        repoPath: String?,
        isGroupParallel: Bool,
        activeRepoTaskCount: Int,
        projectAlwaysUseWorktree: Bool
    ) -> Bool {
        guard let repoPath, !repoPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if projectAlwaysUseWorktree { return true }
        if isGroupParallel { return true }
        if activeRepoTaskCount > 0 { return true }
        return false
    }

    public static func sanitizeBranchSlug(_ text: String) -> String {
        let lower = text.lowercased()
        let allowed = CharacterSet.alphanumerics
        var slug = ""
        var prevDash = false
        for scalar in lower.unicodeScalars {
            if allowed.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                prevDash = false
            } else if !prevDash && !slug.isEmpty {
                slug.append("-")
                prevDash = true
            }
            if slug.count >= 28 { break }
        }
        let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "task" : trimmed
    }

    /// Build a focused follow-up prompt that sends review comments back to the Agent in the same Worktree.
    public static func buildSendBackPrompt(
        session: PipiWorktreeReviewSession,
        feedback: String,
        filePath: String? = nil,
        lineNumber: Int? = nil,
        lang: PipiResolvedLanguage = .zhHans
    ) -> String {
        let locationHint: String
        if let filePath, !filePath.isEmpty {
            if let lineNumber {
                locationHint = "`\(filePath):L\(lineNumber)`"
            } else {
                locationHint = "`\(filePath)`"
            }
        } else {
            locationHint = lang == .zhHans ? "整个改动" : "the overall diff"
        }

        if lang == .zhHans {
            return """
[Worktree Diff 审查打回]
请继续在隔离工作区 `\(session.worktreePath)`（分支 `\(session.branchName)`）内修改代码，解决以下审查意见（定位：\(locationHint)）：
> \(feedback)

修改完成后请自检变更并汇报更新后的改动摘要，不要主动合并或删除该 Worktree。
"""
        } else {
            return """
[Worktree Diff Review Feedback]
Continue working inside the isolated worktree `\(session.worktreePath)` (branch `\(session.branchName)`) and address this review comment (target: \(locationHint)):
> \(feedback)

Verify your changes after editing and summarize what changed. Do not merge or delete the worktree yourself.
"""
        }
    }

    #if os(macOS)
    @discardableResult
    private static func runGit(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let outText = String(data: outData, encoding: .utf8) ?? ""
        let errText = String(data: errData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            let detail = errText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? outText : errText
            throw PipiWorktreeError.gitCommandFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return outText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func detectGitRepoRoot(for path: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        let dir = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
        return try? runGit(["rev-parse", "--show-toplevel"], in: dir)
    }

    public static func currentBranch(in repoPath: String) -> String {
        if let branch = try? runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: repoPath),
           !branch.isEmpty, branch != "HEAD" {
            return branch
        }
        return (try? runGit(["rev-parse", "--short", "HEAD"], in: repoPath)) ?? "main"
    }

    private static func ensureWorktreesExcluded(in repoRoot: String) {
        guard let gitDir = try? runGit(["rev-parse", "--git-common-dir"], in: repoRoot) else { return }
        let resolvedGitDir = gitDir.hasPrefix("/") ? gitDir : (repoRoot as NSString).appendingPathComponent(gitDir)
        let infoDir = (resolvedGitDir as NSString).appendingPathComponent("info")
        let excludePath = (infoDir as NSString).appendingPathComponent("exclude")
        try? FileManager.default.createDirectory(atPath: infoDir, withIntermediateDirectories: true)
        let existing = (try? String(contentsOfFile: excludePath, encoding: .utf8)) ?? ""
        if !existing.contains(".pipibot-worktrees/") {
            let suffix = existing.isEmpty || existing.hasSuffix("\n") ? ".pipibot-worktrees/\n" : "\n.pipibot-worktrees/\n"
            try? (existing + suffix).write(toFile: excludePath, atomically: true, encoding: .utf8)
        }
    }

    public static func createWorktree(
        repoPath: String,
        taskTitle: String,
        botId: String,
        botName: String,
        conversationId: String? = nil,
        groupId: String? = nil
    ) throws -> PipiWorktreeReviewSession {
        guard let repoRoot = detectGitRepoRoot(for: repoPath) else {
            throw PipiWorktreeError.notAGitRepository(repoPath)
        }
        let baseBranch = currentBranch(in: repoRoot)
        ensureWorktreesExcluded(in: repoRoot)

        let shortId = String(UUID().uuidString.prefix(6)).lowercased()
        let slug = sanitizeBranchSlug(taskTitle)
        let branchName = "pipi/\(slug)-\(shortId)"
        let worktreesContainer = (repoRoot as NSString).appendingPathComponent(".pipibot-worktrees")
        try FileManager.default.createDirectory(atPath: worktreesContainer, withIntermediateDirectories: true)
        let worktreePath = (worktreesContainer as NSString).appendingPathComponent("\(slug)-\(shortId)")

        _ = try runGit(["worktree", "add", "-b", branchName, worktreePath, "HEAD"], in: repoRoot)

        return PipiWorktreeReviewSession(
            repoPath: repoRoot,
            worktreePath: worktreePath,
            branchName: branchName,
            baseBranch: baseBranch,
            taskTitle: taskTitle,
            botId: botId,
            botName: botName,
            conversationId: conversationId,
            groupId: groupId,
            status: .active
        )
    }

    public static func captureDiffSnapshot(for session: PipiWorktreeReviewSession) -> PipiWorktreeReviewSession {
        var updated = session
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        guard FileManager.default.fileExists(atPath: session.worktreePath) else {
            return updated
        }

        // Collect modified/staged/untracked files and diff against baseBranch
        let statusOutput = (try? runGit(["status", "--porcelain"], in: session.worktreePath)) ?? ""
        var statusByPath: [String: String] = [:]
        var untrackedFiles: [String] = []
        for rawLine in statusOutput.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard line.count >= 4 else { continue }
            let code = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if code == "??" {
                statusByPath[path] = "A"
                untrackedFiles.append(path)
            } else {
                statusByPath[path] = String(code.first ?? "M")
            }
        }

        // Include committed-on-branch diffs + working tree diffs relative to baseBranch
        let numstat = (try? runGit(["diff", "--numstat", session.baseBranch], in: session.worktreePath))
            ?? (try? runGit(["diff", "--numstat", "HEAD"], in: session.worktreePath))
            ?? ""
        var fileMap: [String: PipiWorktreeFileChange] = [:]
        for line in numstat.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            let adds = Int(parts[0]) ?? 0
            let dels = Int(parts[1]) ?? 0
            let path = String(parts[2])
            let st = statusByPath[path] ?? "M"
            fileMap[path] = PipiWorktreeFileChange(path: path, status: st, additions: adds, deletions: dels)
        }

        // Append untracked files that are not yet in git diff
        var untrackedDiffChunks: [String] = []
        for path in untrackedFiles where fileMap[path] == nil {
            let fullPath = (session.worktreePath as NSString).appendingPathComponent(path)
            if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                let lineCount = content.split(separator: "\n", omittingEmptySubsequences: false).count
                fileMap[path] = PipiWorktreeFileChange(path: path, status: "A", additions: lineCount, deletions: 0)
                let previewLines = content.split(separator: "\n", omittingEmptySubsequences: false).prefix(80).map { "+\($0)" }.joined(separator: "\n")
                untrackedDiffChunks.append("--- /dev/null\n+++ b/\(path)\n@@ -0,0 +1,\(lineCount) @@\n\(previewLines)")
            } else {
                fileMap[path] = PipiWorktreeFileChange(path: path, status: "A", additions: 0, deletions: 0)
            }
        }

        let trackedDiff = (try? runGit(["diff", session.baseBranch], in: session.worktreePath))
            ?? (try? runGit(["diff", "HEAD"], in: session.worktreePath))
            ?? ""
        let combinedDiff = ([trackedDiff] + untrackedDiffChunks).filter { !$0.isEmpty }.joined(separator: "\n\n")
        let cappedDiff = combinedDiff.count > 80_000
            ? String(combinedDiff.prefix(80_000)) + "\n... [diff truncated at 80KB]"
            : combinedDiff

        let sortedFiles = fileMap.values.sorted { $0.path < $1.path }
        updated.files = sortedFiles
        updated.unifiedDiff = cappedDiff
        let adds = updated.totalAdditions
        let dels = updated.totalDeletions
        if sortedFiles.isEmpty {
            updated.diffSummary = "No file changes detected yet."
        } else {
            updated.diffSummary = "\(sortedFiles.count) file(s) changed (+\(adds) / -\(dels))"
            if updated.status == .active || updated.status == .changesRequested {
                updated.status = .readyForReview
            }
        }
        return updated
    }

    public static func mergeAndCleanup(
        session: PipiWorktreeReviewSession,
        strategy: PipiWorktreeMergeStrategy = .squash,
        commitMessage: String? = nil
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: session.worktreePath) else {
            throw PipiWorktreeError.gitCommandFailed("Worktree directory no longer exists: \(session.worktreePath)")
        }

        let msg = (commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
            ?? "feat(pipi): \(session.taskTitle)"

        // 1. Commit any uncommitted changes inside the isolated worktree
        let dirty = (try? runGit(["status", "--porcelain"], in: session.worktreePath)) ?? ""
        if !dirty.isEmpty {
            _ = try runGit(["add", "-A"], in: session.worktreePath)
            _ = try runGit(["commit", "-m", msg], in: session.worktreePath)
        }

        if strategy == .keepBranchForPR {
            return "Committed changes on branch `\(session.branchName)` (worktree preserved at `\(session.worktreePath)` for PR)."
        }

        // 2. Merge into baseBranch inside repoPath
        let activeMainBranch = currentBranch(in: session.repoPath)
        if activeMainBranch != session.baseBranch {
            _ = try runGit(["checkout", session.baseBranch], in: session.repoPath)
        }

        do {
            switch strategy {
            case .squash:
                _ = try runGit(["merge", "--squash", session.branchName], in: session.repoPath)
                let stagedAfterSquash = (try? runGit(["status", "--porcelain"], in: session.repoPath)) ?? ""
                if !stagedAfterSquash.isEmpty {
                    _ = try runGit(["commit", "-m", msg], in: session.repoPath)
                }
            case .mergeCommit:
                _ = try runGit(["merge", "--no-ff", "-m", msg, session.branchName], in: session.repoPath)
            case .keepBranchForPR:
                break
            }
        } catch {
            // Abort partial merge cleanly so main repo isn't left broken
            _ = try? runGit(["merge", "--abort"], in: session.repoPath)
            _ = try? runGit(["reset", "--merge"], in: session.repoPath)
            throw PipiWorktreeError.mergeConflict(error.localizedDescription)
        }

        // 3. Remove worktree & delete temporary branch
        _ = try? runGit(["worktree", "remove", "--force", session.worktreePath], in: session.repoPath)
        _ = try? runGit(["branch", "-D", session.branchName], in: session.repoPath)
        return "Merged `\(session.branchName)` into `\(session.baseBranch)` (\(strategy.rawValue)) and cleaned up worktree."
    }

    public static func discardAndCleanup(session: PipiWorktreeReviewSession) throws {
        _ = try? runGit(["worktree", "remove", "--force", session.worktreePath], in: session.repoPath)
        _ = try? runGit(["branch", "-D", session.branchName], in: session.repoPath)
        if FileManager.default.fileExists(atPath: session.worktreePath) {
            try? FileManager.default.removeItem(atPath: session.worktreePath)
        }
    }
    #else
    public static func detectGitRepoRoot(for path: String) -> String? { nil }
    public static func currentBranch(in repoPath: String) -> String { "main" }
    public static func createWorktree(
        repoPath: String,
        taskTitle: String,
        botId: String,
        botName: String,
        conversationId: String? = nil,
        groupId: String? = nil
    ) throws -> PipiWorktreeReviewSession {
        throw PipiWorktreeError.unsupportedPlatform
    }
    public static func captureDiffSnapshot(for session: PipiWorktreeReviewSession) -> PipiWorktreeReviewSession {
        session
    }
    public static func mergeAndCleanup(
        session: PipiWorktreeReviewSession,
        strategy: PipiWorktreeMergeStrategy = .squash,
        commitMessage: String? = nil
    ) throws -> String {
        throw PipiWorktreeError.unsupportedPlatform
    }
    public static func discardAndCleanup(session: PipiWorktreeReviewSession) throws {
        throw PipiWorktreeError.unsupportedPlatform
    }
    #endif
}
