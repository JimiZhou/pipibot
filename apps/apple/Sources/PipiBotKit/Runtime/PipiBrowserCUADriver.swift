// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Antigravity-grade Native Web CUA (Computer Use Agent) Driver & Isolated Browser Subagent:
// - Drives local Chrome/Chromium over Chrome DevTools Protocol (CDP) via Foundation WebSockets (zero external deps)
// - Supports both isolated headless sessions (default, silent) and signed-in Chrome CDP attachment (port 9222)
// - Captures structured DOM text + numbered interactive element refs ([e1]..[eN]) + compressed JPEG viewport screenshots
// - Enforces rolling vision-frame compaction and safety guardrails for payment/destructive/password actions

import Foundation
#if os(iOS) && canImport(WebKit)
import WebKit
import UIKit
#endif

// MARK: - 1. Structured Browser CUA Models

public struct PipiBrowserCUAElement: Codable, Sendable, Equatable {
    public let ref: String
    public let tag: String
    public let role: String
    public let label: String
    public let href: String?
    public let inputType: String?
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(
        ref: String,
        tag: String,
        role: String,
        label: String,
        href: String? = nil,
        inputType: String? = nil,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.ref = ref
        self.tag = tag
        self.role = role
        self.label = label
        self.href = href
        self.inputType = inputType
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PipiBrowserCUASnapshot: Sendable, Equatable {
    public let url: String
    public let title: String
    public let scrollY: Int
    public let scrollHeight: Int
    public let viewportHeight: Int
    public let visibleText: String
    public let elements: [PipiBrowserCUAElement]
    public let screenshotBase64: String?
    public let screenshotPath: String?

    public init(
        url: String,
        title: String,
        scrollY: Int = 0,
        scrollHeight: Int = 0,
        viewportHeight: Int = 800,
        visibleText: String,
        elements: [PipiBrowserCUAElement] = [],
        screenshotBase64: String? = nil,
        screenshotPath: String? = nil
    ) {
        self.url = url
        self.title = title
        self.scrollY = scrollY
        self.scrollHeight = scrollHeight
        self.viewportHeight = viewportHeight
        self.visibleText = visibleText
        self.elements = elements
        self.screenshotBase64 = screenshotBase64
        self.screenshotPath = screenshotPath
    }

    /// Formats the snapshot into a compact, high-signal text observation for LLM reasoning.
    public func formattedForModel(maxTextChars: Int = 5200, maxElements: Int = 36) -> String {
        var lines: [String] = []
        lines.append("[Browser Page Snapshot]")
        lines.append("Title: \(title.isEmpty ? "(untitled)" : title)")
        lines.append("URL: \(url)")
        let maxScroll = max(0, scrollHeight - viewportHeight)
        let scrollPct = maxScroll > 0 ? min(100, Int((Double(scrollY) / Double(maxScroll)) * 100.0)) : 100
        lines.append("Viewport scroll: y=\(scrollY)/\(scrollHeight)px (\(scrollPct)%)")

        if !elements.isEmpty {
            lines.append("")
            lines.append("Interactive Elements (use ref with browser_act):")
            for el in elements.prefix(maxElements) {
                var desc = "[\(el.ref)] \(el.role)"
                if let inputType = el.inputType, !inputType.isEmpty {
                    desc += "(\(inputType))"
                }
                if !el.label.isEmpty {
                    desc += " \"\(el.label)\""
                }
                if let href = el.href, !href.isEmpty {
                    let shortHref = href.count > 72 ? String(href.prefix(72)) + "…" : href
                    desc += " -> \(shortHref)"
                }
                lines.append(desc)
            }
        }

        let cleanText = visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanText.isEmpty {
            lines.append("")
            lines.append("Visible Page Content:")
            if cleanText.count > maxTextChars {
                lines.append(String(cleanText.prefix(maxTextChars)) + "\n… [truncated, scroll down to read more]")
            } else {
                lines.append(cleanText)
            }
        } else {
            lines.append("")
            lines.append("Visible Page Content: (empty or still loading)")
        }

        return lines.joined(separator: "\n")
    }

    public var encodedImagePart: PipiEncodedImagePart? {
        guard let b64 = screenshotBase64, !b64.isEmpty else { return nil }
        return PipiEncodedImagePart(mimeType: "image/jpeg", base64: b64)
    }
}

public enum PipiBrowserCUAActionKind: String, Codable, Sendable {
    case click
    case type
    case scroll
    case pressKey = "press_key"
    case wait
    case back
    case reload
}

public struct PipiBrowserCUAActionRequest: Sendable, Equatable {
    public let action: PipiBrowserCUAActionKind
    public let ref: String?
    public let x: Double?
    public let y: Double?
    public let text: String?
    public let key: String?
    public let direction: String?
    public let deltaY: Double?
    public let seconds: Double?
    public let submit: Bool

    public init(
        action: PipiBrowserCUAActionKind,
        ref: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        text: String? = nil,
        key: String? = nil,
        direction: String? = nil,
        deltaY: Double? = nil,
        seconds: Double? = nil,
        submit: Bool = false
    ) {
        self.action = action
        self.ref = ref
        self.x = x
        self.y = y
        self.text = text
        self.key = key
        self.direction = direction
        self.deltaY = deltaY
        self.seconds = seconds
        self.submit = submit
    }
}

public enum PipiBrowserCUAError: LocalizedError, Sendable {
    case chromeNotInstalled
    case invalidURL(String)
    case cdpUnavailable(String)
    case cdpTimeout(String)
    case cdpError(String)
    case elementNotFound(String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .chromeNotInstalled:
            return "未在本机检测到 Chrome / Chromium 浏览器，请先安装 Google Chrome 或 Chromium。"
        case .invalidURL(let raw):
            return "无效或受限的网页地址：\(raw)"
        case .cdpUnavailable(let detail):
            return "无法连接到浏览器调试通道 (CDP)：\(detail)"
        case .cdpTimeout(let method):
            return "浏览器操作超时：\(method)"
        case .cdpError(let msg):
            return "浏览器执行出错：\(msg)"
        case .elementNotFound(let ref):
            return "未在当前视口找到元素引用 \(ref)，请先刷新快照或滚动页面。"
        case .unsupportedPlatform:
            return "当前平台不支持本地桌面 Chrome CUA 驱动。"
        }
    }
}

// MARK: - 2. Safety Policy & Rolling Vision Compactor (Pure, Unit-Testable)

public enum PipiBrowserCUASafetyPolicy {
    private static let paymentHostPatterns = [
        "checkout.stripe.com",
        "paypal.com/checkout",
        "pay.google.com",
        "alipay.com",
        "wx.tenpay.com",
        "checkout.shopify.com"
    ]

    private static let highRiskButtonLabels = [
        "pay now", "place order", "confirm payment", "purchase", "buy now",
        "delete account", "permanently delete", "transfer funds", "wire transfer",
        "立即支付", "确认付款", "提交订单", "付款", "转账", "永久删除", "注销账号", "确认转账", "立即下单"
    ]

    private static let socialExternalPublishHosts = [
        "xiaohongshu.com", "xhslink.com", "mp.weixin.qq.com", "weixin.qq.com",
        "douyin.com", "weibo.com", "weibo.cn", "zhihu.com", "bilibili.com", "okjike.com",
        "linkedin.com", "x.com", "twitter.com", "reddit.com"
    ]

    private static let socialPublishButtonLabels = [
        "post", "publish", "reply", "repost", "retweet", "send message", "send dm",
        "connect", "follow", "comment", "submit",
        "发布", "发布笔记", "发布视频", "发布动态", "发表", "发表评论", "群发", "投稿",
        "写回答", "立即发布", "确认发布", "发帖", "回复", "转发", "私信", "发送私信", "发送消息", "关注", "评论"
    ]

    private static let sensitiveInputPatterns = [
        "password", "passwd", "passcode", "cvv", "cvc", "card number", "credit card",
        "密码", "银行卡", "安全码", "验证码"
    ]

    /// Validates that a URL is safe to navigate to (http/https, plus optional data:text/html for tests).
    public static func validateNavigationURL(_ raw: String, allowDataHTML: Bool = false) -> (allowed: Bool, normalizedURL: String, assessment: PipiToolRiskAssessment?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (false, "", PipiToolRiskAssessment(requiresApproval: true, isHardDenied: true, actionKind: .destructive, target: raw, summary: "空链接", reason: "URL 不能为空。"))
        }

        let lower = trimmed.lowercased()
        if allowDataHTML && lower.hasPrefix("data:text/html") {
            return (true, trimmed, nil)
        }
        if lower.hasPrefix("file://") || lower.hasPrefix("javascript:") || lower.hasPrefix("chrome://") || lower.hasPrefix("chrome-extension://") {
            return (false, trimmed, PipiToolRiskAssessment(
                requiresApproval: true,
                isHardDenied: true,
                actionKind: .destructive,
                target: trimmed,
                summary: "受限协议访问: \(trimmed.prefix(80))",
                reason: "浏览器 CUA 禁止访问本地 file://、chrome:// 或 javascript: 协议。"
            ))
        }

        let normalized: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            normalized = trimmed
        } else {
            normalized = "https://\(trimmed)"
        }

        guard let parsed = URL(string: normalized), let host = parsed.host?.lowercased(), !host.isEmpty else {
            return (false, normalized, PipiToolRiskAssessment(requiresApproval: true, isHardDenied: true, actionKind: .destructive, target: raw, summary: "无效 URL", reason: "无法解析目标域名。"))
        }

        let fullCheck = "\(host)\(parsed.path.lowercased())"
        if paymentHostPatterns.contains(where: { fullCheck.contains($0) }) {
            return (false, normalized, PipiToolRiskAssessment(
                requiresApproval: true,
                isHardDenied: false,
                actionKind: .externalEffect,
                target: normalized,
                summary: "支付结算页面: \(host)",
                reason: "检测到支付或结账域名，需要由你本人确认后再操作。"
            ))
        }

        return (true, normalized, nil)
    }

    /// Evaluates whether an interactive browser action (click/type) is safe to execute silently or needs human confirmation.
    public static func evaluateAction(
        request: PipiBrowserCUAActionRequest,
        targetElement: PipiBrowserCUAElement?,
        currentURL: String
    ) -> PipiToolRiskAssessment? {
        switch request.action {
        case .scroll, .wait, .back, .reload, .pressKey:
            return nil

        case .click:
            let label = (targetElement?.label ?? "").lowercased()
            let href = (targetElement?.href ?? "").lowercased()
            let combined = "\(label) \(href)"
            if highRiskButtonLabels.contains(where: { combined.contains($0) }) {
                return PipiToolRiskAssessment(
                    requiresApproval: true,
                    isHardDenied: false,
                    actionKind: .externalEffect,
                    target: currentURL,
                    summary: "点击高敏按钮「\(targetElement?.label ?? request.ref ?? "button")」",
                    reason: "该按钮涉及支付、下单、转账或不可逆删除操作，需先经你确认。"
                )
            }
            let lowerURL = currentURL.lowercased()
            if socialExternalPublishHosts.contains(where: { lowerURL.contains($0) }),
               socialPublishButtonLabels.contains(where: { label.contains($0) }) {
                return PipiToolRiskAssessment(
                    requiresApproval: true,
                    isHardDenied: false,
                    actionKind: .externalEffect,
                    target: currentURL,
                    summary: "社交平台外发操作「\(targetElement?.label ?? request.ref ?? "post")」",
                    reason: "检测到在小红书 / 公众号 / 抖音 / 微博 / 知乎 / B站 / 即刻 / LinkedIn / X / Reddit 执行发帖、评论、私信或关注等对外操作，已拦截至待确认队列。"
                )
            }
            return nil

        case .type:
            let inputType = (targetElement?.inputType ?? "").lowercased()
            let label = (targetElement?.label ?? "").lowercased()
            if inputType == "password" || sensitiveInputPatterns.contains(where: { label.contains($0) }) {
                return PipiToolRiskAssessment(
                    requiresApproval: true,
                    isHardDenied: false,
                    actionKind: .externalEffect,
                    target: currentURL,
                    summary: "向敏感输入框填写内容（\(targetElement?.label ?? inputType)）",
                    reason: "涉及密码、银行卡或验证码输入，请由你亲自确认或手动输入。"
                )
            }
            return nil
        }
    }
}

public enum PipiVisionContextCompactor {
    /// Keeps at most `maxRetainedImages` most recent `.user` messages with attached images,
    /// replacing older screenshot payloads with a short placeholder so multi-step visual CUA
    /// loops stay fast and never overflow the context window.
    public static func compact(
        messages: [PipiAgentWireMessage],
        maxRetainedImages: Int = 2
    ) -> [PipiAgentWireMessage] {
        let cap = max(0, maxRetainedImages)
        var imageUserIndices: [Int] = []
        for (idx, msg) in messages.enumerated() {
            if case .user(_, let imgs) = msg, !imgs.isEmpty {
                imageUserIndices.append(idx)
            }
        }
        guard imageUserIndices.count > cap else { return messages }
        let indicesToStrip = Set(imageUserIndices.dropLast(cap))
        return messages.enumerated().map { idx, msg in
            guard indicesToStrip.contains(idx), case .user(let text, _) = msg else {
                return msg
            }
            let strippedNote = text.isEmpty
                ? "[Earlier viewport screenshot omitted to conserve context]"
                : "\(text)\n[Earlier viewport screenshot omitted to conserve context]"
            return .user(text: strippedNote, images: [])
        }
    }
}

// MARK: - 3. Native macOS Chrome DevTools Protocol (CDP) CUA Driver

public actor PipiBrowserCUADriver {
    public static let shared = PipiBrowserCUADriver()

    public let botId: String?
    public let persistentProfileDirectory: URL?
    public let remoteCDPEndpoint: String?

    private var managedProcess: Process?
    private var managedProfileDir: URL?
    private var debugPort: Int = 0
    private var attachedExternal: Bool = false
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var nextMessageId: Int = 1
    private var pendingCallbacks: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var lastSnapshot: PipiBrowserCUASnapshot?
    private var lastActivityAt: Date = Date()

    public init(
        botId: String? = nil,
        persistentProfileDirectory: URL? = nil,
        remoteCDPEndpoint: String? = nil
    ) {
        self.botId = botId
        self.persistentProfileDirectory = persistentProfileDirectory
        self.remoteCDPEndpoint = remoteCDPEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func detectChromeBinary() -> String? {
        #if os(macOS)
        let envPath = ProcessInfo.processInfo.environment["PIPIBOT_CHROME_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let envPath, !envPath.isEmpty, FileManager.default.isExecutableFile(atPath: envPath) {
            return envPath
        }
        let candidates = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
            "/Applications/Arc.app/Contents/MacOS/Arc",
            "/opt/homebrew/bin/chromium",
            "/usr/local/bin/chromium"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        #endif
        return nil
    }

    public func currentSnapshot() -> PipiBrowserCUASnapshot? {
        lastSnapshot
    }

    /// Ensures a live CDP WebSocket connection to either an existing signed-in Chrome
    /// or a dedicated isolated headless Chromium instance.
    public func ensureConnected(
        useSignedInSession: Bool = false,
        preferredPort: Int? = nil,
        viewportWidth: Int = 1280,
        viewportHeight: Int = 800
    ) async throws {
        #if os(iOS) && canImport(WebKit)
        await PipiIOSWebKitCUASession.shared.ensureReady(width: viewportWidth, height: viewportHeight)
        self.lastActivityAt = Date()
        return
        #elseif !os(macOS)
        throw PipiBrowserCUAError.unsupportedPlatform
        #else
        if let ws = webSocketTask, ws.state == .running {
            // If caller requested a mode switch, reconnect cleanly
            if useSignedInSession == attachedExternal {
                lastActivityAt = Date()
                return
            }
            await close()
        }

        // 1. Optional: try attaching to user's already-running signed-in Chrome CDP (default port 9222)
        if useSignedInSession {
            let attachPort = preferredPort ?? 9222
            if let wsURL = await fetchPageWebSocketURL(port: attachPort) {
                try await connectWebSocket(wsURL)
                self.debugPort = attachPort
                self.attachedExternal = true
                self.lastActivityAt = Date()
                return
            }
        }

        // 2. Spawn dedicated isolated headless Chrome/Chromium instance
        guard let chromeBin = Self.detectChromeBinary() else {
            throw PipiBrowserCUAError.chromeNotInstalled
        }

        let port = preferredPort ?? Int.random(in: 19222...29222)
        let profileDir: URL
        if let persistentProfileDirectory {
            profileDir = persistentProfileDirectory
        } else {
            profileDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pipibot-cua-chrome-\(port)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: chromeBin)
        proc.arguments = [
            "--headless=new",
            "--remote-debugging-port=\(port)",
            "--remote-debugging-address=127.0.0.1",
            "--user-data-dir=\(profileDir.path)",
            "--window-size=\(viewportWidth),\(viewportHeight)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-default-apps",
            "--disable-popup-blocking",
            "--disable-sync",
            "--mute-audio",
            "--disable-blink-features=AutomationControlled",
            "--user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36",
            "about:blank"
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()

        self.managedProcess = proc
        self.managedProfileDir = profileDir
        self.debugPort = port
        self.attachedExternal = false

        // Wait up to 8s for Chrome CDP HTTP endpoint to become ready
        var resolvedWS: URL? = nil
        for _ in 0..<40 {
            if !proc.isRunning {
                throw PipiBrowserCUAError.cdpUnavailable("Headless Chrome exited prematurely with status \(proc.terminationStatus)")
            }
            if let wsURL = await fetchPageWebSocketURL(port: port) {
                resolvedWS = wsURL
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        guard let wsURL = resolvedWS else {
            await close()
            throw PipiBrowserCUAError.cdpUnavailable("Timed out waiting for Chrome DevTools Protocol on port \(port)")
        }

        try await connectWebSocket(wsURL)
        _ = try? await sendCDP("Emulation.setDeviceMetricsOverride", params: [
            "width": viewportWidth,
            "height": viewportHeight,
            "deviceScaleFactor": 1,
            "mobile": false
        ])
        self.lastActivityAt = Date()
        #endif
    }

    /// Navigates to a URL, waits for DOM + SPA hydration, and returns a structured snapshot + JPEG screenshot.
    public func navigate(
        url rawURL: String,
        useSignedInSession: Bool = false,
        deliverablesDirectory: URL? = nil,
        allowDataHTML: Bool = false,
        settleMilliseconds: UInt64 = 1100
    ) async throws -> PipiBrowserCUASnapshot {
        let validation = PipiBrowserCUASafetyPolicy.validateNavigationURL(rawURL, allowDataHTML: allowDataHTML)
        guard validation.allowed else {
            throw PipiBrowserCUAError.invalidURL(validation.assessment?.reason ?? rawURL)
        }

        #if os(iOS) && canImport(WebKit)
        let snap = try await PipiIOSWebKitCUASession.shared.navigate(
            urlString: validation.normalizedURL,
            domSnapshotScript: Self.domSnapshotScript,
            deliverablesDirectory: deliverablesDirectory,
            settleMilliseconds: settleMilliseconds
        )
        self.lastSnapshot = snap
        self.lastActivityAt = Date()
        return snap
        #else
        try await ensureConnected(useSignedInSession: useSignedInSession)
        _ = try await sendCDP("Page.navigate", params: ["url": validation.normalizedURL])

        // Poll document.readyState up to 8s
        for _ in 0..<32 {
            try await Task.sleep(for: .milliseconds(250))
            if let stateRes = try? await evalJS("document.readyState"),
               let ready = stateRes as? String,
               (ready == "complete" || ready == "interactive") {
                if ready == "complete" { break }
            }
        }
        // Extra settle window for JS SPA hydration (X/React/Next.js)
        if settleMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(Int(settleMilliseconds)))
        }

        return try await captureSnapshot(deliverablesDirectory: deliverablesDirectory)
        #endif
    }

    /// Captures live DOM visible text, numbered interactive elements `[e1]..[e45]`, and a JPEG viewport screenshot.
    public func captureSnapshot(
        deliverablesDirectory: URL? = nil,
        includeScreenshot: Bool = true
    ) async throws -> PipiBrowserCUASnapshot {
        #if os(iOS) && canImport(WebKit)
        let snap = try await PipiIOSWebKitCUASession.shared.captureSnapshot(
            domSnapshotScript: Self.domSnapshotScript,
            deliverablesDirectory: deliverablesDirectory,
            includeScreenshot: includeScreenshot
        )
        self.lastSnapshot = snap
        self.lastActivityAt = Date()
        return snap
        #else
        try await ensureConnected(useSignedInSession: attachedExternal)

        let rawEval = try await evalJS(Self.domSnapshotScript)
        guard let jsonStr = rawEval as? String,
              let jsonData = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw PipiBrowserCUAError.cdpError("Failed to parse DOM snapshot payload")
        }

        let url = (dict["url"] as? String) ?? ""
        let title = (dict["title"] as? String) ?? ""
        let scrollY = (dict["scrollY"] as? Int) ?? 0
        let scrollHeight = (dict["scrollHeight"] as? Int) ?? 0
        let viewportHeight = (dict["viewportHeight"] as? Int) ?? 800
        let visibleText = (dict["visibleText"] as? String) ?? ""

        var elements: [PipiBrowserCUAElement] = []
        if let rawEls = dict["elements"] as? [[String: Any]] {
            for item in rawEls {
                guard let ref = item["ref"] as? String else { continue }
                elements.append(PipiBrowserCUAElement(
                    ref: ref,
                    tag: (item["tag"] as? String) ?? "div",
                    role: (item["role"] as? String) ?? "element",
                    label: (item["label"] as? String) ?? "",
                    href: item["href"] as? String,
                    inputType: item["inputType"] as? String,
                    x: (item["x"] as? Double) ?? Double((item["x"] as? Int) ?? 0),
                    y: (item["y"] as? Double) ?? Double((item["y"] as? Int) ?? 0),
                    width: (item["width"] as? Double) ?? Double((item["width"] as? Int) ?? 0),
                    height: (item["height"] as? Double) ?? Double((item["height"] as? Int) ?? 0)
                ))
            }
        }

        var b64Screenshot: String? = nil
        var savedPath: String? = nil
        if includeScreenshot {
            if let shotRes = try? await sendCDP("Page.captureScreenshot", params: [
                "format": "jpeg",
                "quality": 70,
                "fromSurface": true
            ]), let dataB64 = shotRes["data"] as? String, !dataB64.isEmpty {
                b64Screenshot = dataB64
                if let dir = deliverablesDirectory, let rawImg = Data(base64Encoded: dataB64) {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let fileName = "browser-cua-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(4).lowercased()).jpg"
                    let fileURL = dir.appendingPathComponent(fileName)
                    if (try? rawImg.write(to: fileURL)) != nil {
                        savedPath = fileURL.path
                    }
                }
            }
        }

        let snap = PipiBrowserCUASnapshot(
            url: url,
            title: title,
            scrollY: scrollY,
            scrollHeight: scrollHeight,
            viewportHeight: viewportHeight,
            visibleText: visibleText,
            elements: elements,
            screenshotBase64: b64Screenshot,
            screenshotPath: savedPath
        )
        self.lastSnapshot = snap
        self.lastActivityAt = Date()
        return snap
        #endif
    }

    /// Executes an interactive CUA action (`click`, `type`, `scroll`, `press_key`, `wait`, `back`, `reload`),
    /// checks safety policy against the target element, and returns the updated page snapshot + screenshot.
    public func perform(
        request: PipiBrowserCUAActionRequest,
        deliverablesDirectory: URL? = nil,
        skipSafetyCheck: Bool = false
    ) async throws -> (snapshot: PipiBrowserCUASnapshot, blockedAssessment: PipiToolRiskAssessment?) {
        try await ensureConnected(useSignedInSession: attachedExternal)

        let targetEl: PipiBrowserCUAElement? = request.ref.flatMap { ref in
            lastSnapshot?.elements.first(where: { $0.ref.caseInsensitiveCompare(ref) == .orderedSame })
        }

        if !skipSafetyCheck {
            if let risk = PipiBrowserCUASafetyPolicy.evaluateAction(
                request: request,
                targetElement: targetEl,
                currentURL: lastSnapshot?.url ?? ""
            ) {
                let snap = lastSnapshot ?? PipiBrowserCUASnapshot(url: "", title: "", visibleText: "")
                return (snap, risk)
            }
        }

        #if os(iOS) && canImport(WebKit)
        let updated = try await PipiIOSWebKitCUASession.shared.perform(
            request: request,
            domSnapshotScript: Self.domSnapshotScript,
            deliverablesDirectory: deliverablesDirectory
        )
        self.lastSnapshot = updated
        self.lastActivityAt = Date()
        return (updated, nil)
        #else

        switch request.action {
        case .click:
            var clickX = request.x
            var clickY = request.y
            if let ref = request.ref, !ref.isEmpty {
                if let coords = try await resolveElementCenter(ref: ref) {
                    clickX = coords.x
                    clickY = coords.y
                } else if let el = targetEl {
                    clickX = el.x
                    clickY = el.y
                } else {
                    throw PipiBrowserCUAError.elementNotFound(ref)
                }
            }
            guard let x = clickX, let y = clickY else {
                throw PipiBrowserCUAError.cdpError("click action requires either ref (e.g. 'e1') or x/y coordinates")
            }
            _ = try await sendCDP("Input.dispatchMouseEvent", params: ["type": "mouseMoved", "x": x, "y": y])
            _ = try await sendCDP("Input.dispatchMouseEvent", params: ["type": "mousePressed", "x": x, "y": y, "button": "left", "clickCount": 1])
            _ = try await sendCDP("Input.dispatchMouseEvent", params: ["type": "mouseReleased", "x": x, "y": y, "button": "left", "clickCount": 1])
            try await Task.sleep(for: .milliseconds(700))

        case .type:
            let text = request.text ?? ""
            if let ref = request.ref, !ref.isEmpty {
                if let coords = try await resolveElementCenter(ref: ref) {
                    _ = try await sendCDP("Input.dispatchMouseEvent", params: ["type": "mousePressed", "x": coords.x, "y": coords.y, "button": "left", "clickCount": 1])
                    _ = try await sendCDP("Input.dispatchMouseEvent", params: ["type": "mouseReleased", "x": coords.x, "y": coords.y, "button": "left", "clickCount": 1])
                    try await Task.sleep(for: .milliseconds(150))
                }
            }
            if !text.isEmpty {
                _ = try await sendCDP("Input.insertText", params: ["text": text])
            }
            if request.submit {
                try await dispatchSpecialKey("Enter")
            }
            try await Task.sleep(for: .milliseconds(500))

        case .scroll:
            let dir = (request.direction ?? "down").lowercased()
            let amount = request.deltaY ?? 620
            let js: String
            switch dir {
            case "up": js = "window.scrollBy(0, -\(Int(abs(amount))));"
            case "top": js = "window.scrollTo(0, 0);"
            case "bottom": js = "window.scrollTo(0, document.body.scrollHeight);"
            default: js = "window.scrollBy(0, \(Int(abs(amount))));"
            }
            _ = try await evalJS(js)
            try await Task.sleep(for: .milliseconds(450))

        case .pressKey:
            let key = request.key ?? "Enter"
            try await dispatchSpecialKey(key)
            try await Task.sleep(for: .milliseconds(450))

        case .wait:
            let secs = max(0.2, min(8.0, request.seconds ?? 1.5))
            try await Task.sleep(for: .milliseconds(Int(secs * 1000)))

        case .back:
            _ = try await evalJS("window.history.back();")
            try await Task.sleep(for: .milliseconds(800))

        case .reload:
            _ = try await sendCDP("Page.reload", params: [:])
            try await Task.sleep(for: .milliseconds(900))
        }

        let updated = try await captureSnapshot(deliverablesDirectory: deliverablesDirectory)
        return (updated, nil)
        #endif
    }

    /// Cleanly closes the WebSocket and terminates any managed isolated Chrome process.
    public func close() async {
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        let pending = pendingCallbacks
        pendingCallbacks.removeAll()
        for (_, cont) in pending {
            cont.resume(throwing: PipiBrowserCUAError.cdpUnavailable("Browser session closed"))
        }

        if let proc = managedProcess {
            if proc.isRunning {
                proc.terminate()
            }
            managedProcess = nil
        }
        if let dir = managedProfileDir {
            // Preserve persistent teammate browser profiles so LinkedIn / X / Reddit cookies survive restarts!
            if persistentProfileDirectory == nil {
                try? FileManager.default.removeItem(at: dir)
            }
            managedProfileDir = nil
        }
        lastSnapshot = nil
        attachedExternal = false
        debugPort = 0
    }

    // MARK: - Internal CDP Plumbing

    private func fetchPageWebSocketURL(port: Int) async -> URL? {
        guard let listURL = URL(string: "http://127.0.0.1:\(port)/json/list") else { return nil }
        var req = URLRequest(url: listURL)
        req.timeoutInterval = 2.5
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        for item in items {
            let type = (item["type"] as? String) ?? ""
            if type == "page", let wsStr = item["webSocketDebuggerUrl"] as? String, let wsURL = URL(string: wsStr) {
                return wsURL
            }
        }
        return nil
    }

    private func connectWebSocket(_ url: URL) async throws {
        let ws = URLSession.shared.webSocketTask(with: url)
        ws.maximumMessageSize = 32 * 1024 * 1024 // 32 MB for high-res screenshots
        ws.resume()
        self.webSocketTask = ws

        self.receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await ws.receive()
                    let data: Data
                    switch message {
                    case .string(let text):
                        data = Data(text.utf8)
                    case .data(let raw):
                        data = raw
                    @unknown default:
                        continue
                    }
                    await self?.handleIncomingCDPMessage(data)
                } catch {
                    await self?.failAllPending(error)
                    break
                }
            }
        }

        _ = try? await sendCDP("Page.enable", params: [:])
        _ = try? await sendCDP("Runtime.enable", params: [:])
    }

    private func handleIncomingCDPMessage(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["id"] as? Int,
              let cont = pendingCallbacks.removeValue(forKey: id) else {
            return
        }
        if let err = obj["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "CDP error"
            cont.resume(throwing: PipiBrowserCUAError.cdpError(msg))
        } else {
            let result = (obj["result"] as? [String: Any]) ?? [:]
            cont.resume(returning: result)
        }
    }

    private func failAllPending(_ error: Error) {
        let pending = pendingCallbacks
        pendingCallbacks.removeAll()
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }

    private func sendCDP(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        guard let ws = webSocketTask else {
            throw PipiBrowserCUAError.cdpUnavailable("WebSocket not connected")
        }
        let id = nextMessageId
        nextMessageId += 1

        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw PipiBrowserCUAError.cdpError("Failed to encode CDP command \(method)")
        }

        return try await withCheckedThrowingContinuation { cont in
            pendingCallbacks[id] = cont
            ws.send(.string(jsonString)) { [weak self] sendError in
                if let sendError {
                    Task { await self?.rejectPending(id: id, error: sendError) }
                }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                await self?.rejectPending(id: id, error: PipiBrowserCUAError.cdpTimeout(method))
            }
        }
    }

    private func rejectPending(id: Int, error: Error) {
        if let cont = pendingCallbacks.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    private func evalJS(_ expression: String) async throws -> Any? {
        let res = try await sendCDP("Runtime.evaluate", params: [
            "expression": expression,
            "returnByValue": true,
            "awaitPromise": true
        ])
        if let exc = res["exceptionDetails"] as? [String: Any] {
            let text = (exc["text"] as? String) ?? "JS evaluation exception"
            throw PipiBrowserCUAError.cdpError(text)
        }
        let resultObj = res["result"] as? [String: Any]
        return resultObj?["value"]
    }

    private func resolveElementCenter(ref: String) async throws -> (x: Double, y: Double)? {
        let safeRef = ref.replacingOccurrences(of: "\"", with: "")
        let script = """
        (() => {
          const map = window.__pipiRefs || {};
          const el = map["\(safeRef)"];
          if (!el || !el.isConnected) return null;
          el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
          const r = el.getBoundingClientRect();
          if (r.width <= 0 || r.height <= 0) return null;
          return JSON.stringify({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
        })()
        """
        guard let raw = try await evalJS(script) as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let x = obj["x"] as? Double,
              let y = obj["y"] as? Double else {
            return nil
        }
        return (x, y)
    }

    private func dispatchSpecialKey(_ key: String) async throws {
        let keyCodeMap: [String: (code: String, keyCode: Int, text: String?)] = [
            "Enter": ("Enter", 13, "\r"),
            "Escape": ("Escape", 27, nil),
            "Tab": ("Tab", 9, nil),
            "Backspace": ("Backspace", 8, nil),
            "Space": ("Space", 32, " "),
            "ArrowDown": ("ArrowDown", 40, nil),
            "ArrowUp": ("ArrowUp", 38, nil),
            "PageDown": ("PageDown", 34, nil),
            "PageUp": ("PageUp", 33, nil)
        ]
        let mapped = keyCodeMap[key] ?? (key, 0, key.count == 1 ? key : nil)
        var downParams: [String: Any] = [
            "type": "keyDown",
            "key": key,
            "code": mapped.code,
            "windowsVirtualKeyCode": mapped.keyCode,
            "nativeVirtualKeyCode": mapped.keyCode
        ]
        if let text = mapped.text { downParams["text"] = text }
        _ = try await sendCDP("Input.dispatchKeyEvent", params: downParams)
        _ = try await sendCDP("Input.dispatchKeyEvent", params: [
            "type": "keyUp",
            "key": key,
            "code": mapped.code,
            "windowsVirtualKeyCode": mapped.keyCode,
            "nativeVirtualKeyCode": mapped.keyCode
        ])
    }

    /// Compact JS snapshot extractor: assigns `[e1]..[e45]` refs to visible interactive elements
    /// and collects clean rendered page text.
    private static let domSnapshotScript: String = """
    (() => {
      window.__pipiRefs = {};
      const vw = window.innerWidth || 1280;
      const vh = window.innerHeight || 800;
      const selectors = 'a, button, input, textarea, select, [role="button"], [role="link"], [role="tab"], [role="menuitem"], summary';
      const nodes = Array.from(document.querySelectorAll(selectors));
      const elements = [];
      let idx = 0;

      for (const el of nodes) {
        if (elements.length >= 45) break;
        const style = window.getComputedStyle(el);
        if (!style || style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity || '1') === 0) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 6 || r.height < 6) continue;
        if (r.bottom < -120 || r.top > vh + 240 || r.right < 0 || r.left > vw) continue;

        const tag = (el.tagName || '').toLowerCase();
        const role = el.getAttribute('role') || (tag === 'a' ? 'link' : tag);
        const rawLabel = (
          el.getAttribute('aria-label') ||
          el.innerText ||
          el.getAttribute('placeholder') ||
          el.getAttribute('title') ||
          el.value ||
          ''
        ).replace(/\\s+/g, ' ').trim();
        const href = tag === 'a' ? (el.getAttribute('href') || '') : '';
        if (!rawLabel && !href && tag !== 'input' && tag !== 'textarea') continue;

        idx += 1;
        const ref = 'e' + idx;
        window.__pipiRefs[ref] = el;
        elements.push({
          ref,
          tag,
          role,
          label: rawLabel.slice(0, 96),
          href: href ? href.slice(0, 140) : null,
          inputType: (tag === 'input') ? (el.getAttribute('type') || 'text') : null,
          x: Math.round(r.left + r.width / 2),
          y: Math.round(r.top + r.height / 2),
          width: Math.round(r.width),
          height: Math.round(r.height)
        });
      }

      const mainRoot = document.querySelector('main, article, [role="main"]') || document.body;
      const rawText = (mainRoot && mainRoot.innerText ? mainRoot.innerText : (document.body ? document.body.innerText : '')) || '';
      const cleanText = rawText
        .replace(/\\r/g, '')
        .replace(/[ \\t]+/g, ' ')
        .replace(/\\n{3,}/g, '\\n\\n')
        .trim()
        .slice(0, 6800);

      return JSON.stringify({
        url: location.href,
        title: document.title || '',
        scrollY: Math.round(window.scrollY || 0),
        scrollHeight: Math.round(document.documentElement ? document.documentElement.scrollHeight : 0),
        viewportHeight: Math.round(vh),
        visibleText: cleanText,
        elements
      });
    })()
    """
}

// MARK: - 4. Isolated Multimodal Browser Subagent

public struct PipiBrowserCUASubagentResult: Sendable {
    public let summary: String
    public let visitedURLs: [String]
    public let stepsExecuted: Int
    public let latestScreenshotPath: String?
    public let latestImage: PipiEncodedImagePart?
    public let blockedAssessment: PipiToolRiskAssessment?

    public init(
        summary: String,
        visitedURLs: [String],
        stepsExecuted: Int,
        latestScreenshotPath: String? = nil,
        latestImage: PipiEncodedImagePart? = nil,
        blockedAssessment: PipiToolRiskAssessment? = nil
    ) {
        self.summary = summary
        self.visitedURLs = visitedURLs
        self.stepsExecuted = stepsExecuted
        self.latestScreenshotPath = latestScreenshotPath
        self.latestImage = latestImage
        self.blockedAssessment = blockedAssessment
    }
}

public enum PipiBrowserCUASubagent {
    private static let subagentTools: [PipiAgentToolDefinition] = [
        PipiAgentToolDefinition(
            name: "cua_act",
            description: "Interact with the currently open live webpage: click an element by ref (e.g. 'e4'), type text, scroll up/down/bottom, press a key, go back, or wait. Returns the updated DOM text, interactive element refs, and a fresh viewport screenshot.",
            parameters: [
                PipiAgentToolParam(name: "action", description: "click | type | scroll | press_key | wait | back | reload", required: true),
                PipiAgentToolParam(name: "ref", description: "Element ref from snapshot (e.g. 'e1', 'e12') for click/type", required: false),
                PipiAgentToolParam(name: "text", description: "Text to type when action=type", required: false),
                PipiAgentToolParam(name: "submit", description: "Set 'true' to press Enter after typing", required: false),
                PipiAgentToolParam(name: "direction", description: "down | up | top | bottom (when action=scroll)", required: false),
                PipiAgentToolParam(name: "key", description: "Key name (Enter, Escape, Tab, PageDown, Space) when action=press_key", required: false),
                PipiAgentToolParam(name: "seconds", description: "Seconds to wait (0.5-6) when action=wait", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "cua_navigate",
            description: "Navigate the live browser to another http/https URL and inspect its rendered content and screenshot.",
            parameters: [
                PipiAgentToolParam(name: "url", description: "Target http/https URL", required: true)
            ]
        )
    ]

    /// Runs an isolated, multimodal CUA browsing session inside its own message context so
    /// multi-step web DOM & screenshots never pollute the parent Jarvis conversation.
    public static func run(
        url: String,
        goal: String,
        llmConfig: PipiLLMProviderConfig,
        deliverablesDirectory: URL,
        useSignedInSession: Bool = false,
        maxSteps: Int = 8,
        botId: String? = nil,
        remoteCDPEndpoint: String? = nil
    ) async throws -> PipiBrowserCUASubagentResult {
        let usesPersistentTeammateDriver = (botId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let driver: PipiBrowserCUADriver
        if let botId, usesPersistentTeammateDriver {
            driver = await PipiTeammateBrowserRegistry.shared.driver(
                forBotId: botId,
                remoteCDPEndpoint: remoteCDPEndpoint
            )
        } else {
            driver = PipiBrowserCUADriver()
        }
        defer {
            if !usesPersistentTeammateDriver {
                Task { await driver.close() }
            }
        }

        let initialSnap = try await driver.navigate(
            url: url,
            useSignedInSession: useSignedInSession,
            deliverablesDirectory: deliverablesDirectory
        )
        var visited: [String] = [initialSnap.url]
        var latestShotPath = initialSnap.screenshotPath
        var latestImg = initialSnap.encodedImagePart

        let systemPrompt = """
        You are PiPiBot's isolated Web CUA (Computer Use Agent) Subagent.
        Your mission: read and interact with the live rendered webpage until you thoroughly satisfy the user's goal, then return a clear, factual summary in the same language as the goal.
        Rules:
        1. You receive BOTH the structured DOM snapshot (visible text + numbered interactive elements like [e1], [e2]) AND the live viewport screenshot.
        2. Use `cua_act` (scroll down, click "Show more" / "展开" / tabs, wait for media) if the full content isn't visible yet.
        3. Stop as soon as you have gathered complete, accurate information — do not browse unnecessarily.
        4. Never fabricate content that isn't visible in the page text or screenshot. If blocked by a login wall or CAPTCHA, clearly report what you could see and what is gated.
        """

        var wire: [PipiAgentWireMessage] = [
            .system(systemPrompt),
            .user(
                text: "Goal: \(goal)\n\n\(initialSnap.formattedForModel())",
                images: latestImg.map { [$0] } ?? []
            )
        ]

        let boundedSteps = max(2, min(12, maxSteps))
        var executed = 1

        for step in 1...boundedSteps {
            if Task.isCancelled { throw CancellationError() }

            let compacted = PipiVisionContextCompactor.compact(messages: wire, maxRetainedImages: 2)
            let stepResult = try await PipiInferenceEngine.invokeLLMWithTools(
                config: llmConfig,
                messages: compacted,
                tools: subagentTools
            )

            if stepResult.toolCalls.isEmpty {
                return PipiBrowserCUASubagentResult(
                    summary: stepResult.text.isEmpty ? initialSnap.formattedForModel(maxTextChars: 2400) : stepResult.text,
                    visitedURLs: visited,
                    stepsExecuted: executed,
                    latestScreenshotPath: latestShotPath,
                    latestImage: latestImg
                )
            }

            wire.append(.assistant(text: stepResult.text, toolCalls: stepResult.toolCalls))

            for tc in stepResult.toolCalls {
                executed += 1
                if tc.name == "cua_navigate" {
                    let nextURL = tc.string("url") ?? ""
                    let check = PipiBrowserCUASafetyPolicy.validateNavigationURL(nextURL)
                    if !check.allowed, let risk = check.assessment {
                        return PipiBrowserCUASubagentResult(
                            summary: "⏸️ 浏览器子代理已暂停：\(risk.reason)",
                            visitedURLs: visited,
                            stepsExecuted: executed,
                            latestScreenshotPath: latestShotPath,
                            latestImage: latestImg,
                            blockedAssessment: risk
                        )
                    }
                    do {
                        let snap = try await driver.navigate(
                            url: nextURL,
                            useSignedInSession: useSignedInSession,
                            deliverablesDirectory: deliverablesDirectory
                        )
                        if !visited.contains(snap.url) { visited.append(snap.url) }
                        latestShotPath = snap.screenshotPath
                        latestImg = snap.encodedImagePart
                        wire.append(.toolResult(callId: tc.id, toolName: tc.name, content: snap.formattedForModel()))
                        if let img = latestImg {
                            wire.append(.user(text: "[Updated viewport screenshot after navigation]", images: [img]))
                        }
                    } catch {
                        wire.append(.toolResult(callId: tc.id, toolName: tc.name, content: "Navigation failed: \(error.localizedDescription)"))
                    }
                } else if tc.name == "cua_act" {
                    let kind = PipiBrowserCUAActionKind(rawValue: (tc.string("action") ?? "scroll").lowercased()) ?? .scroll
                    let req = PipiBrowserCUAActionRequest(
                        action: kind,
                        ref: tc.string("ref"),
                        text: tc.string("text"),
                        key: tc.string("key"),
                        direction: tc.string("direction"),
                        seconds: tc.int("seconds").map { Double($0) },
                        submit: (tc.string("submit") ?? "").lowercased() == "true"
                    )
                    do {
                        let (snap, blocked) = try await driver.perform(request: req, deliverablesDirectory: deliverablesDirectory)
                        if let blocked {
                            return PipiBrowserCUASubagentResult(
                                summary: "⏸️ 浏览器子代理触发安全护栏：\(blocked.summary) — \(blocked.reason)",
                                visitedURLs: visited,
                                stepsExecuted: executed,
                                latestScreenshotPath: latestShotPath,
                                latestImage: latestImg,
                                blockedAssessment: blocked
                            )
                        }
                        if !visited.contains(snap.url) { visited.append(snap.url) }
                        latestShotPath = snap.screenshotPath
                        latestImg = snap.encodedImagePart
                        wire.append(.toolResult(callId: tc.id, toolName: tc.name, content: snap.formattedForModel()))
                        if let img = latestImg {
                            wire.append(.user(text: "[Updated viewport screenshot after \(kind.rawValue)]", images: [img]))
                        }
                    } catch {
                        wire.append(.toolResult(callId: tc.id, toolName: tc.name, content: "Action failed: \(error.localizedDescription)"))
                    }
                } else {
                    wire.append(.toolResult(callId: tc.id, toolName: tc.name, content: "Unknown browser subagent tool: \(tc.name)"))
                }
            }

            if step == boundedSteps {
                wire.append(.user(text: "Maximum browsing steps reached. Summarize everything you observed directly and factually to answer the goal.", images: []))
                let wrap = try await PipiInferenceEngine.invokeLLMWithTools(
                    config: llmConfig,
                    messages: PipiVisionContextCompactor.compact(messages: wire, maxRetainedImages: 1),
                    tools: []
                )
                return PipiBrowserCUASubagentResult(
                    summary: wrap.text,
                    visitedURLs: visited,
                    stepsExecuted: executed,
                    latestScreenshotPath: latestShotPath,
                    latestImage: latestImg
                )
            }
        }

        return PipiBrowserCUASubagentResult(
            summary: initialSnap.formattedForModel(maxTextChars: 2400),
            visitedURLs: visited,
            stepsExecuted: executed,
            latestScreenshotPath: latestShotPath,
            latestImage: latestImg
        )
    }
}

// MARK: - 4.5 Per-Teammate Persistent Isolated Browser Registry (Brigade Mode)

/// Maintains a dedicated, persistent Chrome/Chromium profile and CDP session per AI teammate (`botId`),
/// allowing independent logged-in sessions on LinkedIn, X, Reddit, and GitHub without cookie collisions.
public actor PipiTeammateBrowserRegistry {
    public static let shared = PipiTeammateBrowserRegistry()

    private var drivers: [String: PipiBrowserCUADriver] = [:]

    public init() {}

    public func driver(
        forBotId botId: String,
        remoteCDPEndpoint: String? = nil
    ) -> PipiBrowserCUADriver {
        let cleanId = botId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanId.isEmpty else { return PipiBrowserCUADriver.shared }
        if let existing = drivers[cleanId] {
            return existing
        }
        let profileDir = PipiSubscriptionAccountPoolEngine.defaultBrowserProfileDirectory(botId: cleanId)
        let created = PipiBrowserCUADriver(
            botId: cleanId,
            persistentProfileDirectory: profileDir,
            remoteCDPEndpoint: remoteCDPEndpoint
        )
        drivers[cleanId] = created
        return created
    }

    public func activeBotIds() -> [String] {
        Array(drivers.keys).sorted()
    }

    public func closeDriver(forBotId botId: String) async {
        guard let existing = drivers.removeValue(forKey: botId) else { return }
        await existing.close()
    }

    public func closeAll() async {
        let all = Array(drivers.values)
        drivers.removeAll()
        for d in all {
            await d.close()
        }
    }
}

// MARK: - 5. Native iOS WebKit CUA Driver (OpenMinis-style In-App Mobile Browser)

#if os(iOS) && canImport(WebKit)
@MainActor
final class PipiIOSWebKitCUASession {
    static let shared = PipiIOSWebKitCUASession()

    private var webView: WKWebView?

    func ensureReady(width: Int = 393, height: Int = 852) {
        if webView == nil {
            let cfg = WKWebViewConfiguration()
            cfg.allowsInlineMediaPlayback = true
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height), configuration: cfg)
            wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"
            self.webView = wv
        }
    }

    func navigate(
        urlString: String,
        domSnapshotScript: String,
        deliverablesDirectory: URL?,
        settleMilliseconds: UInt64
    ) async throws -> PipiBrowserCUASnapshot {
        ensureReady()
        guard let wv = webView, let url = URL(string: urlString) else {
            throw PipiBrowserCUAError.invalidURL(urlString)
        }
        wv.load(URLRequest(url: url))
        for _ in 0..<32 {
            try await Task.sleep(for: .milliseconds(250))
            if !wv.isLoading { break }
        }
        if settleMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(Int(settleMilliseconds)))
        }
        return try await captureSnapshot(domSnapshotScript: domSnapshotScript, deliverablesDirectory: deliverablesDirectory, includeScreenshot: true)
    }

    func captureSnapshot(
        domSnapshotScript: String,
        deliverablesDirectory: URL?,
        includeScreenshot: Bool
    ) async throws -> PipiBrowserCUASnapshot {
        ensureReady()
        guard let wv = webView else {
            throw PipiBrowserCUAError.cdpUnavailable("WKWebView not initialized")
        }
        let raw = try await wv.evaluateJavaScript(domSnapshotScript)
        guard let jsonStr = raw as? String,
              let jsonData = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw PipiBrowserCUAError.cdpError("Failed to decode WKWebView DOM snapshot")
        }

        var elements: [PipiBrowserCUAElement] = []
        if let rawEls = dict["elements"] as? [[String: Any]] {
            for item in rawEls {
                guard let ref = item["ref"] as? String else { continue }
                elements.append(PipiBrowserCUAElement(
                    ref: ref,
                    tag: (item["tag"] as? String) ?? "div",
                    role: (item["role"] as? String) ?? "element",
                    label: (item["label"] as? String) ?? "",
                    href: item["href"] as? String,
                    inputType: item["inputType"] as? String,
                    x: (item["x"] as? Double) ?? Double((item["x"] as? Int) ?? 0),
                    y: (item["y"] as? Double) ?? Double((item["y"] as? Int) ?? 0),
                    width: (item["width"] as? Double) ?? Double((item["width"] as? Int) ?? 0),
                    height: (item["height"] as? Double) ?? Double((item["height"] as? Int) ?? 0)
                ))
            }
        }

        var b64: String? = nil
        var shotPath: String? = nil
        if includeScreenshot, let img = try? await wv.takeSnapshot(configuration: nil),
           let jpeg = img.jpegData(compressionQuality: 0.72) {
            b64 = jpeg.base64EncodedString()
            if let dir = deliverablesDirectory {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let fileURL = dir.appendingPathComponent("ios-cua-\(Int(Date().timeIntervalSince1970)).jpg")
                if (try? jpeg.write(to: fileURL)) != nil {
                    shotPath = fileURL.path
                }
            }
        }

        return PipiBrowserCUASnapshot(
            url: (dict["url"] as? String) ?? wv.url?.absoluteString ?? "",
            title: (dict["title"] as? String) ?? wv.title ?? "",
            scrollY: (dict["scrollY"] as? Int) ?? 0,
            scrollHeight: (dict["scrollHeight"] as? Int) ?? 0,
            viewportHeight: (dict["viewportHeight"] as? Int) ?? 852,
            visibleText: (dict["visibleText"] as? String) ?? "",
            elements: elements,
            screenshotBase64: b64,
            screenshotPath: shotPath
        )
    }

    func perform(
        request: PipiBrowserCUAActionRequest,
        domSnapshotScript: String,
        deliverablesDirectory: URL?
    ) async throws -> PipiBrowserCUASnapshot {
        ensureReady()
        guard let wv = webView else {
            throw PipiBrowserCUAError.cdpUnavailable("WKWebView not initialized")
        }
        switch request.action {
        case .click:
            let safeRef = (request.ref ?? "").replacingOccurrences(of: "\"", with: "")
            _ = try? await wv.evaluateJavaScript("""
            (() => {
              const el = (window.__pipiRefs || {})["\(safeRef)"];
              if (!el) return false;
              el.scrollIntoView({ block: 'center', behavior: 'instant' });
              el.click();
              return true;
            })()
            """)
            try await Task.sleep(for: .milliseconds(700))
        case .type:
            let safeRef = (request.ref ?? "").replacingOccurrences(of: "\"", with: "")
            let escapedText = (request.text ?? "")
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            _ = try? await wv.evaluateJavaScript("""
            (() => {
              const el = (window.__pipiRefs || {})["\(safeRef)"] || document.activeElement;
              if (!el) return false;
              el.focus();
              el.value = "\(escapedText)";
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
              return true;
            })()
            """)
            try await Task.sleep(for: .milliseconds(450))
        case .scroll:
            let dir = (request.direction ?? "down").lowercased()
            let amount = Int(abs(request.deltaY ?? 600))
            let js = dir == "up" ? "window.scrollBy(0, -\(amount));" : (dir == "top" ? "window.scrollTo(0, 0);" : (dir == "bottom" ? "window.scrollTo(0, document.body.scrollHeight);" : "window.scrollBy(0, \(amount));"))
            _ = try? await wv.evaluateJavaScript(js)
            try await Task.sleep(for: .milliseconds(400))
        case .wait:
            let secs = max(0.2, min(8.0, request.seconds ?? 1.5))
            try await Task.sleep(for: .milliseconds(Int(secs * 1000)))
        case .back:
            wv.goBack()
            try await Task.sleep(for: .milliseconds(700))
        case .reload:
            wv.reload()
            try await Task.sleep(for: .milliseconds(800))
        case .pressKey:
            try await Task.sleep(for: .milliseconds(300))
        }
        return try await captureSnapshot(domSnapshotScript: domSnapshotScript, deliverablesDirectory: deliverablesDirectory, includeScreenshot: true)
    }
}
#endif
