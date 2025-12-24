//
//  APIKeyWindowController.swift
//  TypeFixPrototype
//
//  Manages the window and dialog for entering the OpenAI API key.
//  Provides a secure text field for the user to input their API key,
//  with options to save or cancel.
//

import Cocoa

final class APIKeyWindowController: NSWindowController {
    
    private var apiKeyViewController: APIKeyViewController?
    
    var onAPIKeySaved: (() -> Void)?
    var onAPIKeyDeleted: (() -> Void)?
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenAI API Key"
        window.center()
        window.isMovableByWindowBackground = true
        
        let viewController = APIKeyViewController()
        window.contentViewController = viewController
        
        super.init(window: window)
        
        apiKeyViewController = viewController
        viewController.onSave = { [weak self] in
            self?.onAPIKeySaved?()
            self?.close()
        }
        viewController.onDelete = { [weak self] in
            self?.onAPIKeyDeleted?()
            self?.close()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class APIKeyViewController: NSViewController {
    
    private var apiKeyTextField: NSSecureTextField!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!
    private var deleteButton: NSButton!
    private var statusLabel: NSTextField!
    
    var onSave: (() -> Void)?
    var onDelete: (() -> Void)?
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 240))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadExistingKey()
    }
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        let titleLabel = NSTextField(labelWithString: "Enter your OpenAI API Key")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        let descriptionLabel = NSTextField(wrappingLabelWithString: "Your API key will be stored securely in macOS Keychain. You can get your key from https://platform.openai.com/api-keys")
        descriptionLabel.font = NSFont.systemFont(ofSize: 12)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionLabel)
        
        apiKeyTextField = NSSecureTextField()
        apiKeyTextField.placeholderString = "sk-..."
        apiKeyTextField.font = NSFont.systemFont(ofSize: 13)
        apiKeyTextField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(apiKeyTextField)
        
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isHidden = true
        view.addSubview(statusLabel)
        
        saveButton = NSButton(title: "Save", target: self, action: #selector(saveAPIKey))
        saveButton.bezelStyle = .rounded
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveButton)
        
        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        
        deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteAPIKey))
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.isHidden = !KeychainManager.hasAPIKey()
        deleteButton.contentTintColor = .systemRed
        view.addSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            apiKeyTextField.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            apiKeyTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            apiKeyTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            apiKeyTextField.heightAnchor.constraint(equalToConstant: 24),
            
            statusLabel.topAnchor.constraint(equalTo: apiKeyTextField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            saveButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            saveButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            saveButton.widthAnchor.constraint(equalToConstant: 80),
            
            cancelButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cancelButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 80),
            
            deleteButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            deleteButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            deleteButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            deleteButton.widthAnchor.constraint(equalToConstant: 80)
        ])
        
        apiKeyTextField.target = self
        apiKeyTextField.action = #selector(saveAPIKey)
    }
    
    private func loadExistingKey() {
        if KeychainManager.hasAPIKey() {
            apiKeyTextField.placeholderString = "Enter new key to replace existing one"
            deleteButton.isHidden = false
        }
    }
    
    @objc private func deleteAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Delete API Key?"
        alert.informativeText = "Are you sure you want to delete your saved API key? You will need to add it again to use correction features."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        if alert.runModal() == .alertFirstButtonReturn {
            if KeychainManager.deleteAPIKey() {
                showStatus("API key deleted successfully", isError: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.onDelete?()
                }
            } else {
                showStatus("Failed to delete API key", isError: true)
            }
        }
    }
    
    @objc private func saveAPIKey() {
        let apiKey = apiKeyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !apiKey.isEmpty else {
            showStatus("Please enter an API key", isError: true)
            return
        }
        
        if !apiKey.hasPrefix("sk-") {
            showStatus("Warning: API key doesn't start with 'sk-'. Make sure it's correct.", isError: false)
        }
        
        if KeychainManager.saveAPIKey(apiKey) {
            showStatus("API key saved successfully!", isError: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.onSave?()
            }
        } else {
            showStatus("Failed to save API key. Please try again.", isError: true)
        }
    }
    
    @objc private func cancel() {
        view.window?.close()
    }
    
    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.stringValue = message
        statusLabel.textColor = isError ? .systemRed : .systemGreen
        statusLabel.isHidden = false
        
        if !isError {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.statusLabel.isHidden = true
            }
        }
    }
}

