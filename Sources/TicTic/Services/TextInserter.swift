import AppKit
import ApplicationServices
import Foundation
import OSLog

struct TextDestination {
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
    let focusedElement: AXUIElement?
}

enum TextInserter {
    private static let logger = Logger(subsystem: "com.nandanadileep.tictic", category: "insertion")

    static func captureDestination() -> TextDestination? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        let focusedElement: AXUIElement?
        if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused {
            focusedElement = (focused as! AXUIElement)
        } else {
            focusedElement = nil
        }
        return TextDestination(
            processIdentifier: app.processIdentifier,
            applicationName: app.localizedName ?? "Unknown app",
            bundleIdentifier: app.bundleIdentifier,
            focusedElement: focusedElement
        )
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func insert(_ text: String, destination: TextDestination?) async -> Bool {
        guard isAccessibilityTrusted() else {
            Self.logger.error("Paste blocked because Accessibility is not authorized")
            return false
        }

        if let destination {
            guard let app = NSRunningApplication(processIdentifier: destination.processIdentifier),
                  !app.isTerminated else {
                Self.logger.error("Destination application is no longer running")
                return false
            }
            app.activate()
            for _ in 0..<16 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier {
                    break
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else {
                Self.logger.error("Could not activate destination \(destination.applicationName, privacy: .public)")
                return false
            }

            // Restore the exact control that was focused when dictation began, then
            // use a real paste. Content-editable and Electron fields often report a
            // successful AXSelectedText write without changing their visible text.
            if let focusedElement = destination.focusedElement {
                _ = AXUIElementSetAttributeValue(
                    focusedElement,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        guard pasteWithClipboard(text) else {
            Self.logger.error("Could not synthesize Command-V")
            return false
        }
        if let destination {
            Self.logger.info("Dispatched paste to \(destination.applicationName, privacy: .public)")
        }
        return true
    }

    private static func pasteWithClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let oldItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { values[type] = data }
            }
            return values.isEmpty ? nil : values
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        if let oldItems {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                pasteboard.clearContents()
                let restored = oldItems.map { values -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                pasteboard.writeObjects(restored)
            }
        }
        return true
    }
}
