// PiPiBot — Clean-room MIT implementation.
// Unified Account & Device Registry Client for macOS & iOS (`https://pipibot.jimizhou.com`).
// Supports Email 6-digit OTP + Browser OAuth Device Flow (Apple / GitHub / Google).

import Foundation
#if os(macOS)
import AppKit
#endif

public struct PipiAccountUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let email: String?
    public let displayName: String
    public let avatarUrl: String?
    public let providers: [String]
}

public struct PipiAccountDevice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let userId: String
    public let name: String
    public let platform: String
    public let hostId: String
    public let hostPubKey: String
    public let capabilities: [String]
    public let workspacePath: String?
    public let isOnline: Bool
    public let lastSeenAt: String
}

@MainActor
@Observable
public final class PipiAccountClient {
    private static let tokenSecretKey = "pipibot_unified_account_token_v1"

    public var relayOrigin: String
    public private(set) var currentUser: PipiAccountUser? = nil
    public private(set) var devices: [PipiAccountDevice] = []
    public private(set) var isBusy: Bool = false
    public private(set) var statusMessage: String? = nil
    public private(set) var pendingBrowserUserCode: String? = nil

    private let secretStore: any PipiSecretStore
    private let session: URLSession
    private var pollTask: Task<Void, Never>? = nil
    private var verifiedPeerTokens: Set<String> = []

    public var accessToken: String? {
        secretStore.secret(for: Self.tokenSecretKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isSignedIn: Bool {
        currentUser != nil && (accessToken?.isEmpty == false)
    }

    public init(
        relayOrigin: String = PipiE2EERelayClient.defaultRelayOrigin,
        secretStore: any PipiSecretStore = PipiLocalEncryptedSecretStore(),
        session: URLSession = .shared
    ) {
        self.relayOrigin = relayOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.secretStore = secretStore
        self.session = session
    }

    // MARK: - Email 6-Digit OTP

    public func sendEmailOtp(email: String) async -> (ok: Bool, message: String, devCode: String?) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "请输入邮箱地址", nil) }
        isBusy = true
        defer { isBusy = false }

        guard let url = URL(string: "\(relayOrigin)/api/auth/email/send") else {
            return (false, "中转服务地址无效", nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["email": trimmed])

        do {
            let (data, _) = try await session.data(for: req)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let ok = (obj?["ok"] as? Bool) == true
            if ok {
                let devCode = obj?["devCode"] as? String
                let msg = devCode != nil ? "验证码已生成（测试码：\(devCode!)）" : "验证码已发送至邮箱，10 分钟内有效"
                statusMessage = msg
                return (true, msg, devCode)
            }
            let err = (obj?["error"] as? String) ?? "发送验证码失败"
            statusMessage = err
            return (false, err, nil)
        } catch {
            let msg = "无法连接 \(relayOrigin)：\(error.localizedDescription)"
            statusMessage = msg
            return (false, msg, nil)
        }
    }

    public func verifyEmailOtp(email: String, code: String) async -> (ok: Bool, message: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedCode.isEmpty else {
            return (false, "请输入邮箱和 6 位验证码")
        }
        isBusy = true
        defer { isBusy = false }

        guard let url = URL(string: "\(relayOrigin)/api/auth/email/verify") else {
            return (false, "中转服务地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": trimmedEmail,
            "code": trimmedCode,
            "clientLabel": "PiPiBot Mac"
        ])

        do {
            let (data, _) = try await session.data(for: req)
            struct VerifyResp: Decodable {
                let ok: Bool
                let error: String?
                let accessToken: String?
                let user: PipiAccountUser?
            }
            let decoded = try JSONDecoder().decode(VerifyResp.self, from: data)
            if decoded.ok, let token = decoded.accessToken, let user = decoded.user {
                secretStore.setSecret(token, for: Self.tokenSecretKey)
                self.currentUser = user
                self.statusMessage = "已登录 \(user.email ?? user.displayName)"
                await refreshProfile()
                return (true, "登录成功")
            }
            let err = decoded.error ?? "验证码无效"
            self.statusMessage = err
            return (false, err)
        } catch {
            let msg = "验证失败：\(error.localizedDescription)"
            self.statusMessage = msg
            return (false, msg)
        }
    }

    // MARK: - Browser OAuth Device Flow (Apple / GitHub / Google)

    public func startBrowserOAuthLogin(onSignedIn: @escaping @MainActor () -> Void) async {
        pollTask?.cancel()
        isBusy = true
        guard let url = URL(string: "\(relayOrigin)/api/auth/device/start") else {
            isBusy = false
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "clientLabel": "PiPiBot Mac (\(Host.current().localizedName ?? "Mac"))"
        ])

        do {
            let (data, _) = try await session.data(for: req)
            struct StartResp: Decodable {
                let deviceCode: String
                let userCode: String
                let verificationUrl: String
                let interval: Int?
            }
            let flow = try JSONDecoder().decode(StartResp.self, from: data)
            self.pendingBrowserUserCode = flow.userCode
            self.statusMessage = "请在浏览器完成 Apple / GitHub / Google 登录并确认授权码 \(flow.userCode)"
            self.isBusy = false

            #if os(macOS)
            if let openURL = URL(string: flow.verificationUrl) {
                NSWorkspace.shared.open(openURL)
            }
            #endif

            let intervalSec = max(2, flow.interval ?? 2)
            let deviceCode = flow.deviceCode
            pollTask = Task { [weak self] in
                for _ in 0..<180 {
                    try? await Task.sleep(for: .seconds(intervalSec))
                    guard !Task.isCancelled, let self else { return }
                    let done = await self.pollDeviceFlowOnce(deviceCode: deviceCode)
                    if done {
                        onSignedIn()
                        return
                    }
                }
                self?.pendingBrowserUserCode = nil
            }
        } catch {
            self.isBusy = false
            self.statusMessage = "发起浏览器登录失败：\(error.localizedDescription)"
        }
    }

    private func pollDeviceFlowOnce(deviceCode: String) async -> Bool {
        guard let url = URL(string: "\(relayOrigin)/api/auth/device/poll") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceCode": deviceCode])
        do {
            let (data, _) = try await session.data(for: req)
            struct PollResp: Decodable {
                let status: String
                let accessToken: String?
                let user: PipiAccountUser?
            }
            let resp = try JSONDecoder().decode(PollResp.self, from: data)
            if resp.status == "approved", let token = resp.accessToken, let user = resp.user {
                secretStore.setSecret(token, for: Self.tokenSecretKey)
                self.currentUser = user
                self.pendingBrowserUserCode = nil
                self.statusMessage = "已登录 \(user.email ?? user.displayName)"
                await refreshProfile()
                return true
            }
            if resp.status == "expired" {
                self.pendingBrowserUserCode = nil
                self.statusMessage = "授权已过期，请重试"
                return true
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Profile & Unified Device Registry

    public func refreshProfile() async {
        guard let token = accessToken, !token.isEmpty,
              let url = URL(string: "\(relayOrigin)/api/auth/me") else {
            self.currentUser = nil
            self.devices = []
            return
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                secretStore.deleteSecret(for: Self.tokenSecretKey)
                self.currentUser = nil
                self.devices = []
                return
            }
            struct MeResp: Decodable {
                let ok: Bool
                let user: PipiAccountUser?
                let devices: [PipiAccountDevice]?
            }
            let decoded = try JSONDecoder().decode(MeResp.self, from: data)
            self.currentUser = decoded.user
            self.devices = decoded.devices ?? []
        } catch {
            // Keep cached state on transient network drop
        }
    }

    public func registerCurrentHost(
        name: String,
        hostId: String,
        hostPubKey: String,
        capabilities: [String],
        workspacePath: String
    ) async {
        guard let token = accessToken, !token.isEmpty,
              let url = URL(string: "\(relayOrigin)/api/devices/register") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": name,
            "platform": "macos",
            "hostId": hostId,
            "hostPubKey": hostPubKey,
            "capabilities": capabilities,
            "workspacePath": workspacePath
        ])
        _ = try? await session.data(for: req)
        await refreshProfile()
    }

    public func removeDevice(id: String) async {
        guard let token = accessToken, !token.isEmpty,
              let url = URL(string: "\(relayOrigin)/api/devices/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: req)
        await refreshProfile()
    }

    /// Verifies that an incoming E2EE peer's session token belongs to the SAME signed-in PiPiBot user.
    /// Cached in memory so mobile/web browsers signed into the same account connect with zero QR re-pairing.
    public func verifyPeerAccountToken(_ peerToken: String) async -> Bool {
        let trimmed = peerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let ownUserId = currentUser?.id else { return false }
        if trimmed == accessToken || verifiedPeerTokens.contains(trimmed) {
            return true
        }
        guard let url = URL(string: "\(relayOrigin)/api/auth/me") else { return false }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return false
            }
            struct MeCheck: Decodable {
                let ok: Bool
                let user: PipiAccountUser?
            }
            let decoded = try JSONDecoder().decode(MeCheck.self, from: data)
            if decoded.ok, decoded.user?.id == ownUserId {
                verifiedPeerTokens.insert(trimmed)
                return true
            }
            return false
        } catch {
            return false
        }
    }

    public func logout() async {
        pollTask?.cancel()
        pollTask = nil
        pendingBrowserUserCode = nil
        if let token = accessToken, !token.isEmpty,
           let url = URL(string: "\(relayOrigin)/api/auth/logout") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: req)
        }
        secretStore.deleteSecret(for: Self.tokenSecretKey)
        currentUser = nil
        devices = []
        statusMessage = nil
    }
}
