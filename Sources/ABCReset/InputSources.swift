import Carbon
import Foundation

enum InputSourceError: LocalizedError {
    case currentSourceUnavailable
    case abcUnavailable
    case selectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .currentSourceUnavailable:
            return "Не удалось прочитать текущую раскладку"
        case .abcUnavailable:
            return "Добавь ABC в источники ввода в настройках клавиатуры"
        case .selectionFailed(let status):
            return "Не удалось переключить на ABC (код \(status))"
        }
    }
}

struct InputSources {
    static let abcIdentifier: String = "com.apple.keylayout.ABC"

    func getCurrentIdentifier() throws -> String {
        guard let currentSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let identifierPointer = TISGetInputSourceProperty(currentSource, kTISPropertyInputSourceID) else {
            throw InputSourceError.currentSourceUnavailable
        }

        let identifier = Unmanaged<CFString>.fromOpaque(identifierPointer).takeUnretainedValue()
        return identifier as String
    }

    @discardableResult
    func selectABC(when shouldSelect: () throws -> Bool) throws -> Bool {
        let currentIdentifier = try getCurrentIdentifier()
        guard currentIdentifier != Self.abcIdentifier else {
            return false
        }

        let targetSource = try findABC()
        guard try getCurrentIdentifier() == currentIdentifier, try shouldSelect() else {
            return false
        }

        let status = TISSelectInputSource(targetSource)
        guard status == noErr else {
            throw InputSourceError.selectionFailed(status)
        }

        return true
    }

    func findABC() throws -> TISInputSource {
        let properties: [String: Any] = [
            kTISPropertyInputSourceID as String: Self.abcIdentifier,
            kTISPropertyInputSourceIsSelectCapable as String: true
        ]

        guard let sourceList = TISCreateInputSourceList(properties as CFDictionary, false)?.takeRetainedValue(),
              let sources = sourceList as? [TISInputSource],
              let targetSource = sources.first else {
            throw InputSourceError.abcUnavailable
        }

        return targetSource
    }
}
