// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Native macOS Omnipotent Assistant Capabilities:
// - System Permissions Guidance & Live Probing (Messages/SMS, Mail, Calendar, Reminders, Screen Recording, Accessibility, Mic/Speech, Dev Toolchains)
// - Native Messages (iMessage/SMS) & Mail.app integration
// - Real Mac Screenshot, Screen Video Recording, Voice Clip Synthesis, File Delivery, and Dev/Build Shell Execution.

import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import CoreServices
import Darwin
import EventKit
import Speech
#endif

// MARK: - 1. macOS Native Permission & Toolchain Models

public enum PipiMacPermissionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case fullDiskMessages = "full_disk_messages"
    case automationApps = "automation_apps"
    case screenRecording = "screen_recording"
    case accessibility = "accessibility"
    case calendarReminders = "calendar_reminders"
    case microphoneSpeech = "microphone_speech"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .fullDiskMessages: return "message.fill"
        case .automationApps: return "envelope.badge.shield.half.filled"
        case .screenRecording: return "camera.viewfinder"
        case .accessibility: return "hand.raised.circle"
        case .calendarReminders: return "calendar"
        case .microphoneSpeech: return "mic.fill"
        }
    }

    public func title(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .fullDiskMessages:
            return lang == .zhHans ? "短信与信息读取（完全磁盘访问）" : "Messages / SMS Access (Full Disk)"
        case .automationApps:
            return lang == .zhHans ? "邮件与信息控制（自动化）" : "Mail & Messages Control (Automation)"
        case .screenRecording:
            return lang == .zhHans ? "屏幕截图与录屏" : "Screen Capture & Recording"
        case .accessibility:
            return lang == .zhHans ? "桌面窗口与键鼠协作（辅助功能）" : "Desktop Control (Accessibility)"
        case .calendarReminders:
            return lang == .zhHans ? "日历与提醒事项" : "Calendar & Reminders"
        case .microphoneSpeech:
            return lang == .zhHans ? "麦克风与语音识别" : "Microphone & Speech"
        }
    }

    public func capabilitySummary(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .fullDiskMessages:
            return lang == .zhHans
                ? "读取本机短信与验证码摘要，辅助回复与整理重要通知（仅本机读取，不上传第三方）。"
                : "Reads local Messages/SMS database on-device to summarize codes and notifications."
        case .automationApps:
            return lang == .zhHans
                ? "通过 Apple 邮件与信息应用代查未读邮件、起草回复或经确认后发送信息。"
                : "Inspects unread Mail, drafts replies, and sends approved messages via Apple Mail & Messages."
        case .screenRecording:
            return lang == .zhHans
                ? "执行本机截屏与屏幕录制，将画面直接回传至会话、远程 PWA 或微信。"
                : "Captures Mac screenshots and short screen videos to deliver back to chat, PWA, or WeChat."
        case .accessibility:
            return lang == .zhHans
                ? "读取桌面应用控件结构，协助执行跨应用操作，切窗时自动暂停礼让。"
                : "Inspects native macOS window trees for cross-app actions with instant human takeover."
        case .calendarReminders:
            return lang == .zhHans
                ? "读取近期日程与待办事项，自动生成会前简报与任务提醒。"
                : "Reads upcoming Calendar events and Reminders for pre-meeting briefs."
        case .microphoneSpeech:
            return lang == .zhHans
                ? "支持语音输入、实时语音通话与生成语音消息回复。"
                : "Enables voice dictation, live voice calls, and voice message workflows."
        }
    }

    public var requiresManualAddInSettings: Bool {
        self == .fullDiskMessages
    }

    public var requiresRelaunchAfterGrant: Bool {
        self == .fullDiskMessages || self == .screenRecording
    }

    public func onboardingActionHint(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .fullDiskMessages:
            return lang == .zhHans
                ? "受 macOS 安全限制，此项无法自动弹出授权框。请点击「打开系统设置」后，将访达中的 PiPiBot.app 拖入列表并勾选（若旧版本残留请先点「-」移除），随后重启应用生效。"
                : "macOS does not allow apps to auto-prompt for Full Disk Access. Open System Settings, drag PiPiBot.app into the list (remove stale copies first), then relaunch."
        case .automationApps:
            return lang == .zhHans
                ? "点击「立即授权」后，系统将向「邮件」与「信息」发起自动化授权弹窗，允许后 PiPiBot 会自动出现在系统设置列表中。"
                : "Click Authorize to trigger native macOS Automation consent dialogs for Mail and Messages."
        case .screenRecording:
            return lang == .zhHans
                ? "点击「立即授权」会向系统注册 PiPiBot 并打开录屏设置，勾选开关后重启应用即可使用截屏与录屏。"
                : "Click Authorize to register PiPiBot in Screen Recording settings, enable the switch, and relaunch."
        case .accessibility:
            return lang == .zhHans
                ? "点击「立即授权」将触发系统辅助功能提示并自动把 PiPiBot 加入辅助功能列表，勾选后即时生效。"
                : "Click Authorize to prompt macOS Accessibility and automatically add PiPiBot to the list."
        case .calendarReminders:
            return lang == .zhHans
                ? "点击「立即授权」将弹出系统原生确认框，允许后即时生效，无需重启。"
                : "Click Authorize to trigger native macOS Calendar & Reminders prompts (takes effect immediately)."
        case .microphoneSpeech:
            return lang == .zhHans
                ? "点击「立即授权」将依次弹出麦克风与语音识别系统确认框，允许后即时生效。"
                : "Click Authorize to trigger native macOS Microphone & Speech Recognition prompts."
        }
    }

    public var systemSettingsURLString: String {
        switch self {
        case .fullDiskMessages:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case .automationApps:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .calendarReminders:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .microphoneSpeech:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        }
    }
}

public enum PipiMacPermissionState: String, Codable, Sendable, Equatable {
    case granted
    case notGranted
    case manualVerify
    case unavailable

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .granted: return lang == .zhHans ? "已授权" : "Granted"
        case .notGranted: return lang == .zhHans ? "未授权" : "Not Granted"
        case .manualVerify: return lang == .zhHans ? "需按需确认" : "Prompt on Use"
        case .unavailable: return lang == .zhHans ? "不可用" : "Unavailable"
        }
    }
}

public struct PipiMacPermissionItem: Identifiable, Codable, Sendable, Equatable {
    public let kind: PipiMacPermissionKind
    public let state: PipiMacPermissionState
    public let detail: String

    public var id: String { kind.rawValue }

    public init(kind: PipiMacPermissionKind, state: PipiMacPermissionState, detail: String) {
        self.kind = kind
        self.state = state
        self.detail = detail
    }
}

public struct PipiMacPermissionSnapshot: Codable, Sendable, Equatable {
    public let items: [PipiMacPermissionItem]
    public let detectedToolchains: [String]
    public let checkedAt: Date

    public init(items: [PipiMacPermissionItem], detectedToolchains: [String], checkedAt: Date = Date()) {
        self.items = items
        self.detectedToolchains = detectedToolchains
        self.checkedAt = checkedAt
    }

    public static let empty = PipiMacPermissionSnapshot(items: [], detectedToolchains: [])

    public func state(for kind: PipiMacPermissionKind) -> PipiMacPermissionState {
        items.first(where: { $0.kind == kind })?.state ?? .unavailable
    }
}

// MARK: - 2. Rich Media Deliverable Artifact (Image / File / Voice / Video)

public enum PipiDeliverableKind: String, Codable, Sendable, Equatable {
    case image
    case file
    case audio
    case video

    public var mimeTypeFallback: String {
        switch self {
        case .image: return "image/png"
        case .file: return "application/octet-stream"
        case .audio: return "audio/mp4"
        case .video: return "video/mp4"
        }
    }

    public var iLinkMediaType: Int {
        switch self {
        case .image: return 1
        case .video: return 2
        case .file: return 3
        case .audio: return 4
        }
    }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .image: return lang == .zhHans ? "图片 / 截图" : "Image"
        case .file: return lang == .zhHans ? "文件" : "File"
        case .audio: return lang == .zhHans ? "语音" : "Voice"
        case .video: return lang == .zhHans ? "视频" : "Video"
        }
    }
}

public struct PipiDeliverableArtifact: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: PipiDeliverableKind
    public let fileName: String
    public let filePath: String
    public let mimeType: String
    public let byteSize: Int64
    public let caption: String?
    public let createdAt: Date

    public init(
        id: String = "art_\(UUID().uuidString.prefix(10).lowercased())",
        kind: PipiDeliverableKind,
        fileName: String,
        filePath: String,
        mimeType: String,
        byteSize: Int64,
        caption: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.filePath = filePath
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.caption = caption
        self.createdAt = createdAt
    }

    public static func inferKindAndMime(for path: String) -> (PipiDeliverableKind, String) {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return (.image, "image/png")
        case "jpg", "jpeg": return (.image, "image/jpeg")
        case "webp": return (.image, "image/webp")
        case "gif": return (.image, "image/gif")
        case "heic": return (.image, "image/heic")
        case "m4a": return (.audio, "audio/mp4")
        case "mp3": return (.audio, "audio/mpeg")
        case "wav": return (.audio, "audio/wav")
        case "aac": return (.audio, "audio/aac")
        case "ogg", "silk", "amr": return (.audio, "audio/ogg")
        case "mp4": return (.video, "video/mp4")
        case "mov": return (.video, "video/quicktime")
        case "webm": return (.video, "video/webm")
        case "pdf": return (.file, "application/pdf")
        case "zip": return (.file, "application/zip")
        case "txt", "log", "md": return (.file, "text/plain; charset=utf-8")
        case "json": return (.file, "application/json")
        default: return (.file, "application/octet-stream")
        }
    }
}

public struct PipiMacOmnipotentCommandResult: Sendable, Equatable {
    public let succeeded: Bool
    public let summary: String
    public let artifacts: [PipiDeliverableArtifact]
    public let missingPermission: PipiMacPermissionKind?

    public init(
        succeeded: Bool,
        summary: String,
        artifacts: [PipiDeliverableArtifact] = [],
        missingPermission: PipiMacPermissionKind? = nil
    ) {
        self.succeeded = succeeded
        self.summary = summary
        self.artifacts = artifacts
        self.missingPermission = missingPermission
    }
}

// MARK: - 3. Direct Intent Parser (Slash Commands & Natural Action Triggers)

public enum PipiOmnipotentDirectIntent: Sendable, Equatable {
    case screenshot
    case recordScreen(seconds: Int)
    case readSMS(limit: Int)
    case sendSMS(recipient: String, body: String)
    case readMail(limit: Int)
    case sendMail(recipient: String, subject: String, body: String)
    case voiceClip(text: String)
    case sendFile(path: String)
    case runCommand(command: String)
}

public enum PipiMacOmnipotentIntentParser {
    public static func parse(_ rawPrompt: String) -> PipiOmnipotentDirectIntent? {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // 1. Explicit slash commands
        if lower == "/screenshot" || lower == "/screen" || lower == "/截屏" || lower == "/截图" {
            return .screenshot
        }
        if lower.hasPrefix("/record") || lower.hasPrefix("/录屏") {
            let arg = trimmed.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? "5"
            let secs = min(max(Int(arg.trimmingCharacters(in: .whitespaces)) ?? 5, 2), 30)
            return .recordScreen(seconds: secs)
        }
        if lower == "/sms" || lower == "/messages" || lower == "/短信" {
            return .readSMS(limit: 8)
        }
        if lower.hasPrefix("/sendsms ") {
            let rest = String(trimmed.dropFirst("/sendsms ".count)).trimmingCharacters(in: .whitespaces)
            let parts = rest.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                return .sendSMS(recipient: String(parts[0]), body: String(parts[1]))
            }
        }
        if lower == "/mail" || lower == "/email" || lower == "/邮件" {
            return .readMail(limit: 8)
        }
        if lower.hasPrefix("/sendmail ") {
            let rest = String(trimmed.dropFirst("/sendmail ".count))
            let parts = rest.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3 {
                return .sendMail(recipient: parts[0], subject: parts[1], body: parts[2])
            }
        }
        if lower.hasPrefix("/voiceclip ") || lower.hasPrefix("/语音 ") {
            let prefixLen = lower.hasPrefix("/voiceclip ") ? "/voiceclip ".count : "/语音 ".count
            let text = String(trimmed.dropFirst(prefixLen)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return .voiceClip(text: text) }
        }
        if lower.hasPrefix("/sendfile ") || lower.hasPrefix("/file ") || lower.hasPrefix("/发文件 ") {
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let path = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if !path.isEmpty { return .sendFile(path: path) }
            }
        }
        if lower.hasPrefix("/build ") || lower.hasPrefix("/exec ") || lower.hasPrefix("/run ") {
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let cmd = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if !cmd.isEmpty { return .runCommand(command: cmd) }
            }
        }

        // 2. Concise direct natural-language triggers (only when user clearly asks for direct Mac action)
        if trimmed.count <= 32 {
            if (trimmed.contains("截屏") || trimmed.contains("截图") || lower.contains("take a screenshot") || lower == "screenshot")
                && !trimmed.contains("怎么") && !trimmed.contains("如何") {
                return .screenshot
            }
            if (trimmed.contains("录屏") || trimmed.contains("录制屏幕") || lower.contains("record screen"))
                && !trimmed.contains("怎么") {
                let digits = trimmed.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                let secs = min(max(Int(digits) ?? 5, 2), 30)
                return .recordScreen(seconds: secs)
            }
            if (trimmed.contains("查短信") || trimmed.contains("看短信") || trimmed.contains("最近短信") || trimmed.contains("最新短信") || trimmed.contains("查一下短信") || lower.contains("check sms") || lower.contains("recent messages")) {
                return .readSMS(limit: 8)
            }
            if (trimmed.contains("查邮件") || trimmed.contains("看邮件") || trimmed.contains("最近邮件") || trimmed.contains("最新邮件") || trimmed.contains("查一下邮件") || lower.contains("check mail") || lower.contains("recent emails")) {
                return .readMail(limit: 8)
            }
        }
        if let voicePrefix = ["发语音：", "发语音:", "发段语音：", "发段语音:", "语音回复：", "语音回复:"].first(where: { trimmed.hasPrefix($0) }) {
            let text = String(trimmed.dropFirst(voicePrefix.count)).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return .voiceClip(text: text) }
        }
        if let filePrefix = ["发文件：", "发文件:", "发送文件：", "发送文件:"].first(where: { trimmed.hasPrefix($0) }) {
            let path = String(trimmed.dropFirst(filePrefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            if !path.isEmpty { return .sendFile(path: path) }
        }

        return nil
    }
}

// MARK: - 4. Native macOS Omnipotent Execution Engine

public final class PipiMacOmnipotentEngine: @unchecked Sendable {
    public let deliverablesDir: URL
    private let registryLock = NSLock()
    private var artifactsById: [String: PipiDeliverableArtifact] = [:]

    public init(dataRootURL: URL) {
        self.deliverablesDir = dataRootURL.appendingPathComponent("deliverables", isDirectory: true)
        try? FileManager.default.createDirectory(at: deliverablesDir, withIntermediateDirectories: true)
    }

    public func registerArtifact(_ artifact: PipiDeliverableArtifact) {
        registryLock.lock()
        artifactsById[artifact.id] = artifact
        registryLock.unlock()
    }

    public func artifact(id: String) -> PipiDeliverableArtifact? {
        registryLock.lock()
        defer { registryLock.unlock() }
        return artifactsById[id]
    }

    public func allArtifacts() -> [PipiDeliverableArtifact] {
        registryLock.lock()
        defer { registryLock.unlock() }
        return artifactsById.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: System Permissions Live Probing & Guided Authorization

    public func probePermissions() -> PipiMacPermissionSnapshot {
        #if os(macOS)
        var items: [PipiMacPermissionItem] = []

        // 1. Full Disk Access — MUST verify via actual `open()` + `read()` rather than `isReadableFile`
        // (`isReadableFile` only checks POSIX mode bits and falsely returns true even when TCC blocks access!)
        let canOpenMessages = Self.probeRealFullDiskAccess()
        items.append(PipiMacPermissionItem(
            kind: .fullDiskMessages,
            state: canOpenMessages ? .granted : .notGranted,
            detail: canOpenMessages
                ? "已通过真实文件读取验证（chat.db 可访问）"
                : "未获取完全磁盘访问权限；需在系统设置中手动添加并勾选 PiPiBot.app 后重启"
        ))

        // 2. Automation (Mail.app & Messages.app) — real TCC check via AEDeterminePermissionToAutomateTarget
        let mailStatus = Self.probeAutomationTarget(bundleId: "com.apple.mail")
        let msgStatus = Self.probeAutomationTarget(bundleId: "com.apple.MobileSMS")
        let autoState: PipiMacPermissionState
        let autoDetail: String
        if mailStatus == .granted && msgStatus == .granted {
            autoState = .granted
            autoDetail = "邮件与信息自动化控制均已授权"
        } else if mailStatus == .granted || msgStatus == .granted {
            autoState = .granted
            autoDetail = mailStatus == .granted ? "已授权「邮件」（「信息」待触发）" : "已授权「信息」（「邮件」待触发）"
        } else if mailStatus == .notGranted || msgStatus == .notGranted {
            autoState = .notGranted
            autoDetail = "尚未授权控制「邮件」与「信息」，点击请求触发系统弹窗"
        } else {
            autoState = .manualVerify
            autoDetail = "点击「立即授权」触发「邮件」与「信息」系统确认框"
        }
        items.append(PipiMacPermissionItem(
            kind: .automationApps,
            state: autoState,
            detail: autoDetail
        ))

        // 3. Screen Recording
        let screenOK = CGPreflightScreenCaptureAccess()
        items.append(PipiMacPermissionItem(
            kind: .screenRecording,
            state: screenOK ? .granted : .notGranted,
            detail: screenOK ? "已授权截屏与录屏" : "未授权；点击请求注册至「录屏与系统录音」后勾选并重启"
        ))

        // 4. Accessibility
        let axOK = AXIsProcessTrusted()
        items.append(PipiMacPermissionItem(
            kind: .accessibility,
            state: axOK ? .granted : .notGranted,
            detail: axOK ? "已授权桌面辅助功能" : "未授权；点击触发系统提示并自动加入「辅助功能」列表"
        ))

        // 5. Calendar & Reminders
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        let calGranted = (calStatus == .fullAccess)
        let remGranted = (remStatus == .fullAccess)
        let calState: PipiMacPermissionState = (calGranted && remGranted) ? .granted : ((calGranted || remGranted) ? .manualVerify : .notGranted)
        items.append(PipiMacPermissionItem(
            kind: .calendarReminders,
            state: calState,
            detail: calGranted && remGranted
                ? "日历与提醒事项均已授权"
                : (calGranted ? "日历已授权，提醒事项未授权" : (remGranted ? "提醒事项已授权，日历未授权" : "点击授权读取本机日程与待办"))
        ))

        // 6. Microphone & Speech
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        items.append(PipiMacPermissionItem(
            kind: .microphoneSpeech,
            state: (micGranted && speechGranted) ? .granted : .notGranted,
            detail: (micGranted && speechGranted) ? "麦克风与语音识别均已就绪" : "语音通话与听写需要麦克风及语音识别权限"
        ))

        // 7. Developer / Media Toolchains
        let toolNames = ["swift", "xcodebuild", "node", "npm", "python3", "git", "ffmpeg", "docker", "cloudflared"]
        let detected = toolNames.filter { PipiNativeMacRuntime.findExecutable($0) != nil }

        return PipiMacPermissionSnapshot(items: items, detectedToolchains: detected, checkedAt: Date())
        #else
        return .empty
        #endif
    }

    /// Real TCC verification for Full Disk Access by calling POSIX `open()` + `read()` on TCC-protected paths.
    public static func probeRealFullDiskAccess() -> Bool {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protectedFiles = [
            home.appendingPathComponent("Library/Messages/chat.db").path,
            home.appendingPathComponent("Library/Safari/Bookmarks.plist").path,
            home.appendingPathComponent("Library/Safari/CloudTabs.db").path
        ]
        for path in protectedFiles {
            if canActuallyOpenProtectedFile(atPath: path) {
                return true
            }
        }
        // Also try listing TCC-protected Mail directory if files above don't exist
        let mailDir = home.appendingPathComponent("Library/Mail").path
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: mailDir), !entries.isEmpty {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    public static func canActuallyOpenProtectedFile(atPath path: String) -> Bool {
        #if os(macOS)
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var byte: UInt8 = 0
        let n = Darwin.read(fd, &byte, 1)
        return n >= 0
        #else
        _ = path
        return false
        #endif
    }

    #if os(macOS)
    private static func probeAutomationTarget(bundleId: String) -> PipiMacPermissionState {
        guard let targetDesc = NSAppleEventDescriptor(bundleIdentifier: bundleId).aeDesc else {
            return .manualVerify
        }
        let status = AEDeterminePermissionToAutomateTarget(
            targetDesc,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            false
        )
        switch status {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent), OSStatus(errAEEventNotPermitted):
            return .notGranted
        default:
            // procNotFound (-600) when Mail/Messages isn't currently running
            return .manualVerify
        }
    }

    private static func requestAutomationConsentInProcess(bundleId: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                if let targetDesc = NSAppleEventDescriptor(bundleIdentifier: bundleId).aeDesc {
                    _ = AEDeterminePermissionToAutomateTarget(
                        targetDesc,
                        AEEventClass(typeWildCard),
                        AEEventID(typeWildCard),
                        true
                    )
                }
                cont.resume()
            }
        }
    }

    private static func runAppleScriptInProcess(_ source: String) async -> (ok: Bool, output: String, error: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(returning: (false, "", "无法初始化 AppleScript"))
                    return
                }
                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String)
                        ?? (errorInfo[NSAppleScript.errorBriefMessage] as? String)
                        ?? errorInfo.description
                    cont.resume(returning: (false, "", message))
                } else {
                    cont.resume(returning: (true, result.stringValue ?? "", ""))
                }
            }
        }
    }
    #endif

    public static func openSystemSettings(for kind: PipiMacPermissionKind) {
        #if os(macOS)
        if let url = URL(string: kind.systemSettingsURLString) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    public static func revealCurrentAppInFinder() {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        #endif
    }

    public static func currentBundleLocationPath() -> String {
        Bundle.main.bundleURL.path
    }

    public static func relaunchCurrentApp() {
        #if os(macOS)
        let bundleURL = Bundle.main.bundleURL
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 0.6; open -n \"\(bundleURL.path)\""]
        try? proc.run()
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
        #endif
    }

    public static func requestInteractivePermission(for kind: PipiMacPermissionKind) async {
        #if os(macOS)
        switch kind {
        case .screenRecording:
            // CGRequestScreenCaptureAccess registers PiPiBot into System Settings -> Screen Recording
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                openSystemSettings(for: kind)
            }
        case .accessibility:
            // Passing kAXTrustedCheckOptionPrompt = true triggers the native macOS prompt
            // AND automatically registers PiPiBot inside System Settings -> Accessibility!
            let key = "AXTrustedCheckOptionPrompt" as CFString
            let options = [key: kCFBooleanTrue!] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if !trusted {
                openSystemSettings(for: kind)
            }
        case .calendarReminders:
            let store = EKEventStore()
            _ = try? await store.requestFullAccessToEvents()
            _ = try? await store.requestFullAccessToReminders()
        case .microphoneSpeech:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { _ in
                    cont.resume()
                }
            }
        case .automationApps:
            // Request native in-process Automation consent for Mail & Messages so macOS adds PiPiBot automatically
            await requestAutomationConsentInProcess(bundleId: "com.apple.mail")
            await requestAutomationConsentInProcess(bundleId: "com.apple.MobileSMS")
            openSystemSettings(for: kind)
        case .fullDiskMessages:
            // Apple strictly prohibits apps from self-registering into Full Disk Access;
            // open System Settings AND reveal the exact running PiPiBot.app in Finder for 1-drag addition.
            openSystemSettings(for: kind)
            revealCurrentAppInFinder()
        }
        #endif
    }

    // MARK: Native Capabilities Execution

    public func readRecentSMS(limit: Int = 8) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db").path
        guard Self.canActuallyOpenProtectedFile(atPath: dbPath) else {
            return PipiMacOmnipotentCommandResult(
                succeeded: false,
                summary: "尚未获取「完全磁盘访问权限」，无法读取本机短信数据库（~/Library/Messages/chat.db）。请在「引导式配置 → 系统权限」或「设置 → 运行与远程操控」打开系统设置并拖入当前 PiPiBot.app，勾选后重启应用。",
                missingPermission: .fullDiskMessages
            )
        }

        let safeLimit = min(max(limit, 1), 20)
        let sql = """
        SELECT
          datetime(m.date / 1000000000 + strftime('%s', '2001-01-01'), 'unixepoch', 'localtime') AS ts,
          COALESCE(h.id, '本机') AS sender,
          CASE m.is_from_me WHEN 1 THEN '我' ELSE '对方' END AS dir,
          REPLACE(REPLACE(COALESCE(m.text, '[媒体/富文本消息]'), char(10), ' '), char(13), ' ') AS body
        FROM message m
        LEFT JOIN handle h ON m.handle_id = h.ROWID
        WHERE m.text IS NOT NULL AND LENGTH(TRIM(m.text)) > 0
        ORDER BY m.date DESC
        LIMIT \(safeLimit);
        """
        let res = Self.runProcess(
            executable: "/usr/bin/sqlite3",
            arguments: ["-readonly", "-separator", " | ", dbPath, sql],
            timeout: 8
        )
        guard res.exitCode == 0 else {
            return PipiMacOmnipotentCommandResult(
                succeeded: false,
                summary: "读取短信失败：\(res.stderr.isEmpty ? res.stdout : res.stderr)",
                missingPermission: .fullDiskMessages
            )
        }
        let lines = res.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.isEmpty {
            return PipiMacOmnipotentCommandResult(succeeded: true, summary: "最近未查询到文本短信记录。")
        }
        let formatted = lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return PipiMacOmnipotentCommandResult(
            succeeded: true,
            summary: "最近 \(lines.count) 条本机短信 / iMessage：\n\(formatted)"
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持读取本机短信。")
        #endif
    }

    public func sendSMS(recipient: String, body: String) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let escRecipient = Self.escapeAppleScript(recipient)
        let escBody = Self.escapeAppleScript(body)
        let script = """
        tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant "\(escRecipient)" of targetService
            send "\(escBody)" to targetBuddy
        end tell
        """
        let res = await Self.runAppleScriptInProcess(script)
        if res.ok {
            return PipiMacOmnipotentCommandResult(succeeded: true, summary: "已通过本机「信息」发送至 \(recipient)。")
        }
        return PipiMacOmnipotentCommandResult(
            succeeded: false,
            summary: "发送信息失败（请确认已授予「自动化 → 信息」权限，且联系人已开启 iMessage/短信转发）：\(res.error)",
            missingPermission: .automationApps
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持发送信息。")
        #endif
    }

    public func readRecentMail(limit: Int = 8) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let safeLimit = min(max(limit, 1), 15)
        let script = """
        tell application "Mail"
            if not running then launch
            set msgList to messages 1 thru \(safeLimit) of inbox
            set outLines to {}
            repeat with m in msgList
                set s to subject of m
                set f to sender of m
                set d to date received of m as string
                set r to read status of m
                set flagTxt to "[未读]"
                if r is true then set flagTxt to "[已读]"
                set end of outLines to flagTxt & " " & f & " | " & s & " (" & d & ")"
            end repeat
            set AppleScript's text item delimiters to linefeed
            return outLines as text
        end tell
        """
        let res = await Self.runAppleScriptInProcess(script)
        if res.ok {
            let output = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if output.isEmpty {
                return PipiMacOmnipotentCommandResult(succeeded: true, summary: "Apple 邮件收件箱暂无邮件。")
            }
            return PipiMacOmnipotentCommandResult(
                succeeded: true,
                summary: "Apple 邮件最近收件箱摘要：\n\(output)"
            )
        }
        return PipiMacOmnipotentCommandResult(
            succeeded: false,
            summary: "读取 Apple 邮件失败（请确认已登录 Apple Mail 并授予「自动化 → 邮件」权限）：\(res.error)",
            missingPermission: .automationApps
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持读取本机邮件。")
        #endif
    }

    public func sendOrDraftMail(
        to recipient: String,
        subject: String,
        body: String,
        sendImmediately: Bool = false
    ) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let escTo = Self.escapeAppleScript(recipient)
        let escSub = Self.escapeAppleScript(subject)
        let escBody = Self.escapeAppleScript(body)
        let sendLine = sendImmediately ? "send newMessage" : "activate"
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(escSub)", content:"\(escBody)", visible:true}
            tell newMessage
                make new to recipient at end of to recipients with properties {address:"\(escTo)"}
            end tell
            \(sendLine)
        end tell
        """
        let res = await Self.runAppleScriptInProcess(script)
        if res.ok {
            return PipiMacOmnipotentCommandResult(
                succeeded: true,
                summary: sendImmediately
                    ? "已通过 Apple 邮件发送至 \(recipient)（主题：\(subject)）。"
                    : "已在 Apple 邮件创建草稿（收件人：\(recipient)，主题：\(subject)）。"
            )
        }
        return PipiMacOmnipotentCommandResult(
            succeeded: false,
            summary: "操作 Apple 邮件失败：\(res.error)",
            missingPermission: .automationApps
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持操作本机邮件。")
        #endif
    }

    public func captureScreenshot() async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let fileName = "screenshot-\(Self.timestampTag()).png"
        let dest = deliverablesDir.appendingPathComponent(fileName)
        let res = Self.runProcess(executable: "/usr/sbin/screencapture", arguments: ["-x", "-t", "png", dest.path], timeout: 10)
        guard res.exitCode == 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath: dest.path),
              let size = attrs[.size] as? Int64,
              size > 0 else {
            return PipiMacOmnipotentCommandResult(
                succeeded: false,
                summary: "截屏失败，请先在「设置 → 运行与远程操控」授权「屏幕截图与录屏」权限。\(res.stderr)",
                missingPermission: .screenRecording
            )
        }
        let artifact = PipiDeliverableArtifact(
            kind: .image,
            fileName: fileName,
            filePath: dest.path,
            mimeType: "image/png",
            byteSize: size,
            caption: "Mac 屏幕截图"
        )
        registerArtifact(artifact)
        return PipiMacOmnipotentCommandResult(
            succeeded: true,
            summary: "已完成 Mac 截屏（\(Self.formatBytes(size))）：\(dest.path)",
            artifacts: [artifact]
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持屏幕截图。")
        #endif
    }

    public func recordScreenVideo(durationSeconds: Int = 5) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let clamped = min(max(durationSeconds, 2), 30)
        let rawMov = deliverablesDir.appendingPathComponent("screen-\(Self.timestampTag()).mov")
        let res = Self.runProcess(
            executable: "/usr/sbin/screencapture",
            arguments: ["-v", "-V", String(clamped), "-x", rawMov.path],
            timeout: Double(clamped + 12)
        )
        guard res.exitCode == 0, FileManager.default.fileExists(atPath: rawMov.path) else {
            return PipiMacOmnipotentCommandResult(
                succeeded: false,
                summary: "录屏失败，请确认已授权「屏幕截图与录屏」权限。\(res.stderr)",
                missingPermission: .screenRecording
            )
        }

        // Convert to broadly compatible H.264 MP4 when ffmpeg is available
        var finalURL = rawMov
        var finalMime = "video/quicktime"
        if let ffmpeg = PipiNativeMacRuntime.findExecutable("ffmpeg") {
            let mp4URL = rawMov.deletingPathExtension().appendingPathExtension("mp4")
            let conv = Self.runProcess(
                executable: ffmpeg,
                arguments: ["-y", "-i", rawMov.path, "-vcodec", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4URL.path],
                timeout: 45
            )
            if conv.exitCode == 0, FileManager.default.fileExists(atPath: mp4URL.path) {
                try? FileManager.default.removeItem(at: rawMov)
                finalURL = mp4URL
                finalMime = "video/mp4"
            }
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
        let artifact = PipiDeliverableArtifact(
            kind: .video,
            fileName: finalURL.lastPathComponent,
            filePath: finalURL.path,
            mimeType: finalMime,
            byteSize: size,
            caption: "Mac 录屏（\(clamped) 秒）"
        )
        registerArtifact(artifact)
        return PipiMacOmnipotentCommandResult(
            succeeded: true,
            summary: "已完成 \(clamped) 秒 Mac 屏幕录制（\(Self.formatBytes(size))）：\(finalURL.path)",
            artifacts: [artifact]
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持屏幕录制。")
        #endif
    }

    public func synthesizeVoiceClip(text: String, voiceName: String? = nil) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return PipiMacOmnipotentCommandResult(succeeded: false, summary: "语音合成内容为空。")
        }
        let tag = Self.timestampTag()
        let aiffURL = deliverablesDir.appendingPathComponent("voice-\(tag).aiff")
        let m4aURL = deliverablesDir.appendingPathComponent("voice-\(tag).m4a")

        var sayArgs: [String] = []
        if let voiceName, !voiceName.isEmpty {
            sayArgs += ["-v", voiceName]
        }
        sayArgs += ["-o", aiffURL.path, cleaned]
        let sayRes = Self.runProcess(executable: "/usr/bin/say", arguments: sayArgs, timeout: 25)
        guard sayRes.exitCode == 0, FileManager.default.fileExists(atPath: aiffURL.path) else {
            return PipiMacOmnipotentCommandResult(succeeded: false, summary: "语音文件生成失败：\(sayRes.stderr)")
        }

        let conv = Self.runProcess(
            executable: "/usr/bin/afconvert",
            arguments: ["-f", "m4af", "-d", "aac", aiffURL.path, m4aURL.path],
            timeout: 15
        )
        let finalURL: URL
        let finalMime: String
        if conv.exitCode == 0, FileManager.default.fileExists(atPath: m4aURL.path) {
            try? FileManager.default.removeItem(at: aiffURL)
            finalURL = m4aURL
            finalMime = "audio/mp4"
        } else {
            finalURL = aiffURL
            finalMime = "audio/aiff"
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int64) ?? 0
        let artifact = PipiDeliverableArtifact(
            kind: .audio,
            fileName: finalURL.lastPathComponent,
            filePath: finalURL.path,
            mimeType: finalMime,
            byteSize: size,
            caption: String(cleaned.prefix(60))
        )
        registerArtifact(artifact)
        return PipiMacOmnipotentCommandResult(
            succeeded: true,
            summary: "已生成语音消息（\(Self.formatBytes(size))）：\(finalURL.lastPathComponent)",
            artifacts: [artifact]
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持本地语音合成导出。")
        #endif
    }

    public func prepareFileDeliverable(path rawPath: String) async -> PipiMacOmnipotentCommandResult {
        let expanded = (rawPath as NSString).expandingTildeInPath
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else {
            return PipiMacOmnipotentCommandResult(succeeded: false, summary: "未找到目标文件：\(expanded)")
        }

        var targetPath = expanded
        #if os(macOS)
        if isDir.boolValue {
            // Zip directory so user can cleanly download or receive via WeChat/PWA
            let base = (expanded as NSString).lastPathComponent
            let zipURL = deliverablesDir.appendingPathComponent("\(base)-\(Self.timestampTag()).zip")
            let zipRes = Self.runProcess(
                executable: "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", expanded, zipURL.path],
                timeout: 45
            )
            guard zipRes.exitCode == 0, fm.fileExists(atPath: zipURL.path) else {
                return PipiMacOmnipotentCommandResult(succeeded: false, summary: "打包目录失败：\(zipRes.stderr)")
            }
            targetPath = zipURL.path
        }
        #endif

        let (kind, mime) = PipiDeliverableArtifact.inferKindAndMime(for: targetPath)
        let size = (try? fm.attributesOfItem(atPath: targetPath)[.size] as? Int64) ?? 0
        let fileName = (targetPath as NSString).lastPathComponent
        let artifact = PipiDeliverableArtifact(
            kind: kind,
            fileName: fileName,
            filePath: targetPath,
            mimeType: mime,
            byteSize: size,
            caption: fileName
        )
        registerArtifact(artifact)
        return PipiMacOmnipotentCommandResult(
            succeeded: true,
            summary: "已准备好文件投递：\(fileName)（\(Self.formatBytes(size))）",
            artifacts: [artifact]
        )
    }

    public func runShellBuildOrTask(
        command: String,
        workingDirectory: String?,
        timeoutSeconds: Double = 90
    ) async -> PipiMacOmnipotentCommandResult {
        #if os(macOS)
        let cleaned = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return PipiMacOmnipotentCommandResult(succeeded: false, summary: "命令为空。")
        }
        let cwd = workingDirectory.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let res = Self.runProcess(
            executable: "/bin/zsh",
            arguments: ["-lc", cleaned],
            workingDirectory: cwd,
            timeout: timeoutSeconds
        )
        let combined = [res.stdout, res.stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let truncated = combined.count > 2600 ? String(combined.suffix(2600)) : combined
        let statusTag = res.exitCode == 0 ? "执行成功 (Exit 0)" : "执行结束 (Exit \(res.exitCode))"
        let body = truncated.isEmpty ? "(无标准输出)" : truncated
        return PipiMacOmnipotentCommandResult(
            succeeded: res.exitCode == 0,
            summary: "[\(statusTag)] `$ \(cleaned)`\n工作目录：\(cwd)\n```\n\(body)\n```"
        )
        #else
        return PipiMacOmnipotentCommandResult(succeeded: false, summary: "仅 macOS 端支持本地终端编译与打包命令。")
        #endif
    }

    // MARK: Process & Formatting Helpers

    private struct ProcessOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    #if os(macOS)
    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: String? = nil,
        timeout: Double = 30
    ) -> ProcessOutput {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        if let workingDirectory {
            proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "")
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let semaphore = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in semaphore.signal() }

        do {
            try proc.run()
        } catch {
            return ProcessOutput(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            return ProcessOutput(exitCode: 124, stdout: "", stderr: "命令执行超过 \(Int(timeout)) 秒已超时中止。")
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessOutput(
            exitCode: proc.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
    #endif

    private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func timestampTag() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.2f MB", kb / 1024.0)
    }
}
