import Foundation

enum ResetPolicyChecks {
    static func checkStartupGrace() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        // ACT
        let result = policy.shouldReset(at: 104.99, keyboardIdleTime: 30, hasPressedKeys: false)
        // ASSERT
        precondition(!result, "Must wait five seconds after startup")
    }

    static func checkExactThreshold() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        // ACT
        let result = policy.shouldReset(at: 105, keyboardIdleTime: 5, hasPressedKeys: false)
        // ASSERT
        precondition(result, "Must reset at exactly five seconds")
    }

    static func checkTyping() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        // ACT
        let result = policy.shouldReset(at: 200, keyboardIdleTime: 4.99, hasPressedKeys: false)
        // ASSERT
        precondition(!result, "Must not reset during typing")
    }

    static func checkHeldKey() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        // ACT
        let result = policy.shouldReset(at: 200, keyboardIdleTime: 30, hasPressedKeys: true)
        // ASSERT
        precondition(!result, "Must not reset while a key is held")
    }

    static func checkKeyRelease() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        // ACT
        let result = policy.shouldReset(at: 200, keyboardIdleTime: 0, hasPressedKeys: false)
        // ASSERT
        precondition(!result, "Key release must restart keyboard idle time")
    }

    static func checkManualLayoutChange() {
        // ARRANGE
        var policy = ResetPolicy(startTime: 100)
        policy.restart(at: 200)
        // ACT
        let beforeDeadline = policy.shouldReset(at: 204.99, keyboardIdleTime: 30, hasPressedKeys: false)
        let atDeadline = policy.shouldReset(at: 205, keyboardIdleTime: 30, hasPressedKeys: false)
        // ASSERT
        precondition(!beforeDeadline, "Manual source change must grant a fresh five seconds")
        precondition(atDeadline, "Must reset five seconds after a manual change")
    }

    static func checkPause() {
        // ARRANGE
        var policy = ResetPolicy(startTime: 100)
        policy.setEnabled(false, at: 200)
        // ACT
        let result = policy.shouldReset(at: 300, keyboardIdleTime: 30, hasPressedKeys: false)
        // ASSERT
        precondition(!result, "Pause must prevent resetting")
        precondition(!policy.isEnabled, "Policy must expose its paused state")
    }

    static func checkResume() {
        // ARRANGE
        var policy = ResetPolicy(startTime: 100)
        policy.setEnabled(false, at: 200)
        policy.setEnabled(true, at: 300)
        // ACT
        let beforeDeadline = policy.shouldReset(at: 304.99, keyboardIdleTime: 30, hasPressedKeys: false)
        let atDeadline = policy.shouldReset(at: 305, keyboardIdleTime: 30, hasPressedKeys: false)
        // ASSERT
        precondition(!beforeDeadline, "Resume must grant a fresh five seconds")
        precondition(atDeadline, "Must reset five seconds after resuming")
        precondition(policy.isEnabled, "Policy must expose its enabled state")
    }

    static func checkNegativeIdleTime() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        // ACT
        let result = policy.shouldReset(at: 200, keyboardIdleTime: -1, hasPressedKeys: false)
        // ASSERT
        precondition(!result, "Invalid negative idle time must not reset")
    }

    static func checkNonFiniteIdleTimes() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        let idleTimes: [TimeInterval] = [.nan, .infinity, -.infinity]
        // ACT
        let results = idleTimes.map { idleTime in
            policy.shouldReset(at: 200, keyboardIdleTime: idleTime, hasPressedKeys: false)
        }
        // ASSERT
        precondition(results == [false, false, false], "Non-finite idle time must not reset")
    }

    static func checkRepeatedRestart() {
        // ARRANGE
        var policy = ResetPolicy(startTime: 100)
        policy.restart(at: 200)
        policy.restart(at: 203)
        // ACT
        let beforeDeadline = policy.shouldReset(at: 207.99, keyboardIdleTime: 30, hasPressedKeys: false)
        let atDeadline = policy.shouldReset(at: 208, keyboardIdleTime: 30, hasPressedKeys: false)
        // ASSERT
        precondition(!beforeDeadline, "Latest source change must replace the previous deadline")
        precondition(atDeadline, "Must reset after the latest deadline")
    }

    static func checkLazyKeyStateRead() {
        // ARRANGE
        let policy = ResetPolicy(startTime: 100)
        var readCount: Int = 0
        let readPressedKeys: () -> Bool = {
            readCount += 1
            return false
        }
        // ACT
        let duringGrace = policy.shouldReset(at: 104, keyboardIdleTime: 30, hasPressedKeys: readPressedKeys())
        let duringTyping = policy.shouldReset(at: 105, keyboardIdleTime: 4.99, hasPressedKeys: readPressedKeys())
        let earlyReadCount = readCount
        let afterIdle = policy.shouldReset(at: 105, keyboardIdleTime: 5, hasPressedKeys: readPressedKeys())
        // ASSERT
        precondition(!duringGrace && !duringTyping, "Must not reset before both timing conditions are met")
        precondition(earlyReadCount == 0, "Must not query held keys during grace or typing")
        precondition(afterIdle && readCount == 1, "Must query held keys once when eligible to reset")
    }

    static func checkSourceChangeWithoutNotification() {
        // ARRANGE
        var policy = ResetPolicy(startTime: 100)
        policy.observeSource("com.apple.keylayout.ABC", at: 100)
        // ACT
        policy.observeSource("com.apple.keylayout.Russian", at: 200)
        let beforeDeadline = policy.shouldReset(at: 204.99, keyboardIdleTime: 30, hasPressedKeys: false)
        let atDeadline = policy.shouldReset(at: 205, keyboardIdleTime: 30, hasPressedKeys: false)
        // ASSERT
        precondition(!beforeDeadline, "Polling must detect source changes before asynchronous notifications")
        precondition(atDeadline, "Polling must grant five seconds to a newly observed source")
    }

    static func checkUnchangedSourceKeepsDeadline() {
        // ARRANGE
        var policy = ResetPolicy(startTime: 100)
        policy.observeSource("com.apple.keylayout.Russian", at: 101)
        // ACT
        policy.observeSource("com.apple.keylayout.Russian", at: 104)
        let result = policy.shouldReset(at: 105, keyboardIdleTime: 5, hasPressedKeys: false)
        // ASSERT
        precondition(result, "Initial and repeated source observations must preserve the current deadline")
    }
}
