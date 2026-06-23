import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation

private let appName = "BitPaste"
private let bundleIdentifier = "app.bitpaste"
private let appSignature = makeOSType("BPST")
private let logLock = NSLock()

private struct RuntimeError: Error, CustomStringConvertible {
    let description: String
}

private struct FileConfig: Decodable {
    var chunkSize: Int?
    var delayMs: Int?
    var initialDelayMs: Int?
    var waitForShortcutReleaseMs: Int?
    var hotkey: String?
    var restoreClipboard: Bool?
}

private struct AppConfig {
    var chunkSize = 1_200
    var delayMs = 75
    var initialDelayMs = 120
    var waitForShortcutReleaseMs = 1_000
    var hotkey = "command+option+shift+v"
    var restoreClipboard = true
    var configPath = defaultConfigPath()

    mutating func apply(_ fileConfig: FileConfig) {
        if let chunkSize = fileConfig.chunkSize {
            self.chunkSize = chunkSize
        }
        if let delayMs = fileConfig.delayMs {
            self.delayMs = delayMs
        }
        if let initialDelayMs = fileConfig.initialDelayMs {
            self.initialDelayMs = initialDelayMs
        }
        if let waitForShortcutReleaseMs = fileConfig.waitForShortcutReleaseMs {
            self.waitForShortcutReleaseMs = waitForShortcutReleaseMs
        }
        if let hotkey = fileConfig.hotkey {
            self.hotkey = hotkey
        }
        if let restoreClipboard = fileConfig.restoreClipboard {
            self.restoreClipboard = restoreClipboard
        }
    }

    func validate() throws {
        guard chunkSize > 0 else {
            throw RuntimeError(description: "chunkSize must be greater than 0")
        }
        guard delayMs >= 0 else {
            throw RuntimeError(description: "delayMs must be 0 or greater")
        }
        guard initialDelayMs >= 0 else {
            throw RuntimeError(description: "initialDelayMs must be 0 or greater")
        }
        guard waitForShortcutReleaseMs >= 0 else {
            throw RuntimeError(description: "waitForShortcutReleaseMs must be 0 or greater")
        }
    }
}

private enum RuntimeMode {
    case run
    case help
    case printConfig
    case checkPermissions
}

private struct Hotkey {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let requiredReleaseFlags: [CGEventFlags]
    let label: String

    static func parse(_ rawValue: String) throws -> Hotkey {
        let tokens = rawValue
            .lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            throw RuntimeError(description: "hotkey cannot be empty")
        }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for token in tokens {
            switch token {
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "opt", "option", "alt":
                modifiers |= UInt32(optionKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                guard let carbonKeyCode = keyCodes[token] else {
                    throw RuntimeError(description: "unsupported hotkey key '\(token)'")
                }
                if keyCode != nil {
                    throw RuntimeError(description: "hotkey can only contain one non-modifier key")
                }
                keyCode = UInt32(carbonKeyCode)
            }
        }

        guard let keyCode else {
            throw RuntimeError(description: "hotkey must include a non-modifier key, like v")
        }

        return Hotkey(
            keyCode: keyCode,
            carbonModifiers: modifiers,
            requiredReleaseFlags: releaseFlags(fromCarbonModifiers: modifiers),
            label: tokens.joined(separator: "+")
        )
    }
}

private final class HotkeyMonitor {
    private let hotkey: Hotkey
    private let onPress: () -> Void
    private let hotKeyID = EventHotKeyID(signature: appSignature, id: 1)
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(hotkey: Hotkey, onPress: @escaping () -> Void) {
        self.hotkey = hotkey
        self.onPress = onPress
    }

    func start() throws {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let monitor = Unmanaged<HotkeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return monitor.handle(event)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            throw RuntimeError(description: "could not install hotkey handler (OSStatus \(handlerStatus))")
        }

        let registerStatus = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw RuntimeError(description: "could not register \(hotkey.label) (OSStatus \(registerStatus))")
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var pressedID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedID
        )

        guard status == noErr else {
            return status
        }

        if pressedID.signature == hotKeyID.signature && pressedID.id == hotKeyID.id {
            onPress()
        }

        return noErr
    }
}

private final class PasteController {
    private let config: AppConfig
    private let releaseFlags: [CGEventFlags]
    private let queue = DispatchQueue(label: "app.bitpaste.paste")
    private let lock = NSLock()
    private var pasteIsRunning = false

    init(config: AppConfig, hotkey: Hotkey) {
        self.config = config
        self.releaseFlags = hotkey.requiredReleaseFlags
    }

    func triggerPaste() {
        lock.lock()
        if pasteIsRunning {
            lock.unlock()
            log("Paste already running; ignoring hotkey.")
            NSSound.beep()
            return
        }
        pasteIsRunning = true
        lock.unlock()

        log("Hotkey pressed.")
        queue.async {
            defer {
                self.lock.lock()
                self.pasteIsRunning = false
                self.lock.unlock()
            }
            self.pasteClipboardInChunks()
        }
    }

    private func pasteClipboardInChunks() {
        let pasteboard = NSPasteboard.general

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            log("Clipboard does not contain text.")
            NSSound.beep()
            return
        }

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let chunks = split(text, maxCharacters: config.chunkSize)

        log("Pasting \(text.count) characters in \(chunks.count) chunks.")
        waitForShortcutRelease(timeoutMs: config.waitForShortcutReleaseMs)
        sleep(milliseconds: config.initialDelayMs)

        for chunk in chunks {
            pasteboard.clearContents()
            pasteboard.setString(chunk, forType: .string)
            sleep(milliseconds: 15)
            postCommandV()
            sleep(milliseconds: config.delayMs)
        }

        if config.restoreClipboard {
            sleep(milliseconds: config.delayMs)
            snapshot.restore(to: pasteboard)
        }

        log("Paste complete.")
    }

    private func waitForShortcutRelease(timeoutMs: Int) {
        guard timeoutMs > 0, !releaseFlags.isEmpty else {
            return
        }

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000.0)
        while Date() < deadline {
            let currentFlags = CGEventSource.flagsState(.hidSystemState)
            let stillHeld = releaseFlags.contains { currentFlags.contains($0) }
            if !stillHeld {
                return
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.005)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let capturedItems: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var capturedTypes: [NSPasteboard.PasteboardType: Data] = [:]

            for type in item.types {
                if let data = item.data(forType: type) {
                    capturedTypes[type] = data
                }
            }

            return capturedTypes
        } ?? []

        return PasteboardSnapshot(items: capturedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { capturedTypes in
            let item = NSPasteboardItem()
            for (type, data) in capturedTypes {
                item.setData(data, forType: type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}

private let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A,
    "b": kVK_ANSI_B,
    "c": kVK_ANSI_C,
    "d": kVK_ANSI_D,
    "e": kVK_ANSI_E,
    "f": kVK_ANSI_F,
    "g": kVK_ANSI_G,
    "h": kVK_ANSI_H,
    "i": kVK_ANSI_I,
    "j": kVK_ANSI_J,
    "k": kVK_ANSI_K,
    "l": kVK_ANSI_L,
    "m": kVK_ANSI_M,
    "n": kVK_ANSI_N,
    "o": kVK_ANSI_O,
    "p": kVK_ANSI_P,
    "q": kVK_ANSI_Q,
    "r": kVK_ANSI_R,
    "s": kVK_ANSI_S,
    "t": kVK_ANSI_T,
    "u": kVK_ANSI_U,
    "v": kVK_ANSI_V,
    "w": kVK_ANSI_W,
    "x": kVK_ANSI_X,
    "y": kVK_ANSI_Y,
    "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0,
    "1": kVK_ANSI_1,
    "2": kVK_ANSI_2,
    "3": kVK_ANSI_3,
    "4": kVK_ANSI_4,
    "5": kVK_ANSI_5,
    "6": kVK_ANSI_6,
    "7": kVK_ANSI_7,
    "8": kVK_ANSI_8,
    "9": kVK_ANSI_9,
    "space": kVK_Space,
    "tab": kVK_Tab,
    "return": kVK_Return,
    "enter": kVK_Return,
    "escape": kVK_Escape,
    "esc": kVK_Escape
]

private func makeOSType(_ fourCharacters: String) -> OSType {
    var result: UInt32 = 0
    for scalar in fourCharacters.unicodeScalars.prefix(4) {
        result = (result << 8) + scalar.value
    }
    return result
}

private func releaseFlags(fromCarbonModifiers modifiers: UInt32) -> [CGEventFlags] {
    var flags: [CGEventFlags] = []
    if modifiers & UInt32(cmdKey) != 0 {
        flags.append(.maskCommand)
    }
    if modifiers & UInt32(controlKey) != 0 {
        flags.append(.maskControl)
    }
    if modifiers & UInt32(optionKey) != 0 {
        flags.append(.maskAlternate)
    }
    if modifiers & UInt32(shiftKey) != 0 {
        flags.append(.maskShift)
    }
    return flags
}

private func defaultConfigPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/.config/bitpaste/config.json"
}

private func defaultConfigJSON(from config: AppConfig) -> String {
    """
    {
      "chunkSize": \(config.chunkSize),
      "delayMs": \(config.delayMs),
      "initialDelayMs": \(config.initialDelayMs),
      "waitForShortcutReleaseMs": \(config.waitForShortcutReleaseMs),
      "hotkey": "\(config.hotkey)",
      "restoreClipboard": \(config.restoreClipboard ? "true" : "false")
    }

    """
}

private func expandedPath(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

private func loadConfig(from path: String) throws -> FileConfig? {
    guard FileManager.default.fileExists(atPath: path) else {
        return nil
    }

    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(FileConfig.self, from: data)
}

private func ensureConfigFileExists(_ config: AppConfig) {
    guard !FileManager.default.fileExists(atPath: config.configPath) else {
        return
    }

    do {
        let url = URL(fileURLWithPath: config.configPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try defaultConfigJSON(from: config).write(to: url, atomically: true, encoding: .utf8)
        log("Created default config at \(config.configPath).")
    } catch {
        log("Could not create config at \(config.configPath): \(error)")
    }
}

private func requestedConfigPath(from args: [String]) throws -> String? {
    var index = 0
    while index < args.count {
        if args[index] == "--config" {
            guard index + 1 < args.count else {
                throw RuntimeError(description: "--config requires a path")
            }
            return expandedPath(args[index + 1])
        }
        index += 1
    }
    return nil
}

private func parseArguments(_ args: [String], config: inout AppConfig) throws -> RuntimeMode {
    var mode = RuntimeMode.run
    var index = 0

    while index < args.count {
        let arg = args[index]

        func nextValue() throws -> String {
            guard index + 1 < args.count else {
                throw RuntimeError(description: "\(arg) requires a value")
            }
            index += 1
            return args[index]
        }

        switch arg {
        case "--help", "-h":
            mode = .help
        case "--print-config":
            mode = .printConfig
        case "--check-permissions":
            mode = .checkPermissions
        case "--config":
            config.configPath = expandedPath(try nextValue())
        case "--chunk-size":
            guard let value = Int(try nextValue()) else {
                throw RuntimeError(description: "--chunk-size must be an integer")
            }
            config.chunkSize = value
        case "--delay-ms":
            guard let value = Int(try nextValue()) else {
                throw RuntimeError(description: "--delay-ms must be an integer")
            }
            config.delayMs = value
        case "--initial-delay-ms":
            guard let value = Int(try nextValue()) else {
                throw RuntimeError(description: "--initial-delay-ms must be an integer")
            }
            config.initialDelayMs = value
        case "--wait-release-ms":
            guard let value = Int(try nextValue()) else {
                throw RuntimeError(description: "--wait-release-ms must be an integer")
            }
            config.waitForShortcutReleaseMs = value
        case "--hotkey":
            config.hotkey = try nextValue()
        case "--restore":
            config.restoreClipboard = true
        case "--no-restore":
            config.restoreClipboard = false
        default:
            throw RuntimeError(description: "unknown argument \(arg)")
        }

        index += 1
    }

    return mode
}

private func requestAccessibilityPermission(prompt: Bool) -> Bool {
    let options = [
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

private func ensureLoginAgentForCurrentApp() {
    let bundleURL = Bundle.main.bundleURL
    guard bundleURL.pathExtension == "app" else {
        return
    }

    let appPath = bundleURL.path
    let homeApplications = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications", isDirectory: true)
        .path

    guard appPath.hasPrefix("/Applications/") || appPath.hasPrefix(homeApplications + "/") else {
        log("Drag BitPaste.app to Applications, then open it once to install the login item.")
        return
    }

    let launchAgentsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    let plistURL = launchAgentsURL.appendingPathComponent("\(bundleIdentifier).plist")
    let logDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BitPaste", isDirectory: true)

    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(bundleIdentifier)</string>
      <key>ProgramArguments</key>
      <array>
        <string>/usr/bin/open</string>
        <string>-gj</string>
        <string>\(xmlEscaped(appPath))</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>StandardOutPath</key>
      <string>\(xmlEscaped(logDirectory.appendingPathComponent("bitpaste.log").path))</string>
      <key>StandardErrorPath</key>
      <string>\(xmlEscaped(logDirectory.appendingPathComponent("bitpaste.err.log").path))</string>
      <key>ProcessType</key>
      <string>Interactive</string>
    </dict>
    </plist>

    """

    do {
        try FileManager.default.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let existing = try? String(contentsOf: plistURL, encoding: .utf8)
        let launchAgentIsLoaded = processExitCode("/bin/launchctl", ["print", "gui/\(getuid())/\(bundleIdentifier)"]) == 0

        guard existing != plist || !launchAgentIsLoaded else {
            return
        }

        try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        _ = processExitCode("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path])
        let status = processExitCode("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        if status == 0 {
            log("Installed login item at \(plistURL.path).")
        } else {
            log("Could not bootstrap login item at \(plistURL.path) (exit \(status)).")
        }
    } catch {
        log("Could not install login item: \(error)")
    }
}

private func split(_ text: String, maxCharacters: Int) -> [String] {
    var chunks: [String] = []
    var start = text.startIndex

    while start < text.endIndex {
        let end = text.index(start, offsetBy: maxCharacters, limitedBy: text.endIndex) ?? text.endIndex
        chunks.append(String(text[start..<end]))
        start = end
    }

    return chunks
}

private func sleep(milliseconds: Int) {
    guard milliseconds > 0 else {
        return
    }
    Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000.0)
}

private func xmlEscaped(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}

private func processExitCode(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 127
    }
}

private func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(appName): \(message)\n"
    fputs(line, stderr)

    logLock.lock()
    defer {
        logLock.unlock()
    }

    let logDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BitPaste", isDirectory: true)
    let logFile = logDirectory.appendingPathComponent("bitpaste.err.log")

    do {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logFile)
        try handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
        try handle.close()
    } catch {
        // stderr is still available when file logging fails.
    }
}

private func printHelp() {
    print(
        """
        \(appName) pastes the current clipboard text in small chunks.

        Default hotkey:
          command+option+shift+v

        Options:
          --config PATH                 Config file path. Default: ~/.config/bitpaste/config.json
          --hotkey HOTKEY               Example: command+option+shift+v
          --chunk-size N                Characters per paste chunk. Default: 1200
          --delay-ms N                  Delay after each chunk paste. Default: 75
          --initial-delay-ms N          Delay before the first chunk. Default: 120
          --wait-release-ms N           Max time to wait for hotkey release. Default: 1000
          --no-restore                  Leave the last chunk on the clipboard
          --restore                     Restore the original clipboard after paste
          --check-permissions           Prompt/check macOS Accessibility permission
          --print-config                Print the effective config and exit
          --help                        Show this help
        """
    )
}

private func printConfig(_ config: AppConfig) throws {
    let payload: [String: Any] = [
        "chunkSize": config.chunkSize,
        "delayMs": config.delayMs,
        "initialDelayMs": config.initialDelayMs,
        "waitForShortcutReleaseMs": config.waitForShortcutReleaseMs,
        "hotkey": config.hotkey,
        "restoreClipboard": config.restoreClipboard,
        "configPath": config.configPath
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8) ?? "{}")
}

private func run() throws {
    var config = AppConfig()
    if let explicitConfigPath = try requestedConfigPath(from: Array(CommandLine.arguments.dropFirst())) {
        config.configPath = explicitConfigPath
    }
    if let fileConfig = try loadConfig(from: config.configPath) {
        config.apply(fileConfig)
    }

    let mode = try parseArguments(Array(CommandLine.arguments.dropFirst()), config: &config)
    try config.validate()

    switch mode {
    case .help:
        printHelp()
    case .printConfig:
        try printConfig(config)
    case .checkPermissions:
        let trusted = requestAccessibilityPermission(prompt: true)
        if trusted {
            print("\(appName) has Accessibility permission.")
        } else {
            print("\(appName) does not have Accessibility permission yet.")
            exit(2)
        }
    case .run:
        ensureConfigFileExists(config)
        ensureLoginAgentForCurrentApp()

        let hotkey = try Hotkey.parse(config.hotkey)
        let controller = PasteController(config: config, hotkey: hotkey)
        let monitor = HotkeyMonitor(hotkey: hotkey) {
            controller.triggerPaste()
        }

        try monitor.start()

        let trusted = requestAccessibilityPermission(prompt: true)
        if !trusted {
            log("Accessibility permission is required before BitPaste can send paste keystrokes.")
        }

        log("Running. Press \(hotkey.label) to paste clipboard text in chunks.")
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.run()
    }
}

do {
    try run()
} catch {
    fputs("\(appName): \(error)\n", stderr)
    exit(1)
}
