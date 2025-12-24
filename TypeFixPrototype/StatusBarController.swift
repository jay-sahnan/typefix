//
//  StatusBarController.swift
//  TypeFixPrototype
//
//  Manages the menu bar interface and coordinates between the key monitor,
//  correction engine, and log window.
//

import Cocoa

enum CorrectionMode {
    case basic
    case fullFactChecking
}

final class StatusBarController: NSObject {
    
    private var statusItem: NSStatusItem?
    private var logWindowController: LogWindowController?
    private var apiKeyWindowController: APIKeyWindowController?
    private var apiKeyMenuItem: NSMenuItem?
    
    private let keyMonitor = KeyMonitor()
    private let correctionEngine = CorrectionEngine()
    
    var buttonBackgroundColor: NSColor = .clear {
        didSet {
            updateButtonBackground()
        }
    }
    
    private var isBasicEnabled: Bool = true {
        didSet {
            updateEffectiveMode()
            updateMenu()
        }
    }
    
    private var isFullFactCheckingEnabled: Bool = false {
        didSet {
            updateEffectiveMode()
            updateMenu()
        }
    }
    
    private var effectiveMode: CorrectionMode = .basic {
        didSet {
            correctionEngine.correctionMode = effectiveMode
        }
    }
    
    override init() {
        super.init()
        setupStatusBar()
        setupMenu()
        setupCorrectionEngine()
        requestAccessibilityAndStart()
    }
    
    private func updateEffectiveMode() {
        if isFullFactCheckingEnabled {
            effectiveMode = .fullFactChecking
        } else if isBasicEnabled {
            effectiveMode = .basic
        } else {
            effectiveMode = .basic
        }
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "text.cursor", accessibilityDescription: "TypeFix")
            image?.isTemplate = true
            button.image = image
            
            button.wantsLayer = true
            updateButtonBackground()
            
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            
            DistributedNotificationCenter.default.addObserver(
                self,
                selector: #selector(updateIconForAppearance),
                name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil
            )
        }
    }
    
    @objc private func updateIconForAppearance() {
        if let button = statusItem?.button, let image = button.image {
            button.image = nil
            button.image = image
        }
    }
    
    private func updateButtonBackground() {
        statusItem?.button?.layer?.backgroundColor = buttonBackgroundColor.cgColor
    }
    
    deinit {
        DistributedNotificationCenter.default.removeObserver(self)
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        
        let modeHeader = NSMenuItem(title: "Correction Mode", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)
        
        let basicItem = NSMenuItem(title: "Basic", action: #selector(toggleBasicMode), keyEquivalent: "")
        basicItem.target = self
        basicItem.state = isBasicEnabled ? .on : .off
        menu.addItem(basicItem)
        
        let factCheckItem = NSMenuItem(title: "Fact Checking", action: #selector(toggleFactCheckMode), keyEquivalent: "")
        factCheckItem.target = self
        factCheckItem.state = isFullFactCheckingEnabled ? .on : .off
        menu.addItem(factCheckItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let apiKeyItem = NSMenuItem(title: "Add OpenAI API Key", action: #selector(showAPIKeyDialog), keyEquivalent: "")
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)
        apiKeyMenuItem = apiKeyItem
        
        let showLogsItem = NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "")
        showLogsItem.target = self
        menu.addItem(showLogsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func updateAPIKeyMenuItemTitle() {
        let title = KeychainManager.hasAPIKey() ? "Edit API Key" : "Add OpenAI API Key"
        apiKeyMenuItem?.title = title
    }
    
    private func updateMenu() {
        setupMenu()
    }
    
    private func setupCorrectionEngine() {
        updateEffectiveMode()
        correctionEngine.correctionMode = effectiveMode
        
        if logWindowController == nil {
            logWindowController = LogWindowController()
            logWindowController?.keyMonitor = keyMonitor
            logWindowController?.correctionEngine = correctionEngine
        }
        
        correctionEngine.onLog = { [weak self] message in
            self?.logWindowController?.log(message)
        }
        
        correctionEngine.onUpdateLog = { [weak self] message in
            self?.logWindowController?.log(message, replaceLast: true)
        }
        
        keyMonitor.onLog = { [weak self] message in
            self?.logWindowController?.log(message)
        }
        
        keyMonitor.onWordCompleted = { [weak self] word in
            self?.correctionEngine.processWord(word)
        }
        
        keyMonitor.onEnterPressed = { [weak self] in
            self?.correctionEngine.handleEnterPressed()
        }
        
        correctionEngine.keyMonitor = keyMonitor
        correctionEngine.setupCharacterTypedCallback()
    }
    
    @objc private func statusBarButtonClicked() {
    }
    
    @objc private func toggleBasicMode() {
        isBasicEnabled.toggle()
    }
    
    @objc private func toggleFactCheckMode() {
        isFullFactCheckingEnabled.toggle()
    }
    
    @objc private func showAPIKeyDialog() {
        if apiKeyWindowController == nil {
            apiKeyWindowController = APIKeyWindowController()
            apiKeyWindowController?.onAPIKeySaved = { [weak self] in
                self?.logWindowController?.log("OpenAI API key saved successfully")
                self?.updateMenu()
            }
            apiKeyWindowController?.onAPIKeyDeleted = { [weak self] in
                self?.logWindowController?.log("OpenAI API key deleted")
                self?.updateMenu()
            }
        }
        apiKeyWindowController?.showWindow(nil)
    }
    
    @objc private func showLogs() {
        if logWindowController == nil {
            logWindowController = LogWindowController()
            logWindowController?.keyMonitor = keyMonitor
            logWindowController?.correctionEngine = correctionEngine
        }
        logWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }
    
    private func requestAccessibilityAndStart() {
        let (accessibility, inputMonitoring) = checkAllPermissions()
        
        if !accessibility || !inputMonitoring {
            let missingPermissions = [(!accessibility ? "Accessibility" : nil), (!inputMonitoring ? "Input Monitoring" : nil)].compactMap { $0 }
            logWindowController?.log("Missing permissions: \(missingPermissions.joined(separator: ", ")). Please grant in System Settings.")
            
            _ = requestAllPermissionsIfNeeded()
            return
        }
        
        keyMonitor.start()
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateAPIKeyMenuItemTitle()
    }
}

final class LogWindowController: NSWindowController {
    
    private var logViewController: LogViewController?
    
    var keyMonitor: KeyMonitor?
    var correctionEngine: CorrectionEngine?
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TypeFix Logs"
        window.center()
        
        let logVC = LogViewController()
        window.contentViewController = logVC
        logViewController = logVC
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        logViewController?.keyMonitor = keyMonitor
        logViewController?.correctionEngine = correctionEngine
    }
    
    func log(_ message: String, replaceLast: Bool = false) {
        logViewController?.log(message, replaceLast: replaceLast)
    }
}

final class LogViewController: NSViewController {
    
    var logTextView: NSTextView!
    
    var keyMonitor: KeyMonitor?
    var correctionEngine: CorrectionEngine?
    
    // Buffer to store logs before the view is loaded
    private var logBuffer: [String] = []
    private var isViewReady = false
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLogView()
        
        isViewReady = true
        flushLogBuffer()
    }
    
    private func setupLogView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.backgroundColor = .black
        textView.textColor = .white
        textView.isEditable = false
        
        scrollView.documentView = textView
        view.addSubview(scrollView)
        
        logTextView = textView
    }
    
    func log(_ message: String, replaceLast: Bool = false) {
        DispatchQueue.main.async {
            if self.isViewReady, let textView = self.logTextView {
                if replaceLast, let storage = textView.textStorage, storage.length > 0 {
                     // Find the range of the last line
                     let string = storage.string
                     var rangeToReplace = NSRange(location: 0, length: 0)
                     
                     if let lastNewlineRange = string.range(of: "\n", options: .backwards, range: string.startIndex..<string.index(before: string.endIndex)) {
                         let startIndex = lastNewlineRange.upperBound
                         rangeToReplace = NSRange(startIndex..<string.endIndex, in: string)
                     } else {
                         // Only one line exists
                         rangeToReplace = NSRange(location: 0, length: storage.length)
                     }
                     
                    let attributedMessage = NSAttributedString(
                        string: message + "\n",
                        attributes: [.foregroundColor: NSColor.white]
                    )
                    
                    storage.replaceCharacters(in: rangeToReplace, with: attributedMessage)
                } else {
                    let attributedString = NSAttributedString(
                        string: message + "\n",
                        attributes: [.foregroundColor: NSColor.white]
                    )
                    textView.textStorage?.append(attributedString)
                    textView.scrollToEndOfDocument(nil)
                }
            } else {
                if replaceLast && !self.logBuffer.isEmpty {
                    self.logBuffer.removeLast()
                }
                self.logBuffer.append(message)
            }
        }
    }
    
    private func flushLogBuffer() {
        guard let textView = logTextView else { return }
        
        for message in logBuffer {
            let attributedString = NSAttributedString(
                string: message + "\n",
                attributes: [.foregroundColor: NSColor.white]
            )
            textView.textStorage?.append(attributedString)
        }
        
        if !logBuffer.isEmpty {
            textView.scrollToEndOfDocument(nil)
            logBuffer.removeAll()
        }
    }
}


