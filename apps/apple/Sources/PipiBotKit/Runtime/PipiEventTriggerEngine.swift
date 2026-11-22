import Foundation
import CryptoKit

// MARK: - Event-Driven Routine Trigger Engine (Cron, Webhook, FS/Git, Channel, Health)

public enum PipiEventTriggerEngine {

    // MARK: 1. Anti-Storm Cooldown

    public static func isWithinCooldown(
        lastRunAt: String?,
        cooldownSeconds: Int,
        now: Date = Date()
    ) -> Bool {
        guard let lastRunAt, !lastRunAt.isEmpty,
              let lastDate = ISO8601DateFormatter().date(from: lastRunAt) else {
            return false
        }
        return now.timeIntervalSince(lastDate) < Double(max(5, cooldownSeconds))
    }

    // MARK: 2. Standard 5-Field Cron Matcher ("min hour dom month dow")

    public static func matchesCron(_ expression: String, date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let fields = expression
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard fields.count == 5 else { return false }

        let comps = calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: date)
        guard let minute = comps.minute,
              let hour = comps.hour,
              let day = comps.day,
              let month = comps.month,
              let calendarWeekday = comps.weekday else {
            return false
        }
        // Convert Calendar weekday (1=Sun..7=Sat) to cron dow (0=Sun, 1=Mon..6=Sat)
        let cronDow = (calendarWeekday - 1) % 7

        return matchCronField(fields[0], value: minute, min: 0, max: 59)
            && matchCronField(fields[1], value: hour, min: 0, max: 23)
            && matchCronField(fields[2], value: day, min: 1, max: 31)
            && matchCronField(fields[3], value: month, min: 1, max: 12)
            && matchCronField(fields[4], value: cronDow, min: 0, max: 7, isDow: true)
    }

    private static func matchCronField(_ field: String, value: Int, min: Int, max: Int, isDow: Bool = false) -> Bool {
        for part in field.split(separator: ",").map(String.init) {
            let stepParts = part.split(separator: "/").map(String.init)
            let rangeSpec = stepParts[0]
            let step = stepParts.count == 2 ? (Int(stepParts[1]) ?? 0) : 1
            if step <= 0 { continue }

            if rangeSpec == "*" {
                if (value - min) % step == 0 { return true }
                continue
            }

            if rangeSpec.contains("-") {
                let bounds = rangeSpec.split(separator: "-").map(String.init)
                guard bounds.count == 2, var lo = Int(bounds[0]), var hi = Int(bounds[1]) else { continue }
                if isDow {
                    if lo == 7 { lo = 0 }
                    if hi == 7 { hi = 0 }
                }
                if lo <= hi {
                    if value >= lo && value <= hi && (value - lo) % step == 0 { return true }
                } else if isDow {
                    // Wrap around Sunday (e.g. 5-0)
                    if (value >= lo && value <= 6) || (value >= 0 && value <= hi) { return true }
                }
            } else if var exact = Int(rangeSpec) {
                if isDow && exact == 7 { exact = 0 }
                if exact >= min && exact <= max && value == exact { return true }
            }
        }
        return false
    }

    // MARK: 3. Webhook Signature / Bearer Secret Verification

    public static func computeWebhookHMAC(secret: String, body: Data) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
    }

    public static func verifyWebhookAuth(
        secret: String?,
        authorizationHeader: String?,
        signatureHeader: String?,
        body: Data
    ) -> Bool {
        guard let secret, !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        if let auth = authorizationHeader?.trimmingCharacters(in: .whitespacesAndNewlines),
           auth == "Bearer \(secret)" || auth == secret {
            return true
        }
        if let sig = signatureHeader?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            let expected = computeWebhookHMAC(secret: secret, body: body).lowercased()
            if sig == expected { return true }
        }
        return false
    }

    // MARK: 4. Channel Message Rule Matcher (WeChat / Group)

    public static func matchesChannelMessage(
        routine: PipiBotRoutine,
        channel: String,
        text: String
    ) -> Bool {
        guard routine.isEnabled, routine.triggerKind == .channelMessage else { return false }
        let filter = (routine.eventConfig.channelFilter ?? "any").lowercased()
        if filter != "any" && filter != channel.lowercased() {
            return false
        }
        guard let pattern = routine.eventConfig.messageKeyword?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pattern.isEmpty else {
            return false
        }
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 2 {
            let regexBody = String(pattern.dropFirst().dropLast())
            if let regex = try? NSRegularExpression(pattern: regexBody, options: [.caseInsensitive]) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                return regex.firstMatch(in: text, options: [], range: range) != nil
            }
        }
        return text.localizedCaseInsensitiveContains(pattern)
    }

    // MARK: 5. Host Health Threshold Matcher

    public static func evaluateHostHealth(
        routine: PipiBotRoutine,
        cpuPercent: Double,
        memoryPercent: Double,
        diskFreeGB: Double,
        offlineHostNames: [String]
    ) -> String? {
        guard routine.isEnabled,
              routine.triggerKind == .hostHealth,
              let metric = routine.eventConfig.healthMetric else {
            return nil
        }
        let threshold = routine.eventConfig.healthThreshold ?? 85.0
        switch metric {
        case .cpuPercent:
            if cpuPercent >= threshold {
                return "CPU usage \(Int(cpuPercent))% >= \(Int(threshold))%"
            }
        case .memoryPercent:
            if memoryPercent >= threshold {
                return "Memory usage \(Int(memoryPercent))% >= \(Int(threshold))%"
            }
        case .diskFreeGB:
            if diskFreeGB <= threshold {
                return "Free disk \(String(format: "%.1f", diskFreeGB))GB <= \(String(format: "%.1f", threshold))GB"
            }
        case .nodeOffline:
            if !offlineHostNames.isEmpty {
                return "Offline host(s): \(offlineHostNames.joined(separator: ", "))"
            }
        }
        return nil
    }

    // MARK: 6. Local Directory / Git Watch Fingerprint

    public static func computeWorkspaceFingerprint(path: String, watchGitEvents: Bool) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return nil }

        var tokens: [String] = []
        if isDir.boolValue {
            if let items = try? fm.contentsOfDirectory(atPath: path) {
                for name in items.sorted().prefix(120) where !name.hasPrefix(".pipibot-worktrees") && name != ".git" && name != "node_modules" && name != ".build" {
                    let full = (path as NSString).appendingPathComponent(name)
                    if let attrs = try? fm.attributesOfItem(atPath: full) {
                        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                        tokens.append("\(name):\(Int64(mtime)):\(size)")
                    }
                }
            }
            if watchGitEvents {
                let gitHeadPath = (path as NSString).appendingPathComponent(".git/HEAD")
                if let head = try? String(contentsOfFile: gitHeadPath, encoding: .utf8) {
                    let trimmedHead = head.trimmingCharacters(in: .whitespacesAndNewlines)
                    tokens.append("HEAD:\(trimmedHead)")
                    if trimmedHead.hasPrefix("ref: ") {
                        let refRel = String(trimmedHead.dropFirst(5))
                        let refFull = (path as NSString).appendingPathComponent(".git/\(refRel)")
                        if let sha = try? String(contentsOfFile: refFull, encoding: .utf8) {
                            tokens.append("SHA:\(sha.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                    }
                }
            }
        } else if let attrs = try? fm.attributesOfItem(atPath: path) {
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            tokens.append("FILE:\(Int64(mtime)):\(size)")
        }

        let joined = tokens.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
