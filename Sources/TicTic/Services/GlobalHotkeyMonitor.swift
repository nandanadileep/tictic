import AppKit
import Foundation

final class GlobalHotkeyMonitor {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hotkey: HotkeyChoice

    init(hotkey: HotkeyChoice) {
        self.hotkey = hotkey
    }

    func update(_ hotkey: HotkeyChoice) {
        self.hotkey = hotkey
    }

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
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
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == hotkey.keyCode else { return }
        let relevant: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        guard event.flags.intersection(relevant) == hotkey.eventFlags else { return }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        DispatchQueue.main.async { [weak self] in
            if type == .keyDown { self?.onKeyDown?() }
            if type == .keyUp { self?.onKeyUp?() }
        }
    }
}
