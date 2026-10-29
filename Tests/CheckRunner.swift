import Foundation

@main
enum CheckRunner {
    static func main() {
        do {
            try runChecks()
        } catch {
            let message = "FAIL: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func runChecks() throws {
        let checks: [() -> Void] = [
            ResetPolicyChecks.checkStartupGrace,
            ResetPolicyChecks.checkExactThreshold,
            ResetPolicyChecks.checkTyping,
            ResetPolicyChecks.checkHeldKey,
            ResetPolicyChecks.checkKeyRelease,
            ResetPolicyChecks.checkManualLayoutChange,
            ResetPolicyChecks.checkPause,
            ResetPolicyChecks.checkResume,
            ResetPolicyChecks.checkNegativeIdleTime,
            ResetPolicyChecks.checkNonFiniteIdleTimes,
            ResetPolicyChecks.checkRepeatedRestart,
            ResetPolicyChecks.checkLazyKeyStateRead,
            ResetPolicyChecks.checkSourceChangeWithoutNotification,
            ResetPolicyChecks.checkUnchangedSourceKeepsDeadline
        ]
        checks.forEach { check in check() }
        FileHandle.standardOutput.write(Data("PASS: \(checks.count) policy checks\n".utf8))

        if ProcessInfo.processInfo.environment["KSW_RUN_SYSTEM_TESTS"] == "1" {
            try SystemIntegrationChecks.checkNativeAPIs()
            FileHandle.standardOutput.write(Data("PASS: native keyboard and input source APIs\n".utf8))
        }

        if let executablePath = ProcessInfo.processInfo.environment["KSW_LIVE_APP_PATH"] {
            try SystemIntegrationChecks.checkRunningApp(executablePath: executablePath)
        }
    }
}
