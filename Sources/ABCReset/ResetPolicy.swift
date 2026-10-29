import Foundation

struct ResetPolicy {
    static let idleThreshold: TimeInterval = 5

    private(set) var isEnabled: Bool = true
    private var eligibilityTime: TimeInterval
    private var observedSourceIdentifier: String?

    init(startTime: TimeInterval) {
        eligibilityTime = startTime + Self.idleThreshold
    }

    mutating func restart(at time: TimeInterval) {
        eligibilityTime = time + Self.idleThreshold
    }

    mutating func setEnabled(_ enabled: Bool, at time: TimeInterval) {
        isEnabled = enabled
        restart(at: time)
    }

    mutating func observeSource(_ identifier: String, at time: TimeInterval) {
        let didChange = observedSourceIdentifier != nil && observedSourceIdentifier != identifier
        observedSourceIdentifier = identifier
        if didChange {
            restart(at: time)
        }
    }

    func shouldReset(
        at time: TimeInterval,
        keyboardIdleTime: TimeInterval,
        hasPressedKeys: @autoclosure () -> Bool
    ) -> Bool {
        isEnabled
            && time >= eligibilityTime
            && keyboardIdleTime.isFinite
            && keyboardIdleTime >= Self.idleThreshold
            && !hasPressedKeys()
    }
}
