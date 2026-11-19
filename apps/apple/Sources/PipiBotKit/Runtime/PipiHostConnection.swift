import Foundation

public enum PipiHostConnectionError: LocalizedError, Sendable {
    case hostUnavailable
    case sessionNotFound(String)
    case approvalNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .hostUnavailable:
            return "Local host runtime is unavailable."
        case .sessionNotFound(let id):
            return "Session not found: \(id)"
        case .approvalNotFound(let id):
            return "Approval not found: \(id)"
        }
    }
}

/// Client-facing host protocol v2 per blueprint §5.
/// UI and store route session lifecycle operations through this seam.
public protocol PipiHostConnection: AnyObject, Sendable {
    var host: PipiHostDescriptor { get }
    func listBots() async throws -> [PipiBotPersona]
    func listSessions(since: Date?) async throws -> [PipiSessionSummary]
    func events(sessionId: String, afterSeq: Int) -> AsyncThrowingStream<PipiSessionEvent, Error>
    func send(sessionId: String?, botId: String, input: PipiUserInput) async throws -> String
    func stop(sessionId: String) async throws
    func resolveApproval(_ id: String, optionId: String, note: String?) async throws
}

/// In-process local Mac host implementation of `PipiHostConnection`.
public final class PipiLocalHostConnection: PipiHostConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var _host: PipiHostDescriptor
    private weak var store: PipiAppStore?
    private var subscribers: [String: [UUID: AsyncThrowingStream<PipiSessionEvent, Error>.Continuation]] = [:]

    public init(host: PipiHostDescriptor = .local(), store: PipiAppStore? = nil) {
        self._host = host
        self.store = store
    }

    public func attach(store: PipiAppStore) {
        lock.lock()
        self.store = store
        lock.unlock()
    }

    public func updateHost(_ descriptor: PipiHostDescriptor) {
        lock.lock()
        self._host = descriptor
        lock.unlock()
    }

    public var host: PipiHostDescriptor {
        lock.lock()
        defer { lock.unlock() }
        return _host
    }

    public func listBots() async throws -> [PipiBotPersona] {
        guard let store = currentStore() else { throw PipiHostConnectionError.hostUnavailable }
        return await MainActor.run {
            store.personas.filter { $0.hostId == host.id || $0.hostId.isEmpty }
        }
    }

    public func listSessions(since: Date?) async throws -> [PipiSessionSummary] {
        guard let store = currentStore() else { throw PipiHostConnectionError.hostUnavailable }
        return await MainActor.run {
            let iso = ISO8601DateFormatter()
            return store.conversations.compactMap { conv -> PipiSessionSummary? in
                if let since, let updated = iso.date(from: conv.updatedAt), updated < since {
                    return nil
                }
                return PipiSessionSummary(
                    id: conv.id,
                    hostId: conv.hostId,
                    botId: conv.personaId,
                    projectId: conv.projectId,
                    title: conv.title,
                    state: conv.state,
                    engineLabel: conv.lastEngineLabel,
                    updatedAt: conv.updatedAt,
                    lastEventSeq: conv.events.last?.seq ?? 0
                )
            }
        }
    }

    public func events(sessionId: String, afterSeq: Int) -> AsyncThrowingStream<PipiSessionEvent, Error> {
        let token = UUID()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.removeSubscriber(sessionId: sessionId, token: token)
            }

            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                if let store = self.currentStore() {
                    let backlog = await MainActor.run {
                        store.conversations
                            .first(where: { $0.id == sessionId })?
                            .events
                            .filter { $0.seq > afterSeq } ?? []
                    }
                    for evt in backlog {
                        continuation.yield(evt)
                    }
                }
                self.addSubscriber(sessionId: sessionId, token: token, continuation: continuation)
            }
        }
    }

    public func send(sessionId: String?, botId: String, input: PipiUserInput) async throws -> String {
        guard let store = currentStore() else { throw PipiHostConnectionError.hostUnavailable }
        return await MainActor.run {
            store.performLocalHostSend(sessionId: sessionId, botId: botId, input: input)
        }
    }

    public func stop(sessionId: String) async throws {
        guard let store = currentStore() else { throw PipiHostConnectionError.hostUnavailable }
        await MainActor.run {
            store.performLocalHostStop(sessionId: sessionId)
        }
    }

    @MainActor
    public func stopImmediate(sessionId: String) {
        guard let store = currentStore() else { return }
        store.performLocalHostStop(sessionId: sessionId)
    }

    public func resolveApproval(_ id: String, optionId: String, note: String? = nil) async throws {
        guard let store = currentStore() else { throw PipiHostConnectionError.hostUnavailable }
        let resumedTask = await MainActor.run {
            store.performLocalHostResolveApproval(id, optionId: optionId, note: note)
        }
        await resumedTask?.value
    }

    public func publishEvent(_ event: PipiSessionEvent) {
        lock.lock()
        let active = subscribers[event.sessionId]?.values.map { $0 } ?? []
        lock.unlock()
        for continuation in active {
            continuation.yield(event)
        }
    }

    private func currentStore() -> PipiAppStore? {
        lock.lock()
        defer { lock.unlock() }
        return store
    }

    private func addSubscriber(
        sessionId: String,
        token: UUID,
        continuation: AsyncThrowingStream<PipiSessionEvent, Error>.Continuation
    ) {
        lock.lock()
        subscribers[sessionId, default: [:]][token] = continuation
        lock.unlock()
    }

    private func removeSubscriber(sessionId: String, token: UUID) {
        lock.lock()
        subscribers[sessionId]?.removeValue(forKey: token)
        if subscribers[sessionId]?.isEmpty == true {
            subscribers.removeValue(forKey: sessionId)
        }
        lock.unlock()
    }
}
