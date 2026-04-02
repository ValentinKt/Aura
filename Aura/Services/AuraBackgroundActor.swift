import Foundation

@globalActor
public struct AuraBackgroundActor {
    public actor ActorType {
        private var renderingSuspended = false
        private var suspensionWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

        func setRenderingSuspended(_ suspended: Bool) {
            guard renderingSuspended != suspended else { return }
            renderingSuspended = suspended

            guard !suspended else { return }
            let waiters = suspensionWaiters.values
            suspensionWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        func waitUntilRenderingActive() async {
            guard renderingSuspended else { return }

            let id = UUID()
            await withCheckedContinuation { continuation in
                suspensionWaiters[id] = continuation
            }
        }

        func isRenderingSuspended() -> Bool {
            renderingSuspended
        }
    }
    public static let shared = ActorType()

    @AuraBackgroundActor
    public static func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    public static func setRenderingSuspended(_ suspended: Bool) async {
        await shared.setRenderingSuspended(suspended)
    }

    public static func waitUntilRenderingActive() async {
        await shared.waitUntilRenderingActive()
    }

    public static func throwIfRenderingSuspended() async throws {
        if await shared.isRenderingSuspended() {
            throw CancellationError()
        }
    }
}
