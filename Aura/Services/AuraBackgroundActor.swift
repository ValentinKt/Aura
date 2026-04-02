import Foundation

@globalActor
public struct AuraBackgroundActor {
    public actor ActorType { }
    public static let shared = ActorType()

    @AuraBackgroundActor
    public static func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
