//
//  CorrectionEngine.swift
//  TypeFixPrototype
//
//  Main orchestration engine that coordinates all correction components:
//  - Key monitoring and word buffering
//  - Pause detection for button display
//  - OpenAI API integration for corrections
//  - Text replacement via Accessibility API
//  - Floating button management
//  - System autocorrect coordination
//
//  This is the central coordinator that manages the correction workflow
//  from keystroke detection to final text replacement.
//

import Foundation
import Cocoa

final class CorrectionEngine {
    
    // MARK: - Properties
    
    private let systemAutocorrect = SystemAutocorrectManager()
    private let pauseDetector = PauseDetector()
    private let textReplacer = AccessibilityTextReplacer()
    private let floatingButton = FloatingCorrectionButton()
    private let openAI = OpenAIClient()
    weak var keyMonitor: KeyMonitor?
    
    private var textBuffer: [String] = []
    private var isCorrectionInProgress = false
    private var enterHideTimer: Timer?
    private var selectedText: String?
    private var selectedTextRange: CFRange?
    
    var replaceTextAfterFinalPass = true
    var showFloatingButton = true
    var disableMacOSAutocorrect = true
    var showButtonOnSelection = true
    
    var correctionMode: CorrectionMode = .basic {
        didSet {
            openAI.correctionMode = correctionMode
            floatingButton.correctionMode = correctionMode
        }
    }
    
    var onLog: ((String) -> Void)?
    var onUpdateLog: ((String) -> Void)?
    
    init() {
        openAI.correctionMode = correctionMode
        
        if disableMacOSAutocorrect {
            systemAutocorrect.disableSystemAutocorrect()
        }
        
        pauseDetector.onLog = { [weak self] message in
            self?.onLog?(message)
        }
        
        textReplacer.onLog = { [weak self] message in
            self?.onLog?(message)
        }
        
        floatingButton.onLog = { [weak self] message in
            self?.onLog?(message)
        }
        
        openAI.onLog = { [weak self] message in
            self?.onLog?(message)
        }
        
        floatingButton.onButtonClicked = { [weak self] in
            guard let self = self else { return }
            
            guard !self.isCorrectionInProgress else {
                self.onLog?("Correction already in progress, ignoring click")
                return
            }
            
            let (accessibility, inputMonitoring) = checkAllPermissions()
            if !accessibility || !inputMonitoring {
                let missingPermissions = [(!accessibility ? "Accessibility" : nil), (!inputMonitoring ? "Input Monitoring" : nil)].compactMap { $0 }
                
                self.onLog?("Missing permissions: \(missingPermissions.joined(separator: ", "))")
                _ = requestAllPermissionsIfNeeded()
                return
            }
            
            if self.correctionMode == .fullFactChecking {
                self.floatingButton.showSpinner()
            } else {
                self.floatingButton.showSpinner()
            }
            
            self.isCorrectionInProgress = true
            
            let currentSelectedText = self.textReplacer.getSelectedText()
            let currentSelectedRange = self.textReplacer.getSelectedTextRange()
            
            self.onLog?("Button clicked. Selection check: \(currentSelectedText != nil ? "Found" : "None")")
            
            if let selected = currentSelectedText, !selected.isEmpty, currentSelectedRange != nil {
                self.performOpenAICorrection(on: selected) { corrected in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        self.isCorrectionInProgress = false
                        
                        if self.replaceTextAfterFinalPass && !corrected.isEmpty {
                            self.keyMonitor?.pause()
                            usleep(100000)
                            let success = self.textReplacer.replaceSelectedText(with: corrected)
                            if !success {
                                self.textReplacer.replaceText(with: corrected, replacing: selected)
                            }
                            usleep(200000)
                            self.keyMonitor?.resume()
                        }
                        
                        self.selectedText = nil
                        self.selectedTextRange = nil
                        
                        if self.correctionMode == .fullFactChecking {
                            self.floatingButton.hide()
                        } else {
                            self.floatingButton.hideSpinner()
                        }
                    }
                }
            } else {
                // Normal flow - correct buffered text
                self.performOpenAICorrection { corrected, original in
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        
                        self.isCorrectionInProgress = false
                        
                        if self.replaceTextAfterFinalPass && !corrected.isEmpty {
                            self.keyMonitor?.pause()
                            usleep(100000)
                            self.textReplacer.replaceText(with: corrected, replacing: original)
                            usleep(200000)
                            self.keyMonitor?.resume()
                        }
                        
                        if self.correctionMode == .fullFactChecking {
                            self.floatingButton.hide()
                        } else {
                            self.floatingButton.hideSpinner()
                        }
                    }
                }
            }
        }
        
        pauseDetector.onPauseDetected = { [weak self] in
            guard let self = self else { return }
            
            let bufferedText = self.getBufferedText()
            let cleanText = bufferedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if cleanText.count <= 1 {
                return
            }
            
            if self.showFloatingButton && self.floatingButton.showOnPause && !self.textBuffer.isEmpty {
                self.floatingButton.show()
            }
        }
        
        textReplacer.onSelectionChanged = { [weak self] selectedText, range in
            guard let self = self else { return }
            
            self.selectedText = selectedText
            self.selectedTextRange = range
            
            if let selected = selectedText, !selected.isEmpty, self.showButtonOnSelection {
                if let bounds = self.textReplacer.getSelectionBounds() {
                    self.floatingButton.showNearSelection(bounds)
                } else {
                    self.floatingButton.show()
                }
            } else if selectedText == nil {
                if self.textBuffer.isEmpty {
                    self.floatingButton.hide()
                }
            }
        }
        
        textReplacer.startSelectionMonitoring()
    }
    
    deinit {
        if disableMacOSAutocorrect {
            systemAutocorrect.restoreSystemAutocorrect()
        }
    }
    
    func processWord(_ word: String) {
        guard !word.isEmpty else { return }
        
        textBuffer.append(word)
        
        // Log the current buffer state using update log to keep it on one line
        let currentText = textBuffer.joined(separator: " ")
        onUpdateLog?("Typing: \(currentText)")
        
        enterHideTimer?.invalidate()
        enterHideTimer = nil
        
        floatingButton.hide()
        pauseDetector.didType()
    }
    
    /// Performs correction on a specific text string (used for selected text)
    func performOpenAICorrection(on text: String, completion: @escaping (String) -> Void) {
        guard !text.isEmpty else {
            onLog?("No text to correct")
            isCorrectionInProgress = false
            completion("")
            return
        }
        
        onLog?("Requesting correction for selected text: \"\(text)\"")
        
        openAI.correctText(text) { [weak self] corrected, error in
            guard let self = self else { return }
            
            self.isCorrectionInProgress = false
            
            if let error = error {
                self.onLog?("Correction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion("")
                }
                return
            }
            
            guard let correctedText = corrected else {
                self.onLog?("No correction received from OpenAI")
                DispatchQueue.main.async {
                    completion("")
                }
                return
            }
            
            self.onLog?("Corrected selected text: \"\(correctedText)\"")
            
            DispatchQueue.main.async {
                completion(correctedText)
            }
        }
    }
    
    func performOpenAICorrection(completion: @escaping (String, String) -> Void) {
        let axText = textReplacer.getCurrentText()
        let bufferedText = textBuffer.joined(separator: " ")
        
        onLog?("Debug - AXText: '\(String(describing: axText))', Buffer: '\(bufferedText)'")
        
        var textToCorrect = ""
        var usingBufferOnly = false
        
        if !bufferedText.isEmpty {
             textToCorrect = bufferedText
             usingBufferOnly = true
        } else {
            let fullText = axText ?? ""
            if fullText.isEmpty { return }
            
            textToCorrect = fullText
        }
        
        guard !textToCorrect.isEmpty else {
            onLog?("No text to correct")
            isCorrectionInProgress = false
            completion("", "")
            return
        }
        
        onLog?("Requesting correction for: \"\(textToCorrect)\"")
        
        openAI.correctText(textToCorrect) { [weak self] corrected, error in
            guard let self = self else { return }
            
            self.isCorrectionInProgress = false
            
            if let error = error {
                self.onLog?("Correction failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion("", "")
                }
                return
            }
            
            guard let correctedSegment = corrected else {
                self.onLog?("No correction received from OpenAI")
                DispatchQueue.main.async {
                    completion("", "")
                }
                return
            }
            
            self.onLog?("Final corrected text: \"\(correctedSegment)\"")
            
            DispatchQueue.main.async {
                if usingBufferOnly {
                    self.keyMonitor?.pause()
                    self.textReplacer.replaceLastCharacters(count: textToCorrect.count, with: correctedSegment)
                    usleep(200000)
                    self.keyMonitor?.resume()
                    self.clearBuffer()
                    
                    if self.correctionMode == .basic {
                        self.floatingButton.hideSpinner()
                    }
                } else {
                    completion(correctedSegment, textToCorrect)
                }
            }
        }
    }
    
    func clearBuffer() {
        if !textBuffer.isEmpty {
            onLog?("Clearing buffer (had \(textBuffer.count) words)")
        }
        textBuffer.removeAll()
        pauseDetector.stop()
    }
    
    func getBufferedText() -> String {
        return textBuffer.joined(separator: " ")
    }
    
    func setupCharacterTypedCallback() {
        keyMonitor?.onCharacterTyped = { [weak self] _ in
            self?.enterHideTimer?.invalidate()
            self?.enterHideTimer = nil
            
            self?.floatingButton.hide()
            self?.pauseDetector.didType()
        }
    }
    
    func handleEnterPressed() {
        onLog?("Enter pressed - clearing buffer")
        pauseDetector.stop()
        clearBuffer()
        
        enterHideTimer?.invalidate()
        enterHideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.floatingButton.hide()
            self?.enterHideTimer = nil
        }
    }
    
}

