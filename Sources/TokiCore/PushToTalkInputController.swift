import Foundation

public enum PushToTalkSource: String, Equatable, Sendable {
    case keyboard
    case mouse
}

public enum PushToTalkInputEvent: Equatable, Sendable {
    case pressed(PushToTalkSource)
    case released
}

public protocol PushToTalkInputControlling: AnyObject, Sendable {
    var onEvent: (@Sendable (PushToTalkInputEvent) -> Void)? { get set }
    func press(source: PushToTalkSource)
    func release()
}

public final class PushToTalkInputController: PushToTalkInputControlling, @unchecked Sendable {
    public var onEvent: (@Sendable (PushToTalkInputEvent) -> Void)?

    public init() {}

    public func press(source: PushToTalkSource) {
        onEvent?(.pressed(source))
    }

    public func release() {
        onEvent?(.released)
    }
}
