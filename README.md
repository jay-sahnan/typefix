# TypeFix

AI-powered real-time text correction for macOS. TypeFix monitors your typing across all applications and provides intelligent grammar, spelling, and fact-checking corrections using OpenAI's API.

## Disclaimer
I cannot code in Swift, so I relied heavily on AI agents to help me write this code.

## Features

- **Basic Correction**: Fixes grammar and spelling errors in real-time
- **Fact Checking**: Verifies factual accuracy of your text
- **System-Wide**: Works across all applications on macOS
- **Menu Bar App**: Runs quietly in the background with a menu bar icon
- **Floating Button**: Appears when you pause typing, allowing you to correct text on demand

## Installation

1. Clone this repository
2. Open `TypeFixPrototype.xcodeproj` in Xcode
3. Build and run the project

## Setup

1. **Grant Permissions**: When you first launch TypeFix, you'll be prompted to grant:
   - **Accessibility** permission (required to detect and replace text)
   - **Input Monitoring** permission (required to monitor keystrokes)

2. **Add API Key**: 
   - Click the menu bar icon (text cursor symbol)
   - Select "Add OpenAI API Key"
   - Enter your API key from [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
   - Your key is stored securely in macOS Keychain

3. **Start Typing**: Type anywhere! When you pause, click the ✨ button that appears to correct your text.

## Usage

- **Correction Modes**: Toggle between "Basic" (grammar/spelling) and "Fact Checking" (includes factual verification) from the menu bar
- **Selected Text**: Select text in any app and the correction button will appear near your selection
- **Logs**: View detailed logs by selecting "Show Logs" from the menu bar

## Privacy

- Your API key is stored securely in macOS Keychain
- Text is sent to OpenAI's API for correction (check OpenAI's privacy policy)
- No text is stored locally beyond what's needed for the correction process

## Known Bugs

- **Browser Compatibility**: Text replacement may be unreliable in some web browsers (Chrome, Safari, Firefox). The app uses clipboard paste as a fallback, which may not preserve formatting.
- **Accessibility API Limitations**: Some applications may not fully support the Accessibility API, causing text replacement to fail. The app falls back to keyboard simulation in these cases.
- **Text Replacement Verification**: Occasionally, text replacement may fail verification and require manual correction.
- **System Autocorrect**: TypeFix disables macOS's built-in autocorrect system-wide while running. This may affect other applications that rely on system autocorrect.
- **Network Errors**: No retry mechanism for failed API requests. Network interruptions will cause corrections to fail.

## Future

- **Better Browser Support**: Improve text replacement reliability in web browsers
- **Retry Logic**: Implement automatic retry for failed API requests
- **Local Model**: Use a local LLM instead of calling Open AI