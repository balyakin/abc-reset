import AppKit
import Carbon
import Foundation
import os

private enum AppSettings {
    static let bundleIdentifier: String = "local.ksw.ABCReset"
    static let pollingInterval: TimeInterval = 0.25
    static let timerTolerance: TimeInterval = 0.05
    static let retryInterval: TimeInterval = 5
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: AppSettings.bundleIdentifier, category: "InputSource")
    private let inputSources = InputSources()
    private let keyboardState = KeyboardState()
    private let stateItem = NSMenuItem(
        title: "ABC после 5 секунд без клавиатуры", action: nil, keyEquivalent: ""
    )
    private let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "Приостановить", action: nil, keyEquivalent: "")
    private var policy = ResetPolicy(startTime: ProcessInfo.processInfo.systemUptime)
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var nextAttemptTime: TimeInterval = 0
    private var isSessionActive: Bool = true
    private var isSleeping: Bool = false
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        observeLifecycle()
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Возврат на ABC после пяти секунд без клавиатуры"
        )
        startTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if let activity = activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    private func createMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        stateItem.isEnabled = false
        errorItem.isEnabled = false
        errorItem.isHidden = true
        pauseItem.target = self
        pauseItem.action = #selector(togglePause)

        let settingsItem = NSMenuItem(
            title: "Настройки клавиатуры…",
            action: #selector(openKeyboardSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self

        let quitItem = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        [stateItem, errorItem, .separator(), pauseItem, settingsItem, .separator(), quitItem].forEach(menu.addItem)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.menu = menu
        updateStatus()
    }

    private func startTimer() {
        let pollingTimer = Timer(timeInterval: AppSettings.pollingInterval, repeats: true) { [weak self] _ in
            self?.checkKeyboard()
        }
        pollingTimer.tolerance = AppSettings.timerTolerance
        RunLoop.main.add(pollingTimer, forMode: .common)
        timer = pollingTimer
    }

    private func observeLifecycle() {
        let sourceCenter = DistributedNotificationCenter.default()
        let sourceNotifications = [
            Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
        ]
        for sourceNotification in sourceNotifications {
            sourceCenter.addObserver(
                self,
                selector: #selector(handleSourceChange),
                name: sourceNotification,
                object: nil
            )
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleSessionInactive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(handleSessionActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    private func shouldReset() -> Bool {
        guard policy.isEnabled, isSessionActive, !isSleeping else {
            return false
        }

        return policy.shouldReset(
            at: ProcessInfo.processInfo.systemUptime,
            keyboardIdleTime: keyboardState.idleTime,
            hasPressedKeys: keyboardState.hasPressedKeys
        )
    }

    private func checkKeyboard() {
        guard policy.isEnabled, isSessionActive, !isSleeping,
              ProcessInfo.processInfo.systemUptime >= nextAttemptTime else {
            return
        }

        do {
            let currentIdentifier = try observeCurrentSource()
            guard currentIdentifier != InputSources.abcIdentifier else {
                clearError()
                return
            }
            guard shouldReset() else {
                return
            }
            let didSelect = try inputSources.selectABC {
                try self.observeCurrentSource()
                return self.shouldReset()
            }
            if didSelect {
                policy.observeSource(InputSources.abcIdentifier, at: ProcessInfo.processInfo.systemUptime)
                logger.info("Выбран источник ввода \(InputSources.abcIdentifier, privacy: .public)")
            }
            clearError()
        } catch {
            showError(error)
        }
    }

    @discardableResult
    private func observeCurrentSource() throws -> String {
        let identifier = try inputSources.getCurrentIdentifier()
        policy.observeSource(identifier, at: ProcessInfo.processInfo.systemUptime)
        return identifier
    }

    private func showError(_ error: Error) {
        let message = error.localizedDescription
        if lastError != message {
            logger.error(
                "Источник \(InputSources.abcIdentifier, privacy: .public): \(message, privacy: .public)"
            )
        }
        lastError = message
        nextAttemptTime = ProcessInfo.processInfo.systemUptime + AppSettings.retryInterval
        errorItem.title = message
        errorItem.isHidden = false
        updateStatus()
    }

    private func clearError() {
        guard lastError != nil else {
            return
        }
        lastError = nil
        errorItem.isHidden = true
        updateStatus()
    }

    private func updateStatus() {
        let stateTitle = policy.isEnabled ? "ABC↺" : "ABCⅡ"
        statusItem?.button?.title = lastError == nil ? stateTitle : "ABC!"
        let tooltip = "ABC Reset: возврат на ABC через 5 секунд без клавиатуры"
        statusItem?.button?.toolTip = lastError ?? tooltip
        statusItem?.button?.setAccessibilityLabel("ABC Reset")
        pauseItem.title = policy.isEnabled ? "Приостановить" : "Возобновить"
        stateItem.title = policy.isEnabled
            ? "ABC после 5 секунд без клавиатуры"
            : "Автосброс приостановлен"
    }

    private func restartGracePeriod() {
        policy.restart(at: ProcessInfo.processInfo.systemUptime)
        nextAttemptTime = 0
    }

    @objc private func togglePause() {
        policy.setEnabled(!policy.isEnabled, at: ProcessInfo.processInfo.systemUptime)
        clearError()
        updateStatus()
    }

    @objc private func openKeyboardSettings() {
        let settingsAddress: String
        if #available(macOS 13, *) {
            settingsAddress = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        } else {
            settingsAddress = "x-apple.systempreferences:com.apple.preference.keyboard?InputSources"
        }
        if let settingsURL = URL(string: settingsAddress) {
            NSWorkspace.shared.open(settingsURL)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleSourceChange(_ notification: Notification) {
        restartGracePeriod()
    }

    @objc private func handleSleep(_ notification: Notification) {
        isSleeping = true
    }

    @objc private func handleWake(_ notification: Notification) {
        isSleeping = false
        restartGracePeriod()
    }

    @objc private func handleSessionInactive(_ notification: Notification) {
        isSessionActive = false
    }

    @objc private func handleSessionActive(_ notification: Notification) {
        isSessionActive = true
        restartGracePeriod()
    }
}

@main
enum ABCResetApplication {
    static func main() {
        let application = NSApplication.shared
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: AppSettings.bundleIdentifier)
        guard runningApps.count <= 1 else {
            return
        }

        let delegate = ApplicationDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
