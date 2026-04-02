import Foundation

@globalActor
public struct AuraBackgroundActor {
    public actor ActorType { }
    public static let shared = ActorType()
}