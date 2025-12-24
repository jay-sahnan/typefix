//
//  Permissions.swift
//  TypeFixPrototype
//
//  Handles requesting Accessibility and Input Monitoring permissions from the user.
//  Both are required for the app to monitor keystrokes and replace text across
//  all applications. The system will prompt the user to grant access
//  in System Settings if not already granted.
//

import ApplicationServices
import CoreServices
import CoreGraphics

func requestAccessibilityIfNeeded() -> Bool {
    let options = [
        kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
    ] as CFDictionary

    let trusted = AXIsProcessTrustedWithOptions(options)
    return trusted
}

func requestInputMonitoringIfNeeded() -> Bool {
    let eventMask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
    
    if let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, _, _, _ in nil },
        userInfo: nil
    ) {
        CGEvent.tapEnable(tap: eventTap, enable: false)
        return true
    }
    
    return false
}

func checkInputMonitoringPermission() -> Bool {
    let eventMask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
    
    guard let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: { _, _, _, _ in nil },
        userInfo: nil
    ) else {
        return false
    }
    
    CGEvent.tapEnable(tap: eventTap, enable: false)
    return true
}

func checkAccessibilityPermission() -> Bool {
    return AXIsProcessTrusted()
}

func requestAllPermissionsIfNeeded() -> (accessibility: Bool, inputMonitoring: Bool) {
    let accessibility = requestAccessibilityIfNeeded()
    let inputMonitoring = requestInputMonitoringIfNeeded()
    return (accessibility, inputMonitoring)
}

func checkAllPermissions() -> (accessibility: Bool, inputMonitoring: Bool) {
    let accessibility = checkAccessibilityPermission()
    let inputMonitoring = checkInputMonitoringPermission()
    return (accessibility, inputMonitoring)
}
