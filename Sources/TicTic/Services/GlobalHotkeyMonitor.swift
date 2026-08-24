import AppKit
import Carbon
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
    private var registeredHotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
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
        if !hotkey.isModifierOnly { return startRegisteredHotKey() }

        return startModifierMonitor()
    }

    private func startModifierMonitor() -> Bool {
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

    private func startRegisteredHotKey() -> Bool {
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<GlobalHotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                let kind = GetEventKind(event)
                DispatchQueue.main.async { [weak monitor] in
                    if kind == UInt32(kEventHotKeyPressed) { monitor?.onKeyDown?() }
                    if kind == UInt32(kEventHotKeyReleased) { monitor?.onKeyUp?() }
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            pointer,
            &hotKeyHandler
        )
        guard handlerStatus == noErr else { return false }

        let identifier = EventHotKeyID(signature: 0x54695463, id: 1) // "TiTc"
        let registrationStatus = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonModifiers,
            identifier,
            GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive),
            &registeredHotKey
        )
        guard registrationStatus == noErr else {
            if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
            hotKeyHandler = nil
            return false
        }
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let registeredHotKey { UnregisterEventHotKey(registeredHotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        source = nil
        eventTap = nil
        registeredHotKey = nil
        hotKeyHandler = nil
        modifierTracker = ModifierChordTracker(requiredKeyCodes: hotkey.modifierKeyCodes)
    }

    private var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if hotkey.eventFlags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if hotkey.eventFlags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        if hotkey.eventFlags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if hotkey.eventFlags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        return modifiers
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
