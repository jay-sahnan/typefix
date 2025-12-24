//
//  KeyMonitor.swift
//  TypeFixPrototype
//
//  Monitors keyboard input system-wide using CGEvent taps. Tracks word
//  boundaries and character input to detect when words are completed,
//  enabling the correction engine to process text in real-time.
//
//  This class requires Accessibility permissions to monitor keystrokes
//  across all applications.
//

import Cocoa
import Carbon

final class KeyMonitor {

    // MARK: - State

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentWord = ""
    private var isPaused = false

    var onLog: ((String) -> Void)?
    var onWordCompleted: ((String) -> Void)?
    var onCharacterTyped: ((String) -> Void)?
    var onEnterPressed: (() -> Void)?
    var onMouseDown: (() -> Void)?
    
    var isRunning: Bool {
        return eventTap != nil
    }

    // MARK: - Public API

    func start() {
        guard eventTap == nil else {
            onLog?("Key monitor already running")
            return
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard
                    let userInfo
                else {
                    return Unmanaged.passUnretained(event)
                }
                
                let monitor = Unmanaged<KeyMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                
                if type == .leftMouseDown {
                    monitor.onMouseDown?()
                    return Unmanaged.passUnretained(event)
                }
                
                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }

                guard !monitor.isPaused else {
                    return Unmanaged.passUnretained(event)
                }

                if let char = monitor.characterFromEvent(event) {
                    monitor.handle(char: char)
                } else if let char = monitor.character(from: event) {
                    monitor.handle(char: char)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            )
        )

        guard let eventTap else {
            onLog?("Failed to create event tap - check permissions")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        )

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            runLoopSource,
            .commonModes
        )

        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        guard let eventTap else { return }

        CGEvent.tapEnable(tap: eventTap, enable: false)

        if let source = runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                source,
                .commonModes
            )
        }

        self.eventTap = nil
        self.runLoopSource = nil
        self.currentWord = ""
        self.isPaused = false
    }
    
    // MARK: - Pause/Resume
    
    func pause() {
        isPaused = true
        currentWord = ""
    }
    
    func resume() {
        currentWord = ""
        isPaused = false
    }

    // MARK: - Word Buffering

    private func handle(char: String) {
        if char == "\u{0008}" || char == "\u{007F}" {
            if !currentWord.isEmpty {
                currentWord.removeLast()
            }
            onCharacterTyped?(char)
            return
        }
        
        if char == "\n" {
            if !currentWord.isEmpty {
                onWordCompleted?(currentWord)
                currentWord = ""
            }
            onEnterPressed?()
            return
        }
        
        if isWordBoundary(char) {
            if !currentWord.isEmpty {
                onWordCompleted?(currentWord)
                currentWord = ""
            }
            onCharacterTyped?(char)
        } else {
            if char.count == 1, let scalar = char.unicodeScalars.first, !scalar.isASCII || scalar.value >= 32 {
                currentWord.append(char)
                onCharacterTyped?(char)
            }
        }
    }

    private func isWordBoundary(_ char: String) -> Bool {
        return char == " " ||
               char == "\t" ||
               char == "." ||
               char == "," ||
               char == "!" ||
               char == "?"
    }

    // MARK: - Key Translation
    
    private func characterFromEvent(_ event: CGEvent) -> String? {
        var stringLength: Int = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &stringLength, unicodeString: nil)
        
        guard stringLength > 0 else {
            return nil
        }
        
        var unicodeString = [UniChar](repeating: 0, count: stringLength)
        event.keyboardGetUnicodeString(maxStringLength: stringLength, actualStringLength: &stringLength, unicodeString: &unicodeString)
        
        guard stringLength > 0 else {
            return nil
        }
        
        return String(utf16CodeUnits: unicodeString, count: stringLength)
    }

    private func character(from event: CGEvent) -> String? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return nil
        }
        
        guard let layoutDataPointer = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyUnicodeKeyLayoutData
        ) else {
            return nil
        }
        
        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let dataPtr = CFDataGetBytePtr(layoutData) else {
            return nil
        }

        return dataPtr.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
            var deadKeyState: UInt32 = 0
            var length: Int = 0
            var chars = [UniChar](repeating: 0, count: 4)

            let modifiers = event.flags
            var modifierKeyState: UInt32 = 0
            
            if modifiers.contains(.maskCommand) {
                modifierKeyState |= 0x01  // Command key
            }
            if modifiers.contains(.maskShift) {
                modifierKeyState |= 0x02  // Shift key
            }
            if modifiers.contains(.maskAlternate) {
                modifierKeyState |= 0x04  // Option/Alt key
            }
            if modifiers.contains(.maskControl) {
                modifierKeyState |= 0x08  // Control key
            }

            let status = UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )

            guard status == noErr, length > 0 else {
                return nil
            }

            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
