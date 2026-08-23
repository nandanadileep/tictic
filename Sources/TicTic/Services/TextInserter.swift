import AppKit
import ApplicationServices
import Foundation

struct TextDestination {
    let processIdentifier: pid_t
    let applicationName: String
    let bundleIdentifier: String?
}

enum TextInserter {
    static func captureDestination() -> TextDestination? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return TextDestination(
            processIdentifier: app.processIdentifier,
            applicationName: app.localizedName ?? "Unknown app",
            bundleIdentifier: app.bundleIdentifier
        )
    }

    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static func insert(_ text: String, destination: TextDestination?) -> Bool {
        if let destination,
           let app = NSRunningApplication(processIdentifier: destination.processIdentifier),
           !app.isTerminated {
            app.activate()
        }

        if isAccessibilityTrusted(), setFocusedSelection(text, destination: destination) {
            return true
        }
        return pasteWithClipboard(text)
    }

    private static func setFocusedSelection(_ text: String, destination: TextDestination?) -> Bool {
        let application: AXUIElement
        if let destination {
            application = AXUIElementCreateApplication(destination.processIdentifier)
        } else {
            application = AXUIElementCreateSystemWide()
        }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return false }
        let element = focused as! AXUIElement
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
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
