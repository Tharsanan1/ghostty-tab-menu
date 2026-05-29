import AppKit
import Foundation

struct GhosttyTab: Equatable {
    let windowId: String
    let tabIndex: Int
    let name: String
}

struct ZellijSession: Equatable {
    let name: String
    let isExited: Bool
}

struct ScriptError: Error {
    let message: String
}

final class GhosttyTabMenuApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pinnedNamesKey = "pinnedZellijSessionNames"
    private var currentTabs: [GhosttyTab] = []
    private var currentSessions: [ZellijSession] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
            button.toolTip = "Zellij sessions"
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    private static func makeMenuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18))
        image.lockFocus()

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outline = NSBezierPath()
        outline.lineWidth = 1.8
        outline.lineCapStyle = .round
        outline.lineJoinStyle = .round
        outline.move(to: NSPoint(x: 5, y: 4.5))
        outline.line(to: NSPoint(x: 5, y: 11))
        outline.curve(
            to: NSPoint(x: 17, y: 11),
            controlPoint1: NSPoint(x: 5, y: 16),
            controlPoint2: NSPoint(x: 17, y: 16)
        )
        outline.line(to: NSPoint(x: 17, y: 4.5))
        outline.line(to: NSPoint(x: 14.6, y: 6.1))
        outline.line(to: NSPoint(x: 12.2, y: 4.5))
        outline.line(to: NSPoint(x: 9.8, y: 6.1))
        outline.line(to: NSPoint(x: 7.4, y: 4.5))
        outline.line(to: NSPoint(x: 5, y: 4.5))
        outline.stroke()

        let prompt = NSBezierPath()
        prompt.lineWidth = 1.55
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.move(to: NSPoint(x: 7.9, y: 10.7))
        prompt.line(to: NSPoint(x: 10.2, y: 9))
        prompt.line(to: NSPoint(x: 7.9, y: 7.3))
        prompt.stroke()

        let cursor = NSBezierPath()
        cursor.lineWidth = 1.55
        cursor.lineCapStyle = .round
        cursor.move(to: NSPoint(x: 11.6, y: 7.4))
        cursor.line(to: NSPoint(x: 14.3, y: 7.4))
        cursor.stroke()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Zellij sessions"
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        currentSessions = loadZellijSessions()
        currentTabs = loadGhosttyTabs()

        guard !currentSessions.isEmpty else {
            menu.addItem(disabledItem("No Zellij sessions found"))
            menu.addItem(NSMenuItem.separator())
            addRefreshAndQuit()
            return
        }

        let pinnedNames = loadPinnedNames()
        let pinnedSessions = currentSessions.filter { pinnedNames.contains($0.name) }

        if !pinnedSessions.isEmpty {
            menu.addItem(sectionItem("Pinned"))
            addFocusItems(for: pinnedSessions)
            menu.addItem(NSMenuItem.separator())
        }

        menu.addItem(sectionItem("Zellij Sessions"))
        addFocusItems(for: currentSessions)
        menu.addItem(NSMenuItem.separator())

        let pinMenuItem = NSMenuItem(title: "Pin / Unpin Sessions", action: nil, keyEquivalent: "")
        let pinSubmenu = NSMenu()
        for name in uniqueSessionNames(currentSessions) {
            let item = NSMenuItem(title: name, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = pinnedNames.contains(name) ? .on : .off
            pinSubmenu.addItem(item)
        }
        pinMenuItem.submenu = pinSubmenu
        menu.addItem(pinMenuItem)

        addRefreshAndQuit()
    }

    private func addFocusItems(for sessions: [ZellijSession]) {
        for session in sessions {
            let item = NSMenuItem(title: session.name, action: #selector(focusSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session.name
            menu.addItem(item)
        }
    }

    private func addRefreshAndQuit() {
        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let quitItem = NSMenuItem(title: "Quit Zellij Session Menu", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func refreshMenu() {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        var pinnedNames = loadPinnedNames()

        if pinnedNames.contains(name) {
            pinnedNames.removeAll { $0 == name }
        } else {
            pinnedNames.append(name)
            pinnedNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        savePinnedNames(pinnedNames)
        rebuildMenu()
    }

    @objc private func focusSession(_ sender: NSMenuItem) {
        guard let sessionName = sender.representedObject as? String else {
            return
        }

        currentTabs = loadGhosttyTabs()
        if let tab = currentTabs.first(where: { tabMatchesSession($0, sessionName: sessionName) }) {
            focusTab(tab)
        } else {
            openTab(for: sessionName)
        }
    }

    private func focusTab(_ tab: GhosttyTab) {
        let result = runOsascript(script: Self.focusTabScript, arguments: [tab.windowId, String(tab.tabIndex)])
        if case let .failure(error) = result {
            showError(error.message)
        }
    }

    private func openTab(for sessionName: String) {
        let attachCommand = "exec zellij attach -- \(shellQuoted(sessionName))"

        let script = """
        on run argv
          set attachCommand to item 1 of argv

          tell application "Ghostty"
            activate
            set cfg to new surface configuration
            set initial input of cfg to attachCommand & linefeed

            if (count of windows) is 0 then
              set targetWindow to new window with configuration cfg
              set targetTab to selected tab of targetWindow
            else
              set targetWindow to front window
              set targetTab to new tab in targetWindow with configuration cfg
            end if

            activate window targetWindow
            select tab targetTab
            focus focused terminal of targetTab
          end tell
        end run
        """

        let result = runOsascript(script: script, arguments: [attachCommand])
        if case let .failure(error) = result {
            showError(error.message)
        }
    }

    private func loadZellijSessions() -> [ZellijSession] {
        let result = runCommand(
            executable: "/bin/zsh",
            arguments: ["-lc", "zellij list-sessions --no-formatting"]
        )

        switch result {
        case .success(let output):
            return parseZellijSessions(output).filter { !$0.isExited }
        case .failure:
            return []
        }
    }

    private func parseZellijSessions(_ output: String) -> [ZellijSession] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let text = String(line)
                guard let createdRange = text.range(of: " [Created ") else {
                    return nil
                }

                let name = String(text[..<createdRange.lowerBound])
                return ZellijSession(name: name, isExited: text.contains("(EXITED"))
            }
    }

    private func loadGhosttyTabs() -> [GhosttyTab] {
        let script = #"""
        set oldDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to linefeed

        tell application "Ghostty"
          set tabRows to {}

          repeat with w in windows
            set windowId to id of w as text
            repeat with i from 1 to count of tabs of w
              set t to tab i of w
              set tabName to name of t as text
              set end of tabRows to windowId & "\t" & (i as text) & "\t" & tabName
            end repeat
          end repeat
        end tell

        set output to tabRows as text
        set AppleScript's text item delimiters to oldDelimiters
        return output
        """#

        let result = runOsascript(script: script, arguments: [])
        switch result {
        case .success(let output):
            return parseTabs(output)
        case .failure:
            return []
        }
    }

    private func parseTabs(_ output: String) -> [GhosttyTab] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3,
                      let tabIndex = Int(parts[1])
                else {
                    return nil
                }
                return GhosttyTab(windowId: String(parts[0]), tabIndex: tabIndex, name: String(parts[2]))
            }
    }

    private func tabMatchesSession(_ tab: GhosttyTab, sessionName: String) -> Bool {
        let title = tab.name

        if title.compare(sessionName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return true
        }

        guard let regex = try? NSRegularExpression(
            pattern: "(^|[^A-Za-z0-9_.-])\(NSRegularExpression.escapedPattern(for: sessionName))($|[^A-Za-z0-9_.-])",
            options: [.caseInsensitive]
        ) else {
            return false
        }

        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return regex.firstMatch(in: title, range: range) != nil
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static let focusTabScript = """
    on run argv
      set targetWindowId to item 1 of argv
      set targetTabIndex to (item 2 of argv) as integer

      tell application "Ghostty"
        activate

        repeat with w in windows
          if (id of w as text) is targetWindowId then
            set targetTab to tab targetTabIndex of w
            activate window w
            select tab targetTab
            focus focused terminal of targetTab
            return
          end if
        end repeat

        error "No Ghostty tab found for window " & targetWindowId & ", tab " & targetTabIndex
      end tell
    end run
    """

    private func runOsascript(script: String, arguments: [String]) -> Result<String, ScriptError> {
        runCommand(executable: "/usr/bin/osascript", arguments: ["-e", script] + arguments)
    }

    private func runCommand(executable: String, arguments: [String]) -> Result<String, ScriptError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(ScriptError(message: error.localizedDescription))
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            return .success(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(ScriptError(message: message.isEmpty ? "\(executable) failed with status \(process.terminationStatus)" : message))
    }

    private func loadPinnedNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: pinnedNamesKey) ?? []
    }

    private func savePinnedNames(_ names: [String]) {
        UserDefaults.standard.set(names, forKey: pinnedNamesKey)
    }

    private func uniqueSessionNames(_ sessions: [ZellijSession]) -> [String] {
        Array(Set(sessions.map(\.name))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private func sectionItem(_ title: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Zellij Session Menu"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = GhosttyTabMenuApp()
app.delegate = delegate
app.run()
