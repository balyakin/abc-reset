import AppKit
import Carbon
import Foundation

enum SystemCheckError: LocalizedError {
    case appAlreadyRunning
    case sourceUnavailable
    case checkFailed(String)

    var errorDescription: String? {
        switch self {
        case .appAlreadyRunning:
            return "Quit ABC Reset before running the live test"
        case .sourceUnavailable:
            return "Enable ABC and Russian before running the system checks"
        case .checkFailed(let message):
            return message
        }
    }
}

enum SystemIntegrationChecks {
    static func checkNativeAPIs() throws {
        // ARRANGE
        let keyboardState = KeyboardState()
        let inputSources = InputSources()
        // ACT
        let idleTime = keyboardState.idleTime
        let currentIdentifier = try inputSources.getCurrentIdentifier()
        let abcSource = try inputSources.findABC()
        guard let identifierPointer = TISGetInputSourceProperty(abcSource, kTISPropertyInputSourceID) else {
            throw SystemCheckError.sourceUnavailable
        }
        let abcIdentifier = Unmanaged<CFString>.fromOpaque(identifierPointer).takeUnretainedValue() as String
        // ASSERT
        try require(idleTime.isFinite && idleTime >= 0, "Keyboard idle time must be finite and non-negative")
        try require(!currentIdentifier.isEmpty, "Current source identifier must not be empty")
        try require(abcIdentifier == "com.apple.keylayout.ABC", "Must resolve exactly ABC")
    }

    static func checkRunningApp(executablePath: String) throws {
        // ARRANGE
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.ksw.ABCReset")
        guard runningApps.isEmpty else {
            throw SystemCheckError.appAlreadyRunning
        }
        guard let originalSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            throw SystemCheckError.sourceUnavailable
        }
        let russianSource = try findRussian()
        let inputSources = InputSources()
        let application = Process()
        application.executableURL = URL(fileURLWithPath: executablePath)
        application.standardOutput = FileHandle.nullDevice
        application.standardError = FileHandle.nullDevice
        defer {
            if application.isRunning {
                application.terminate()
                application.waitUntilExit()
            }
            let restoreStatus = TISSelectInputSource(originalSource)
            precondition(restoreStatus == noErr, "Must restore the initial input source")
        }
        // ACT
        try inputSources.selectABC(when: { true })
        try application.run()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        try require(application.isRunning, "Application must remain running after launch")
        let selectionStatus = TISSelectInputSource(russianSource)
        try require(selectionStatus == noErr, "Must be able to select Russian for this live test")
        let initialIdentifier = try inputSources.getCurrentIdentifier()
        try require(initialIdentifier == "com.apple.keylayout.Russian", "Russian must be active before the test")
        let startTime = ProcessInfo.processInfo.systemUptime
        let rejectedSelection = try inputSources.selectABC(when: { false })
        try require(!rejectedSelection, "A rejected last-moment activity check must prevent selection")
        let timeout: TimeInterval = 12
        let pollingInterval: TimeInterval = 0.1
        while try inputSources.getCurrentIdentifier() != "com.apple.keylayout.ABC"
            && ProcessInfo.processInfo.systemUptime - startTime < timeout {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: pollingInterval))
        }
        let elapsedTime = ProcessInfo.processInfo.systemUptime - startTime
        let finalIdentifier = try inputSources.getCurrentIdentifier()
        // ASSERT
        try require(application.isRunning, "Application must remain running after resetting")
        try require(finalIdentifier == "com.apple.keylayout.ABC", "Running app must switch Russian to ABC")
        try require(elapsedTime >= 4.9, "Application must wait five seconds after a manual source change")
        try require(elapsedTime < timeout, "Application must reset before the live-test timeout")
        let message = "PASS: running app switched Russian to ABC after \(elapsedTime) seconds\n"
        FileHandle.standardOutput.write(Data(message.utf8))
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw SystemCheckError.checkFailed(message)
        }
    }

    private static func findRussian() throws -> TISInputSource {
        let properties = [kTISPropertyInputSourceID as String: "com.apple.keylayout.Russian"]
        guard let sourceList = TISCreateInputSourceList(properties as CFDictionary, false)?.takeRetainedValue(),
              let sources = sourceList as? [TISInputSource],
              let source = sources.first else {
            throw SystemCheckError.sourceUnavailable
        }
        return source
    }
}
