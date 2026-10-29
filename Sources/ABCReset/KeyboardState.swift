import Carbon
import CoreGraphics
import Foundation

struct KeyboardState {
    private static let lastKeyCode: CGKeyCode = 127
    private static let firstKeyCode: CGKeyCode = 0
    private static let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]

    var idleTime: TimeInterval {
        Self.eventTypes.map { eventType in
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: eventType)
        }.min() ?? 0
    }

    var hasPressedKeys: Bool {
        (Self.firstKeyCode...Self.lastKeyCode).contains { keyCode in
            keyCode != CGKeyCode(kVK_CapsLock)
                && CGEventSource.keyState(.combinedSessionState, key: keyCode)
        }
    }
}
