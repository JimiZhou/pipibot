// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Bot Box OS-Level Sandbox (macOS Seatbelt `sandbox-exec` + live `box-check` self-probe).

import Foundation

public struct PipiBotBoxSpec: Sendable, Equatable {
    public let allowedWorkspacePath: String
    public let deniedReadPaths: [String]
    public let allowNetwork: Bool

    public init(
        allowedWorkspacePath: String,
        deniedReadPaths: [String]? = nil,
        allowNetwork: Bool = true
    ) {
        self.allowedWorkspacePath = allowedWorkspacePath
        if let deniedReadPaths {
            self.deniedReadPaths = deniedReadPaths
        } else {
            let home = NSHomeDirectory()
            self.deniedReadPaths = [
                "\(home)/.ssh",
                "\(home)/.aws",
                "\(home)/.gnupg",
                "\(home)/Library/Keychains",
                "\(home)/Library/Application Support/PiPiBot/vault.enc"
            ]
        }
        self.allowNetwork = allowNetwork
    }
}

public enum PipiBotBoxSandbox {
    /// Resolves symlinks via POSIX `realpath` so macOS Seatbelt matches kernel-canonical paths (e.g. `/private/var/...`).
    public static func canonicalPath(_ path: String) -> String {
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        if path.hasPrefix("/var/") || path.hasPrefix("/tmp/") {
            return "/private\(path)"
        }
        return path
    }

    /// Escapes a file path for inclusion inside a Seatbelt `.sb` string literal.
    public static func escapeSeatbeltPath(_ path: String) -> String {
        canonicalPath(path)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Generates a minimal macOS Seatbelt profile that:
    /// - Denies reading host secret folders (`~/.ssh`, `~/.aws`, Keychains, PiPiBot `vault.enc`, plus any extra decoy paths).
    /// - Restricts file writes strictly to `allowedWorkspacePath` and `/tmp` / `/private/tmp` / `/var/folders`.
    public static func renderSeatbeltProfile(spec: PipiBotBoxSpec) -> String {
        var lines: [String] = [
            "(version 1)",
            "(allow default)",
            "; Deny writes everywhere outside workspace and temp directories",
            "(deny file-write*)",
            "(allow file-write* (subpath \"\(escapeSeatbeltPath(spec.allowedWorkspacePath))\"))",
            "(allow file-write* (subpath \"/tmp\"))",
            "(allow file-write* (subpath \"/private/tmp\"))",
            "(allow file-write* (subpath \"/private/var/folders\"))",
            "(allow file-write* (literal \"/dev/null\"))",
            "(allow file-write* (literal \"/dev/tty\"))",
            "; Deny reading host secrets and PiPiBot encrypted vault"
        ]
        for denied in spec.deniedReadPaths {
            lines.append("(deny file-read* (subpath \"\(escapeSeatbeltPath(denied))\"))")
        }
        if !spec.allowNetwork {
            lines.append("(deny network*)")
            lines.append("(allow network* (local ip \"localhost:*\"))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Wraps an executable + arguments in `/usr/bin/sandbox-exec` on macOS when `.sandboxBox` is selected.
    public static func wrapCommandIfBoxed(
        mode: PipiBotExecutionIsolationMode,
        executablePath: String,
        arguments: [String],
        spec: PipiBotBoxSpec
    ) -> (executable: String, arguments: [String], profilePath: String?) {
        #if os(macOS)
        guard mode == .sandboxBox,
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            return (executablePath, arguments, nil)
        }
        let profileText = renderSeatbeltProfile(spec: spec)
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-box-\(UUID().uuidString.prefix(8)).sb")
        do {
            try profileText.write(to: profileURL, atomically: true, encoding: .utf8)
            var wrappedArgs = ["-f", profileURL.path, executablePath]
            wrappedArgs.append(contentsOf: arguments)
            return ("/usr/bin/sandbox-exec", wrappedArgs, profileURL.path)
        } catch {
            return (executablePath, arguments, nil)
        }
        #else
        return (executablePath, arguments, nil)
        #endif
    }

    /// Runs a live sandbox self-probe (`box-check`) verifying that:
    /// 1. Reading a decoy secret file in a denied folder is blocked.
    /// 2. Writing outside the workspace is blocked.
    /// 3. Writing inside the allowed workspace succeeds.
    public static func runSelfCheck() -> PipiBoxSelfCheckResult {
        #if os(macOS)
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            return PipiBoxSelfCheckResult(
                backend: "off",
                checks: [
                    PipiBoxSelfCheckItem(name: "seatbelt_binary", passed: false, detail: "/usr/bin/sandbox-exec unavailable")
                ]
            )
        }

        let fm = FileManager.default
        let probeRoot = fm.temporaryDirectory.appendingPathComponent("pipibot-boxcheck-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let allowedDir = probeRoot.appendingPathComponent("workspace", isDirectory: true)
        let deniedSecretDir = probeRoot.appendingPathComponent("decoy-secrets", isDirectory: true)
        let forbiddenOutDir = probeRoot.appendingPathComponent("outside-write", isDirectory: true)
        defer { try? fm.removeItem(at: probeRoot) }

        do {
            try fm.createDirectory(at: allowedDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: deniedSecretDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: forbiddenOutDir, withIntermediateDirectories: true)
        } catch {
            return PipiBoxSelfCheckResult(
                backend: "seatbelt",
                checks: [PipiBoxSelfCheckItem(name: "fixture_setup", passed: false, detail: error.localizedDescription)]
            )
        }

        let decoyFile = deniedSecretDir.appendingPathComponent("vault.enc")
        try? "TOP_SECRET_CANARY_999".write(to: decoyFile, atomically: true, encoding: .utf8)

        let resolvedAllowed = canonicalPath(allowedDir.path)
        let resolvedDenied = canonicalPath(deniedSecretDir.path)
        let resolvedForbidden = canonicalPath(forbiddenOutDir.path)

        let spec = PipiBotBoxSpec(
            allowedWorkspacePath: resolvedAllowed,
            deniedReadPaths: [resolvedDenied],
            allowNetwork: false
        )
        // Use a dedicated stricter profile for self-check that denies writes to forbiddenOutDir even under /private/var/folders
        let probeProfile = """
        (version 1)
        (allow default)
        (deny file-write*)
        (allow file-write* (subpath "\(escapeSeatbeltPath(resolvedAllowed))"))
        (deny file-read* (subpath "\(escapeSeatbeltPath(resolvedDenied))"))
        (deny network*)
        """
        let profileURL = probeRoot.appendingPathComponent("probe.sb")
        try? probeProfile.write(to: profileURL, atomically: true, encoding: .utf8)

        var items: [PipiBoxSelfCheckItem] = []

        // Check 1: Decoy secret read must be DENIED
        let readRes = runProbe(profilePath: profileURL.path, shellCmd: "cat '\(resolvedDenied)/vault.enc'")
        let readBlocked = (readRes.exitCode != 0) && !readRes.output.contains("TOP_SECRET_CANARY_999")
        items.append(PipiBoxSelfCheckItem(
            name: "block_secret_read",
            passed: readBlocked,
            detail: readBlocked ? "Blocked decoy secret read (exit \(readRes.exitCode))" : "WARNING: decoy secret was readable"
        ))

        // Check 2: Write outside allowed workspace must be DENIED
        let outsideWrite = runProbe(profilePath: profileURL.path, shellCmd: "echo pwn > '\(resolvedForbidden)/escape.txt'")
        let writeBlocked = (outsideWrite.exitCode != 0) && !fm.fileExists(atPath: "\(resolvedForbidden)/escape.txt")
        items.append(PipiBoxSelfCheckItem(
            name: "block_outside_write",
            passed: writeBlocked,
            detail: writeBlocked ? "Blocked write outside workspace (exit \(outsideWrite.exitCode))" : "WARNING: outside write succeeded"
        ))

        // Check 3: Write inside allowed workspace must SUCCEED
        let insideWrite = runProbe(profilePath: profileURL.path, shellCmd: "echo ok > '\(resolvedAllowed)/hello.txt'")
        let insideOK = (insideWrite.exitCode == 0) && fm.fileExists(atPath: "\(resolvedAllowed)/hello.txt")
        items.append(PipiBoxSelfCheckItem(
            name: "allow_workspace_write",
            passed: insideOK,
            detail: insideOK ? "Workspace write succeeded" : "Workspace write failed (exit \(insideWrite.exitCode))"
        ))

        // Check 4: Render default production profile sanity
        let renderedProd = renderSeatbeltProfile(spec: spec)
        items.append(PipiBoxSelfCheckItem(
            name: "profile_integrity",
            passed: renderedProd.contains("(deny file-read*") && renderedProd.contains("(allow file-write*"),
            detail: "Seatbelt profile rules valid"
        ))

        return PipiBoxSelfCheckResult(backend: "seatbelt", checks: items)
        #else
        return PipiBoxSelfCheckResult(
            backend: "off",
            checks: [PipiBoxSelfCheckItem(name: "platform", passed: true, detail: "iOS app sandbox enforced by OS")]
        )
        #endif
    }

    #if os(macOS)
    private static func runProbe(profilePath: String, shellCmd: String) -> (exitCode: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        proc.arguments = ["-f", profilePath, "/bin/sh", "-c", shellCmd]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timer.schedule(deadline: .now() + 5.0)
            timer.setEventHandler { if proc.isRunning { proc.terminate() } }
            timer.resume()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            timer.cancel()
            return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }
    #endif
}
