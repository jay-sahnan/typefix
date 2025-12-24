//
//  AppDelegate.swift
//  TypeFixPrototype
//
//  Application delegate that manages the app lifecycle and initializes
//  the status bar controller. This app runs as a menu bar accessory with
//  no dock icon.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        
        if let emojiImage = createEmojiImage("✨", size: 512) {
            NSApp.applicationIconImage = emojiImage
        }
        
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func createEmojiImage(_ emoji: String, size: CGFloat) -> NSImage? {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        
        let font = NSFont.systemFont(ofSize: size * 0.8)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = attributedString.size()
        let point = NSPoint(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2
        )
        
        attributedString.draw(at: point)
        image.unlockFocus()
        
        return image
    }

    func applicationWillTerminate(_ notification: Notification) {
    }
}
