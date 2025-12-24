//
//  AccessibilityTextReplacer.swift
//  TypeFixPrototype
//
//  Replaces text in focused text fields using the macOS Accessibility API.
//  This approach is more reliable than character-by-character keyboard simulation
//  because it directly manipulates the text field's value.
//
//  Implements multiple fallback strategies:
//  1. Direct value replacement via AX API
//  2. Selection-based replacement
//  3. Keyboard simulation fallback (if Accessibility API fails)
//
//  Intelligently matches and replaces only the relevant portion of text,
//  preserving any text that was typed before the correction buffer.
//

import Cocoa
import ApplicationServices

final class AccessibilityTextReplacer {
    
    var onLog: ((String) -> Void)?
    var onSelectionChanged: ((String?, CFRange?) -> Void)?
    
    private var selectionMonitorTimer: Timer?
    private var lastSelectionRange: CFRange?
    private var isMonitoringSelection = false
    
    func getCurrentText() -> String? {
        guard let focusedElement = getFocusedElement() else {
            return nil
        }
        
        var currentValue: AnyObject?
        let readResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )
        
        if readResult == .success, let currentText = currentValue as? String {
            return currentText
        }
        
        return nil
    }
    
    /// Gets the currently selected text from the focused element
    func getSelectedText() -> String? {
        guard let focusedElement = getFocusedElement() else {
            return nil
        }
        
        var selectedTextValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextValue
        )
        
        if result == .success, let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
            return selectedText
        }
        
        return nil
    }
    
    /// Gets the selected text range (location and length)
    func getSelectedTextRange() -> CFRange? {
        guard let focusedElement = getFocusedElement() else {
            return nil
        }
        
        var rangeValue: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        
        guard result == .success, let range = rangeValue else {
            return nil
        }
        
        guard CFGetTypeID(range) == AXValueGetTypeID() else {
            return nil
        }
        
        let axRangeValue = range as! AXValue
        var cfRange = CFRange()
        if AXValueGetValue(axRangeValue, .cfRange, &cfRange) {
            if cfRange.length > 0 {
                return cfRange
            }
        }
        
        return nil
    }
    
    /// Gets the screen position of the selected text for button positioning
    /// Returns bounds in screen coordinates (with Y flipped for macOS coordinate system)
    func getSelectionBounds() -> CGRect? {
        guard let focusedElement = getFocusedElement(),
              getSelectedTextRange() != nil else {
            return nil
        }
        
        var rangeValue: AnyObject?
        let getRangeResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        
        guard getRangeResult == .success, let rangeVal = rangeValue else {
            return nil
        }
        
        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeVal,
            &boundsValue
        )
        
        guard boundsResult == .success, let boundsVal = boundsValue else {
            return nil
        }
        
        guard CFGetTypeID(boundsVal) == AXValueGetTypeID() else {
            return nil
        }
        
        let axBoundsValue = boundsVal as! AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(axBoundsValue, .cgRect, &rect) else {
            return nil
        }
        
        return rect
    }
    
    /// Starts monitoring text selection changes
    func startSelectionMonitoring() {
        guard !isMonitoringSelection else { return }
        isMonitoringSelection = true
        
        // Check selection immediately
        checkSelection()
        
        // Poll for selection changes every 0.1 seconds
        selectionMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkSelection()
        }
    }
    
    /// Stops monitoring text selection changes
    func stopSelectionMonitoring() {
        isMonitoringSelection = false
        selectionMonitorTimer?.invalidate()
        selectionMonitorTimer = nil
        lastSelectionRange = nil
    }
    
    /// Checks if the selection has changed and notifies listeners
    private func checkSelection() {
        guard let range = getSelectedTextRange() else {
            if lastSelectionRange != nil {
                lastSelectionRange = nil
                onSelectionChanged?(nil, nil)
            }
            return
        }
        
        if let lastRange = lastSelectionRange {
            if lastRange.location != range.location || lastRange.length != range.length {
                lastSelectionRange = range
                let selectedText = getSelectedText()
                onSelectionChanged?(selectedText, range)
            }
        } else {
            lastSelectionRange = range
            let selectedText = getSelectedText()
            onSelectionChanged?(selectedText, range)
        }
    }
    
    /// Replaces the currently selected text with new text, preserving formatting
    func replaceSelectedText(with newText: String) -> Bool {
        guard let focusedElement = getFocusedElement() else {
            onLog?("Error: No focused text element found")
            return false
        }
        
        guard getSelectedTextRange() != nil else {
            onLog?("Error: No text selected")
            return false
        }
        
        if isBrowser() {
            onLog?("Browser detected, using clipboard paste for reliability")
            pasteText(newText)
            return true
        }
        
        if trySetSelectedText(newText, for: focusedElement) {
            return true
        }
        
        onLog?("AX replacement failed, falling back to paste")
        pasteText(newText)
        return true
    }
    
    func replaceText(with newText: String, replacing originalText: String? = nil) {
        guard let focusedElement = getFocusedElement() else {
            onLog?("Error: No focused text element found")
            return
        }
        
        var currentValue: AnyObject?
        let readResult = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            &currentValue
        )
        
        var finalText = newText
        
        if readResult == .success, let currentText = currentValue as? String {
            let trimmedCurrent = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedNew = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedCurrent.isEmpty {
                finalText = trimmedNew
            } else if let original = originalText?.trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty {
                if let range = trimmedCurrent.range(of: original, options: [String.CompareOptions.backwards, String.CompareOptions.caseInsensitive]) {
                    let prefix = String(trimmedCurrent[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    finalText = prefix.isEmpty ? trimmedNew : prefix + " " + trimmedNew
                } else {
                    let correctedWords = trimmedNew.split(separator: " ").map(String.init)
                    let currentWords = trimmedCurrent.split(separator: " ").map(String.init)
                    
                    var matchingWordCount = 0
                    let maxMatch = min(correctedWords.count, currentWords.count)
                    
                    for i in 1...maxMatch {
                        let correctedSuffix = correctedWords.suffix(i).map { $0.lowercased() }.joined(separator: " ")
                        let currentSuffix = currentWords.suffix(i).map { $0.lowercased() }.joined(separator: " ")
                        if correctedSuffix == currentSuffix {
                            matchingWordCount = i
                        } else {
                            break
                        }
                    }
                    
                    if matchingWordCount > 0 && matchingWordCount == correctedWords.count {
                        let prefixWords = currentWords.dropLast(matchingWordCount)
                        let prefix = prefixWords.joined(separator: " ")
                        let correctedSuffix = correctedWords.suffix(matchingWordCount).joined(separator: " ")
                        finalText = prefix.isEmpty ? correctedSuffix : prefix + " " + correctedSuffix
                    } else if matchingWordCount > 0 {
                        let prefixWords = currentWords.dropLast(matchingWordCount)
                        let prefix = prefixWords.joined(separator: " ")
                        let correctedSuffix = correctedWords.suffix(matchingWordCount).joined(separator: " ")
                        finalText = prefix.isEmpty ? correctedSuffix : prefix + " " + correctedSuffix
                    } else {
                        let originalWordCount = originalText?.split(separator: " ").count ?? correctedWords.count
                        let replaceCount = min(originalWordCount, currentWords.count)
                        
                        if replaceCount > 0 {
                            let prefixWords = currentWords.dropLast(replaceCount)
                            let prefix = prefixWords.joined(separator: " ")
                            finalText = prefix.isEmpty ? trimmedNew : prefix + " " + trimmedNew
                        } else {
                            finalText = trimmedCurrent + " " + trimmedNew
                        }
                    }
                }
            } else {
                let newWordCount = trimmedNew.split(separator: " ").count
                let currentWords = trimmedCurrent.split(separator: " ")
                
                if newWordCount <= currentWords.count {
                    let prefixWords = currentWords.dropLast(newWordCount)
                    let prefix = prefixWords.joined(separator: " ")
                    finalText = prefix.isEmpty ? trimmedNew : prefix + " " + trimmedNew
                } else {
                    finalText = trimmedCurrent + " " + trimmedNew
                }
            }
        } else {
            onLog?("Warning: Could not read current text, replacing entire field")
        }
        
        finalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        
        var method1Success = false
        if setValue(finalText, for: focusedElement) {
            method1Success = true
            
            usleep(100000)
            var verifyValue: AnyObject?
            let verifyResult = AXUIElementCopyAttributeValue(
                focusedElement,
                kAXValueAttribute as CFString,
                &verifyValue
            )
            
            if verifyResult == .success, let verifiedText = verifyValue as? String {
                if verifiedText != finalText {
                    method1Success = false
                    onLog?("Warning: Text replacement verification failed")
                }
            } else {
                method1Success = false
            }
        }
        
        if !method1Success {
            if trySetSelectedText(finalText, for: focusedElement) {
                usleep(100000)
                var verifyValue: AnyObject?
                let verifyResult = AXUIElementCopyAttributeValue(
                    focusedElement,
                    kAXValueAttribute as CFString,
                    &verifyValue
                )
                if verifyResult == .success, let verifiedText = verifyValue as? String {
                    if verifiedText == finalText {
                        return
                    }
                }
            }
        }
        
        if !method1Success {
            onLog?("Warning: Accessibility API failed, using keyboard fallback")
            fallbackReplaceText(with: finalText)
        }
    }
    
    private func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        return (element as! AXUIElement)
    }
    
    private func setValue(_ value: String, for element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        )
        
        return result == .success
    }
    
    private func trySetSelectedText(_ text: String, for element: AXUIElement) -> Bool {
        var currentRangeValue: AnyObject?
        let getRangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &currentRangeValue
        )
        
        if getRangeResult != .success || currentRangeValue == nil {
            var currentValue: AnyObject?
            let readResult = AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &currentValue
            )
            
            guard readResult == .success, let currentText = currentValue as? String else {
                return false
            }
            
            let textLength = currentText.count
            if textLength == 0 {
                return setValue(text, for: element)
            }
            
            var range = CFRange(location: 0, length: textLength)
            guard let rangeValue = AXValueCreate(.cfRange, &range) else {
                return false
            }
            
            let setRangeResult = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
            )
            
            guard setRangeResult == .success else {
                return false
            }
            
            usleep(50000)
        }
        
        let setSelectedResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        
        return setSelectedResult == .success
    }
    
    private func fallbackReplaceText(with newText: String) {
        var selectionSuccess = false
        
        if let focusedElement = getFocusedElement(), let currentText = getCurrentText() {
            let textLength = currentText.count
            if textLength > 0 {
                var range = CFRange(location: 0, length: textLength)
                if let rangeValue = AXValueCreate(.cfRange, &range) {
                    let setRangeResult = AXUIElementSetAttributeValue(
                        focusedElement,
                        kAXSelectedTextRangeAttribute as CFString,
                        rangeValue
                    )
                    if setRangeResult == .success {
                        selectionSuccess = true
                        usleep(50000)
                    }
                }
            }
        }
        
        if !selectionSuccess {
            sendKeyCombo(key: 0x00, modifiers: .maskCommand) // Cmd+A
            usleep(100000)
        }
        
        sendKey(0x33)
        usleep(50000)
        
        pasteText(newText)
        usleep(50000)
    }
    
    func replaceLastCharacters(count: Int, with newText: String) {
        guard count > 0 else { return }
        
        for _ in 0..<count {
            sendKey(0x33)
            usleep(2000)
        }
        
        usleep(50000)
        
        pasteText(newText)
    }

    private func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        sendKeyCombo(key: 0x09, modifiers: .maskCommand) // Cmd+V
    }
    
    private func isBrowser() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleId = app.bundleIdentifier?.lowercased() else {
            return false
        }
        return bundleId.contains("chrome") ||
               bundleId.contains("safari") ||
               bundleId.contains("firefox") ||
               bundleId.contains("arc") ||
               bundleId.contains("edge") ||
               bundleId.contains("brave")
    }

    private func sendKeyCombo(key: CGKeyCode, modifiers: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        keyDown?.flags = modifiers
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func sendKey(_ key: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        keyDown?.post(tap: .cghidEventTap)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    private func typeText(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        
        for char in text {
            let utf16 = String(char).utf16
            var unicodeString = Array(utf16)
            
            guard !unicodeString.isEmpty else { continue }
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            keyDown?.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyDown?.post(tap: .cghidEventTap)
            
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyUp?.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
            keyUp?.post(tap: .cghidEventTap)
            
            usleep(5000)
        }
    }
}

