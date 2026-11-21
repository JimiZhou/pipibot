// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// GitHub Release Auto-Updater (`https://api.github.com/repos/JimiZhou/pipibot/releases`)
// - SemVer comparison & architecture-aware asset matching (arm64 / x86_64 DMG + SHA-256)
// - Download progress, SHA-256 integrity verification, DMG mount + atomic .app swap + relaunch.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if os(macOS)
import AppKit
#endif

public struct PipiGitHubReleaseAsset: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let downloadURL: String
    public let sizeBytes: Int64

    public init(name: String, downloadURL: String, sizeBytes: Int64) {
        self.name = name
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
    }
}

public struct PipiGitHubReleaseInfo: Codable, Sendable, Equatable {
    public let tagName: String
    public let version: String
    public let title: String
    public let body: String
    public let htmlURL: String
    public let publishedAt: String?
    public let dmgAsset: PipiGitHubReleaseAsset?
    public let sha256Asset: PipiGitHubReleaseAsset?

    public init(
        tagName: String,
        version: String,
        title: String,
        body: String,
        htmlURL: String,
        publishedAt: String?,
        dmgAsset: PipiGitHubReleaseAsset?,
        sha256Asset: PipiGitHubReleaseAsset?
    ) {
        self.tagName = tagName
        self.version = version
        self.title = title
        self.body = body
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.dmgAsset = dmgAsset
        self.sha256Asset = sha256Asset
    }
}

public enum PipiAppUpdateState: Sendable, Equatable {
    case idle
    case checking
    case upToDate(version: String, checkedAt: Date)
    case updateAvailable(PipiGitHubReleaseInfo)
    case downloading(PipiGitHubReleaseInfo, progress: Double)
    case verifying(PipiGitHubReleaseInfo)
    case installing(PipiGitHubReleaseInfo)
    case error(String)

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing:
            return true
        case .idle, .upToDate, .updateAvailable, .error:
            return false
        }
    }

    public var availableRelease: PipiGitHubReleaseInfo? {
        switch self {
        case .updateAvailable(let info),
             .downloading(let info, _),
             .verifying(let info),
             .installing(let info):
            return info
        default:
            return nil
        }
    }
}

public enum PipiGitHubUpdaterLogic {
    public static let defaultRepoOwner = "JimiZhou"
    public static let defaultRepoName = "pipibot"
    public static let bundleIdentifier = "ai.pipibot.mac"

    public static var currentArch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    public static func normalizeVersion(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            trimmed.removeFirst()
        }
        return trimmed
    }

    /// Compares two semantic version strings (e.g. "0.10.0" vs "0.9.0", "0.10.0-beta" vs "0.10.0").
    public static func compareSemVer(_ lhsRaw: String, _ rhsRaw: String) -> ComparisonResult {
        let lhsClean = normalizeVersion(lhsRaw)
        let rhsClean = normalizeVersion(rhsRaw)

        let lhsSplit = lhsClean.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let rhsSplit = rhsClean.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        let lhsNums = lhsSplit[0].split(separator: ".").map { Int($0) ?? 0 }
        let rhsNums = rhsSplit[0].split(separator: ".").map { Int($0) ?? 0 }

        let count = max(lhsNums.count, rhsNums.count)
        for idx in 0..<count {
            let l = idx < lhsNums.count ? lhsNums[idx] : 0
            let r = idx < rhsNums.count ? rhsNums[idx] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }

        let lhsPre = lhsSplit.count > 1 ? String(lhsSplit[1]) : ""
        let rhsPre = rhsSplit.count > 1 ? String(rhsSplit[1]) : ""
        if lhsPre.isEmpty && !rhsPre.isEmpty { return .orderedDescending }
        if !lhsPre.isEmpty && rhsPre.isEmpty { return .orderedAscending }
        if lhsPre == rhsPre { return .orderedSame }
        return lhsPre.compare(rhsPre, options: [.numeric, .caseInsensitive])
    }

    public static func selectBestAsset(
        from assets: [PipiGitHubReleaseAsset],
        arch: String = currentArch
    ) -> (dmg: PipiGitHubReleaseAsset?, sha256: PipiGitHubReleaseAsset?) {
        let dmgAssets = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        let preferredDmg = dmgAssets.first(where: { $0.name.lowercased().contains(arch.lowercased()) })
            ?? dmgAssets.first(where: { $0.name.lowercased().contains("universal") })
            ?? dmgAssets.first

        let shaAsset: PipiGitHubReleaseAsset? = {
            if let preferredDmg {
                let exactSha = "\(preferredDmg.name).sha256"
                if let found = assets.first(where: { $0.name == exactSha }) {
                    return found
                }
            }
            return assets.first(where: { $0.name.lowercased().hasSuffix(".sha256") })
        }()

        return (preferredDmg, shaAsset)
    }

    public static func parseSHA256Text(_ text: String) -> String? {
        let tokens = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
        for token in tokens {
            let str = String(token).lowercased()
            if str.count == 64, str.allSatisfy({ $0.isHexDigit }) {
                return str
            }
        }
        return nil
    }

    public static func parseReleaseJSON(
        _ data: Data,
        currentVersion: String,
        preferredArch: String = currentArch
    ) -> (info: PipiGitHubReleaseInfo, isNewer: Bool)? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return parseReleaseObject(obj, currentVersion: currentVersion, preferredArch: preferredArch)
    }

    public static func parseReleasesArrayJSON(
        _ data: Data,
        currentVersion: String,
        preferredArch: String = currentArch
    ) -> (info: PipiGitHubReleaseInfo, isNewer: Bool)? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return nil
        }
        for obj in list {
            if (obj["draft"] as? Bool) == true { continue }
            if (obj["prerelease"] as? Bool) == true { continue }
            if let parsed = parseReleaseObject(obj, currentVersion: currentVersion, preferredArch: preferredArch) {
                return parsed
            }
        }
        return nil
    }

    private static func parseReleaseObject(
        _ obj: [String: Any],
        currentVersion: String,
        preferredArch: String
    ) -> (info: PipiGitHubReleaseInfo, isNewer: Bool)? {
        guard let tagName = obj["tag_name"] as? String, !tagName.isEmpty else {
            return nil
        }
        if (obj["draft"] as? Bool) == true { return nil }

        let version = normalizeVersion(tagName)
        let title = (obj["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tagName
        let body = (obj["body"] as? String) ?? ""
        let htmlURL = (obj["html_url"] as? String) ?? "https://github.com/\(defaultRepoOwner)/\(defaultRepoName)/releases/tag/\(tagName)"
        let publishedAt = obj["published_at"] as? String

        let rawAssets = (obj["assets"] as? [[String: Any]]) ?? []
        let assets: [PipiGitHubReleaseAsset] = rawAssets.compactMap { a in
            guard let name = a["name"] as? String,
                  let dl = a["browser_download_url"] as? String else { return nil }
            let size = (a["size"] as? NSNumber)?.int64Value ?? 0
            return PipiGitHubReleaseAsset(name: name, downloadURL: dl, sizeBytes: size)
        }

        let best = selectBestAsset(from: assets, arch: preferredArch)
        let info = PipiGitHubReleaseInfo(
            tagName: tagName,
            version: version,
            title: title,
            body: body,
            htmlURL: htmlURL,
            publishedAt: publishedAt,
            dmgAsset: best.dmg,
            sha256Asset: best.sha256
        )
        let isNewer = compareSemVer(version, currentVersion) == .orderedDescending
        return (info, isNewer)
    }

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return ""
        #endif
    }

    /// Resolves the target `.app` bundle path to replace during an auto-update.
    public static func resolveInstallTargetAppPath(currentBundlePath: String = Bundle.main.bundlePath) -> String {
        let fm = FileManager.default
        if currentBundlePath.hasSuffix(".app") {
            let parentDir = (currentBundlePath as NSString).deletingLastPathComponent
            if fm.isWritableFile(atPath: currentBundlePath) || fm.isWritableFile(atPath: parentDir) {
                return currentBundlePath
            }
        }
        return "/Applications/PipiBot.app"
    }
}

@MainActor
@Observable
public final class PipiGitHubUpdateManager {
    public private(set) var state: PipiAppUpdateState = .idle
    public private(set) var lastCheckedAt: Date? = nil
    public private(set) var latestRelease: PipiGitHubReleaseInfo? = nil

    private let repoOwner: String
    private let repoName: String
    private let session: URLSession
    private var activeTask: Task<Void, Never>?

    public init(
        repoOwner: String = PipiGitHubUpdaterLogic.defaultRepoOwner,
        repoName: String = PipiGitHubUpdaterLogic.defaultRepoName,
        session: URLSession = .shared
    ) {
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.session = session
    }

    public func checkForUpdates(currentVersion: String, silent: Bool = false) async -> PipiAppUpdateState {
        if state.isBusy { return state }
        if !silent {
            state = .checking
        }

        let latestEndpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        let listEndpoint = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases?per_page=8"

        do {
            let parsedResult: (info: PipiGitHubReleaseInfo, isNewer: Bool)?
            if let (data, status) = try await fetchGitHubAPI(urlString: latestEndpoint),
               (200...299).contains(status),
               let parsed = PipiGitHubUpdaterLogic.parseReleaseJSON(data, currentVersion: currentVersion) {
                parsedResult = parsed
            } else if let (listData, listStatus) = try await fetchGitHubAPI(urlString: listEndpoint),
                      (200...299).contains(listStatus) {
                parsedResult = PipiGitHubUpdaterLogic.parseReleasesArrayJSON(listData, currentVersion: currentVersion)
            } else {
                parsedResult = nil
            }

            let now = Date()
            lastCheckedAt = now

            guard let result = parsedResult else {
                if !silent {
                    state = .error("暂未查询到 GitHub Release 信息，请检查网络连接。")
                }
                return state
            }

            latestRelease = result.info
            if result.isNewer {
                state = .updateAvailable(result.info)
            } else {
                state = .upToDate(version: currentVersion, checkedAt: now)
            }
            return state
        } catch {
            if !silent {
                state = .error("检查更新失败：\(error.localizedDescription)")
            }
            return state
        }
    }

    public func downloadAndInstallUpdate(
        _ release: PipiGitHubReleaseInfo,
        onBeforeTerminate: @escaping @MainActor () -> Void
    ) {
        guard !state.isBusy else { return }
        guard let dmgAsset = release.dmgAsset,
              let dmgURL = URL(string: dmgAsset.downloadURL) else {
            state = .error("当前 Release 未附带 macOS DMG 安装包，请前往 GitHub 手动下载。")
            return
        }

        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            #if os(macOS)
            do {
                self.state = .downloading(release, progress: 0.05)

                let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("PiPiBot/Updates/\(release.version)", isDirectory: true)
                    ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pipibot-update-\(release.version)", isDirectory: true)
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

                let localDmgURL = cacheDir.appendingPathComponent(dmgAsset.name)
                try? FileManager.default.removeItem(at: localDmgURL)

                try await self.downloadFile(from: dmgURL, to: localDmgURL) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.state = .downloading(release, progress: progress)
                    }
                }

                self.state = .verifying(release)

                // Verify SHA-256 if `.sha256` asset is attached
                if let shaAsset = release.sha256Asset,
                   let shaURL = URL(string: shaAsset.downloadURL) {
                    var shaReq = URLRequest(url: shaURL)
                    shaReq.timeoutInterval = 20
                    shaReq.setValue("PiPiBot/\(release.version)", forHTTPHeaderField: "User-Agent")
                    let (shaData, shaResp) = try await self.session.data(for: shaReq)
                    if let http = shaResp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                       let expectedHash = PipiGitHubUpdaterLogic.parseSHA256Text(String(decoding: shaData, as: UTF8.self)) {
                        let actualHash = try PipiGitHubUpdaterLogic.sha256Hex(of: localDmgURL)
                        guard !actualHash.isEmpty, actualHash.lowercased() == expectedHash.lowercased() else {
                            self.state = .error("安装包 SHA-256 校验失败，已中止更新。")
                            return
                        }
                    }
                }

                self.state = .installing(release)
                let targetAppPath = PipiGitHubUpdaterLogic.resolveInstallTargetAppPath()
                try Self.stageAndLaunchInstallerScript(
                    dmgPath: localDmgURL.path,
                    targetAppPath: targetAppPath,
                    currentPID: ProcessInfo.processInfo.processIdentifier
                )

                onBeforeTerminate()
                try? await Task.sleep(for: .milliseconds(250))
                NSApplication.shared.terminate(nil)
            } catch is CancellationError {
                self.state = .updateAvailable(release)
            } catch {
                self.state = .error("自动更新失败：\(error.localizedDescription)")
            }
            #else
            self.state = .error("自动安装仅支持 macOS 桌面端。")
            #endif
        }
    }

    private func fetchGitHubAPI(urlString: String) async throws -> (Data, Int)? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PiPiBot-Mac-Updater", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func downloadFile(
        from remoteURL: URL,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var req = URLRequest(url: remoteURL)
        req.timeoutInterval = 180
        req.setValue("PiPiBot-Mac-Updater", forHTTPHeaderField: "User-Agent")

        let (asyncBytes, resp) = try await session.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "PipiUpdater", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "下载安装包返回 HTTP \(http.statusCode)"
            ])
        }

        let expectedLength = max(1, resp.expectedContentLength)
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destinationURL)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var received: Int64 = 0
        var lastReportedPct = -1

        for try await byte in asyncBytes {
            if Task.isCancelled { throw CancellationError() }
            buffer.append(byte)
            received += 1
            if buffer.count >= 65_536 {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                let pct = Int((Double(received) / Double(expectedLength)) * 100.0)
                if pct != lastReportedPct && resp.expectedContentLength > 0 {
                    lastReportedPct = pct
                    onProgress(min(0.98, Double(received) / Double(expectedLength)))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        onProgress(1.0)
    }

    #if os(macOS)
    private static func stageAndLaunchInstallerScript(
        dmgPath: String,
        targetAppPath: String,
        currentPID: Int32
    ) throws {
        let stageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-install-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

        let mountPoint = stageDir.appendingPathComponent("mnt", isDirectory: true).path
        let attachProc = Process()
        attachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attachProc.arguments = ["attach", dmgPath, "-nobrowse", "-readonly", "-mountpoint", mountPoint]
        try attachProc.run()
        attachProc.waitUntilExit()
        guard attachProc.terminationStatus == 0 else {
            throw NSError(domain: "PipiUpdater", code: Int(attachProc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "无法挂载 DMG 安装镜像"
            ])
        }

        let mountedApp = findAppBundle(in: mountPoint)
        guard let mountedApp else {
            detachDMG(at: mountPoint)
            throw NSError(domain: "PipiUpdater", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "DMG 镜像中未找到 PiPiBot.app"
            ])
        }

        // Verify code signature & bundle identifier before replacing running app
        let verifyProc = Process()
        verifyProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verifyProc.arguments = ["--verify", "--deep", "--strict", mountedApp]
        try verifyProc.run()
        verifyProc.waitUntilExit()
        guard verifyProc.terminationStatus == 0 else {
            detachDMG(at: mountPoint)
            throw NSError(domain: "PipiUpdater", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "新版应用签名验证未通过，已取消安装。"
            ])
        }

        let scriptURL = stageDir.appendingPathComponent("apply_update.sh")
        let escapedMount = shellSingleQuote(mountPoint)
        let escapedSrcApp = shellSingleQuote(mountedApp)
        let escapedDstApp = shellSingleQuote(targetAppPath)
        let escapedStage = shellSingleQuote(stageDir.path)

        let script = """
        #!/usr/bin/env bash
        set -euo pipefail
        PID=\(currentPID)
        for _ in $(seq 1 120); do
          if ! kill -0 "$PID" 2>/dev/null; then
            break
          fi
          sleep 0.25
        done
        DST=\(escapedDstApp)
        SRC=\(escapedSrcApp)
        MNT=\(escapedMount)
        BACKUP="${DST}.backup.$$"
        if [[ -d "$DST" ]]; then
          mv "$DST" "$BACKUP" || true
        fi
        if ditto "$SRC" "$DST"; then
          rm -rf "$BACKUP" || true
        else
          if [[ -d "$BACKUP" ]]; then
            mv "$BACKUP" "$DST" || true
          fi
          hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
          exit 1
        fi
        hdiutil detach "$MNT" -force >/dev/null 2>&1 || true
        open -n "$DST"
        rm -rf \(escapedStage) || true
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let runner = Process()
        runner.executableURL = URL(fileURLWithPath: "/bin/bash")
        runner.arguments = [scriptURL.path]
        runner.standardOutput = FileHandle.nullDevice
        runner.standardError = FileHandle.nullDevice
        try runner.run()
    }

    private static func findAppBundle(in mountPoint: String) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: mountPoint) else { return nil }
        if let exact = entries.first(where: { $0.lowercased() == "pipibot.app" }) {
            return (mountPoint as NSString).appendingPathComponent(exact)
        }
        if let anyApp = entries.first(where: { $0.lowercased().hasSuffix(".app") }) {
            return (mountPoint as NSString).appendingPathComponent(anyApp)
        }
        return nil
    }

    private static func detachDMG(at mountPoint: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = ["detach", mountPoint, "-force"]
        try? p.run()
        p.waitUntilExit()
    }

    private static func shellSingleQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
    #endif
}
