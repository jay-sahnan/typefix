//
//  ViewController.swift
//  TypeFixPrototype
//
//  Minimal view controller for the main window. Since this app primarily
//  operates as a menu bar accessory, this view controller is kept minimal
//  for compatibility with the storyboard.
//

import Cocoa

class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWelcomeView()
    }
    
    private func setupWelcomeView() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.distribution = .fill
        stackView.spacing = 16
        stackView.edgeInsets = NSEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
        
        let titleLabel = NSTextField(labelWithString: "TypeFix")
        titleLabel.font = NSFont.systemFont(ofSize: 32, weight: .bold)
        titleLabel.textColor = .labelColor
        stackView.addArrangedSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "AI-Powered Real-Time Text Correction")
        subtitleLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(subtitleLabel)
        
        stackView.addArrangedSubview(NSBox.separator())
        
        let startTitle = createSectionTitle("Quick Start")
        stackView.addArrangedSubview(startTitle)
        
        let startText = createBodyText("""
        1. Grant **Accessibility** & **Input Monitoring** permissions when prompted.
        2. Add your **OpenAI API Key** via the menu bar icon (text cursor symbol).
        3. Type anywhere! When you pause, click the ✨ button to correct text.
        """)
        stackView.addArrangedSubview(startText)
        
        stackView.addArrangedSubview(NSBox.separator())
        
        let featuresTitle = createSectionTitle("Features")
        stackView.addArrangedSubview(featuresTitle)
        
        let featuresText = createBodyText("""
        • **Basic**: Fixes grammar and spelling
        • **Fact Checking**: Verifies factual accuracy
        """)
        stackView.addArrangedSubview(featuresText)
        
        stackView.addArrangedSubview(NSBox.separator())
        
        let contributeTitle = createSectionTitle("Open Source")
        stackView.addArrangedSubview(contributeTitle)
        
        let contributeText = createBodyText("Visit github.com/yourusername/TypeFixPrototype to contribute or report bugs.")
        stackView.addArrangedSubview(contributeText)
        
        stackView.addArrangedSubview(NSBox.separator())
        
        let noteLabel = NSTextField(labelWithString: "💡 Tip: You can close this window. The app runs in the menu bar.")
        noteLabel.font = NSFont.systemFont(ofSize: 12)
        noteLabel.textColor = .tertiaryLabelColor
        stackView.addArrangedSubview(noteLabel)
        
        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            stackView.widthAnchor.constraint(equalToConstant: 500)
        ])
        
        scrollView.documentView = contentView
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func createSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .labelColor
        return label
    }
    
    private func createBodyText(_ text: String) -> NSTextField {
        let textField = NSTextField(wrappingLabelWithString: text)
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.textColor = .labelColor
        textField.preferredMaxLayoutWidth = 440
        return textField
    }
}

extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }
}
