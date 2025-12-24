//
//  FloatingCorrectionButton.swift
//  TypeFixPrototype
//
//  Displays a floating correction button that appears near the text cursor
//  when the user pauses typing.
//

import Cocoa
import ApplicationServices

final class FloatingCorrectionButton {
    
    private var floatingWindow: NSWindow?
    private var button: NSButton?
    private var spinnerView: NSProgressIndicator?
    private var isVisible = false
    private var autoHideTimer: Timer?
    private var isShowingSpinner = false
    
    var onButtonClicked: (() -> Void)?
    var onLog: ((String) -> Void)?
    
    var showOnPause = true
    var offsetFromCursor: NSPoint = NSPoint(x: 10, y: 5)
    var correctionMode: CorrectionMode = .basic
    
    func show(at position: NSPoint? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show(at: position)
            }
            return
        }
        
        guard !isVisible else { return }
        
        var targetLocation: NSPoint
        if let customPosition = position {
            targetLocation = customPosition
        } else {
            targetLocation = getTextCursorPosition()
            if targetLocation == NSPoint.zero {
                targetLocation = NSEvent.mouseLocation
            }
        }
        
        showAtLocation(targetLocation)
    }
    
    /// Shows the button at a specific location (internal method)
    private func showAtLocation(_ targetLocation: NSPoint) {
        
        let window = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        
        let button = SafeActionButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        
        button.title = "✨"
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 14)
        button.imagePosition = .noImage
        
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        button.layer?.cornerRadius = button.frame.height / 2
        button.layer?.masksToBounds = true
        button.contentTintColor = nil
        
        button.actionHandler = { [weak self] in
            self?.handleButtonClick()
        }
        
        window.contentView = NSView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(button)
        
        let windowFrame = NSRect(
            x: targetLocation.x + offsetFromCursor.x,
            y: targetLocation.y - 20 - offsetFromCursor.y,
            width: 20,
            height: 20
        )
        
        window.setFrame(windowFrame, display: true)
        window.alphaValue = 0.0
        window.orderFront(nil)
        
        self.floatingWindow = window
        self.button = button
        self.isVisible = true
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            window.alphaValue = 1.0
        }
        
        startAutoHideTimer()
    }
    
    /// Shows the button near a text selection rectangle
    func showNearSelection(_ selectionBounds: CGRect) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showNearSelection(selectionBounds)
            }
            return
        }
        
        guard !isVisible else { return }
        
        if let screen = NSScreen.main {
            let convertedY = screen.frame.height - selectionBounds.origin.y - selectionBounds.height
            let targetLocation = NSPoint(
                x: selectionBounds.origin.x + selectionBounds.width,
                y: convertedY
            )
            showAtLocation(targetLocation)
        } else {
            show()
        }
    }
    
    func hide() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.hide()
            }
            return
        }
        
        guard isVisible else { return }
        
        (button as? SafeActionButton)?.actionHandler = nil
        
        spinnerView?.stopAnimation(nil)
        spinnerView = nil
        
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        
        guard let window = floatingWindow else {
            isVisible = false
            isShowingSpinner = false
            return
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            window.alphaValue = 0.0
        }, completionHandler: {
            window.close()
            self.floatingWindow = nil
            self.button = nil
            self.isVisible = false
            self.isShowingSpinner = false
        })
    }
    
    func showSpinner() {
        guard isVisible, button != nil else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.button else { return }
            
            button.title = ""
            
            if self.spinnerView == nil {
                let spinner = NSProgressIndicator(frame: NSRect(x: 4, y: 4, width: 12, height: 12))
                spinner.style = .spinning
                spinner.controlSize = .small
                spinner.isIndeterminate = true
                button.addSubview(spinner)
                self.spinnerView = spinner
            }
            
            self.spinnerView?.startAnimation(nil)
            self.isShowingSpinner = true
        }
    }
    
    func hideSpinner() {
        guard isVisible else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.button else { return }
            
            self.spinnerView?.stopAnimation(nil)
            self.spinnerView?.removeFromSuperview()
            self.spinnerView = nil
            self.isShowingSpinner = false
            
            if self.correctionMode == .basic {
                button.title = "✨"
            }
        }
    }
    
    private func getTextCursorPosition() -> NSPoint {
        return autoreleasepool {
            let systemWideElement = AXUIElementCreateSystemWide()
            var focusedElement: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                systemWideElement,
                kAXFocusedUIElementAttribute as CFString,
                &focusedElement
            )
            
            guard result == .success, let element = focusedElement else {
                return NSPoint.zero
            }
            
            let axElement = element as! AXUIElement
            var selectedTextRangeValue: CFTypeRef?
            let rangeResult = AXUIElementCopyAttributeValue(
                axElement,
                kAXSelectedTextRangeAttribute as CFString,
                &selectedTextRangeValue
            )
            
            guard rangeResult == .success, let rangeValue = selectedTextRangeValue else {
                return NSPoint.zero
            }
            
            guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
                return NSPoint.zero
            }
            
            let axRangeValue = rangeValue as! AXValue
            var range = CFRange()
            AXValueGetValue(axRangeValue, .cfRange, &range)
            
            var boundsValue: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                axElement,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsValue
            )
            
            if boundsResult == .success, let boundsVal = boundsValue {
                if CFGetTypeID(boundsVal) == AXValueGetTypeID() {
                    let axBoundsValue = boundsVal as! AXValue
                    var rect = CGRect.zero
                    AXValueGetValue(axBoundsValue, .cgRect, &rect)
                    
                    if let screen = NSScreen.main {
                        let convertedY = screen.frame.height - rect.origin.y - rect.height
                        return NSPoint(x: rect.origin.x + rect.width, y: convertedY)
                    }
                }
            }
            
            return NSPoint.zero
        }
    }
    
    private func handleButtonClick() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        onButtonClicked?()
    }
    
    private func startAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }
}

private class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private class SafeActionButton: NSButton {
    var actionHandler: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var originalFrame: NSRect?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.target = self
        self.action = #selector(buttonPressed)
        self.originalFrame = frameRect
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.target = self
        self.action = #selector(buttonPressed)
        self.originalFrame = self.frame
        setupTrackingArea()
    }
    
    @objc private func buttonPressed() {
        actionHandler?()
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        setupTrackingArea()
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        
        NSCursor.pointingHand.push()
        
        let scale: CGFloat = 0.9
        let newWidth = (originalFrame?.width ?? frame.width) * scale
        let newHeight = (originalFrame?.height ?? frame.height) * scale
        let centerX = frame.midX
        let centerY = frame.midY
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            self.frame = NSRect(
                x: centerX - newWidth / 2,
                y: centerY - newHeight / 2,
                width: newWidth,
                height: newHeight
            )
            self.layer?.cornerRadius = min(newWidth, newHeight) / 2
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        
        NSCursor.pop()
        
        guard let original = originalFrame else { return }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            self.frame = original
            self.layer?.cornerRadius = min(original.width, original.height) / 2
        }
    }
}

