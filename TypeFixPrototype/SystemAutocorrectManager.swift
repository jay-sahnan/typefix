//
//  SystemAutocorrectManager.swift
//  TypeFixPrototype
//
//  Manages coordination with macOS's built-in autocorrect system to prevent
//  conflicts. This class can disable system autocorrect when TypeFix is active
//  and restore it when the app terminates, ensuring only one correction system
//  operates at a time.
//
//  Also provides utilities to detect if macOS has already corrected text,
//  helping to avoid double-corrections.
//

import Cocoa

final class SystemAutocorrectManager {
    
    // MARK: - Properties
    
    private var originalAutocorrectState: Bool?
    
    // MARK: - Public API
    
    /// Disable macOS's built-in autocorrect system-wide
    /// This prevents conflicts with our custom autocorrection
    func disableSystemAutocorrect() {
        // Get current state
        let defaults = UserDefaults.standard
        originalAutocorrectState = defaults.bool(forKey: "NSAutomaticSpellingCorrectionEnabled")
        
        // Disable it
        defaults.set(false, forKey: "NSAutomaticSpellingCorrectionEnabled")
        defaults.set(false, forKey: "WebAutomaticSpellingCorrectionEnabled")
        
        // Also disable automatic text replacement
        defaults.set(false, forKey: "NSAutomaticTextReplacementEnabled")
        
        // Synchronize
        defaults.synchronize()
    }
    
    /// Re-enable macOS's built-in autocorrect
    func restoreSystemAutocorrect() {
        let defaults = UserDefaults.standard
        
        // Restore original state
        if let originalState = originalAutocorrectState {
            defaults.set(originalState, forKey: "NSAutomaticSpellingCorrectionEnabled")
            defaults.set(originalState, forKey: "WebAutomaticSpellingCorrectionEnabled")
            defaults.set(originalState, forKey: "NSAutomaticTextReplacementEnabled")
            defaults.synchronize()
        }
    }
    
    /// Check if macOS autocorrect is currently enabled
    func isSystemAutocorrectEnabled() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "NSAutomaticSpellingCorrectionEnabled")
    }
    
    /// Detect if a word was recently changed by macOS autocorrect
    /// This helps us avoid double-correcting
    func detectSystemCorrection(original: String, current: String) -> Bool {
        // If they're different and current is a valid word, macOS likely corrected it
        guard original != current else { return false }
        
        // Simple heuristic: if current is a valid word and similar to original,
        // macOS probably corrected it
        let similarity = calculateSimilarity(original, current)
        return similarity > 0.6
    }
    
    // MARK: - Private Methods
    
    /// Calculate similarity between two strings (0.0 to 1.0)
    private func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        let longerLength = max(s1.count, s2.count)
        
        if longerLength == 0 {
            return 1.0
        }
        
        let editDistance = levenshteinDistance(s1, s2)
        return (Double(longerLength) - Double(editDistance)) / Double(longerLength)
    }
    
    /// Calculate Levenshtein distance
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count {
            matrix[i][0] = i
        }
        
        for j in 0...s2Count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        
        return matrix[s1Count][s2Count]
    }
}

