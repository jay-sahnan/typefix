//
//  PauseDetector.swift
//  TypeFixPrototype
//
//  Detects when the user stops typing for a specified duration (pause threshold).
//  When a pause is detected, it triggers the floating correction button to appear,
//  allowing users to request corrections after they've finished typing a phrase.
//
//  Uses a timer-based approach: each keystroke resets the timer, and if no
//  keystrokes occur within the threshold period, a pause is detected.
//

import Foundation

final class PauseDetector {
    
    // MARK: - Properties
    
    private var lastKeystrokeTime: Date?
    private var checkTimer: Timer?
    private let pauseThreshold: TimeInterval = 0.4
    
    // Callback when pause is detected
    var onPauseDetected: (() -> Void)?
    
    var onLog: ((String) -> Void)?
    
    // MARK: - Public API
    
    /// Notify that user just typed something
    func didType() {
        lastKeystrokeTime = Date()
        
        // Cancel existing timer
        checkTimer?.invalidate()
        
        // Start new timer to check for pause
        checkTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            self?.checkForPause()
        }
    }
    
    /// Stop monitoring for pauses
    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        lastKeystrokeTime = nil
    }
    
    // MARK: - Private Methods
    
    private func checkForPause() {
        guard let lastTime = lastKeystrokeTime else { return }
        
        let timeSinceLastKeystroke = Date().timeIntervalSince(lastTime)
        
        if timeSinceLastKeystroke >= pauseThreshold {
            onPauseDetected?()
        }
    }
}

