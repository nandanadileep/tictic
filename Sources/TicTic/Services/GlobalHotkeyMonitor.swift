import AppKit
import Foundation

struct ModifierChordTracker {
    let requiredKeyCodes: Set<CGKeyCode>
    private(set) var pressedKeyCodes: Set<CGKeyCode> = []
    private(set) var isActive = false

    mutating func update(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool? {
        guard requiredKeyCodes.contains(keyCode) else { return nil }
        let flag: CGEventFlags = keyCode == 59 ? .maskControl : keyCode == 56 ? .maskShift : .maskAlternate
        if flags.contains(flag) {
            pressedKeyCodes.insert(keyCode)
        } else {
            pressedKeyCodes.remove(keyCode)
        }

        let nextIsActive = requiredKeyCodes.isSubset(of: pressedKeyCodes)
        guard nextIsActive != isActive else { return nil }
        isActive = nextIsActive
        return nextIsActive
    }
}

final class GlobalHotkeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotkey: HotkeyChoice
    private var modifierTracker: ModifierChordTracker

    init(hotkey: HotkeyChoice) {
        self.hotkey = hotkey
        modifierTracker = ModifierChordTracker(requiredKeyCodes: hotkey.modifierKeyCodes)
    }

    func update(_ hotkey: HotkeyChoice) {
        self.hotkey = hotkey
        modifierTracker = ModifierChordTracker(requiredKeyCodes: hotkey.modifierKeyCodes)
    }

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else { return false }

        eventTap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        source = nil
        eventTap = nil
        modifierTracker = ModifierChordTracker(requiredKeyCodes: hotkey.modifierKeyCodes)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

        if hotkey.isModifierOnly {
            guard type == .flagsChanged else { return }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard let isPressed = modifierTracker.update(keyCode: keyCode, flags: event.flags) else { return }
            DispatchQueue.main.async { [weak self] in
                if isPressed { self?.onKeyDown?() } else { self?.onKeyUp?() }
            }
            return
        }

        guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == hotkey.keyCode else { return }
        guard event.flags.intersection(relevant) == hotkey.eventFlags else { return }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        DispatchQueue.main.async { [weak self] in
            if type == .keyDown { self?.onKeyDown?() }
            if type == .keyUp { self?.onKeyUp?() }
        }
    }
}
