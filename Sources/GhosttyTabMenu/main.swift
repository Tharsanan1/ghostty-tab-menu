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

struct SessionLink: Codable, Equatable {
    let title: String
    let url: String
}

struct SessionLinkPayload {
    let sessionName: String
    let link: SessionLink
}

struct PullRequestLink {
    let sessionName: String
    let url: String
}

struct PullRequestReview: Codable, Equatable {
    let author: PullRequestAuthor?
    let state: String?
    let submittedAt: String?
}

struct PullRequestAuthor: Codable, Equatable {
    let login: String?
}

struct PullRequestStatus: Codable, Equatable {
    let isDraft: Bool
    let latestReviews: [PullRequestReview]
    let mergedAt: String?
    let reviewDecision: String?
    let state: String
    let title: String
    let updatedAt: String
    let url: String

    var fingerprint: String {
        let reviewFingerprint = latestReviews
            .map { "\($0.author?.login ?? ""):\($0.state ?? ""):\($0.submittedAt ?? "")" }
            .joined(separator: "|")

        return [
            updatedAt,
            state,
            isDraft ? "draft" : "ready",
            mergedAt ?? "",
            reviewDecision ?? "",
            reviewFingerprint,
        ].joined(separator: "\t")
    }

    var displayName: String {
        guard let parsedURL = URL(string: url) else {
            return url
        }

        let parts = parsedURL.path.split(separator: "/")
        guard parts.count >= 4 else {
            return parsedURL.host ?? url
        }

        return "\(parts[0])/\(parts[1])#\(parts[3])"
    }
}

struct PullRequestSnapshot: Codable, Equatable {
    let fingerprint: String
    let reviewDecision: String?
    let state: String
    let title: String
    let updatedAt: String
}

struct PullRequestActivity: Codable, Equatable {
    let displayName: String
    let message: String
    let updatedAt: String
    let url: String
}

struct ScriptError: Error {
    let message: String
}

final class GhosttyTabMenuApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let pinnedNamesKey = "pinnedZellijSessionNames"
    private let sessionLinksKey = "zellijSessionLinks"
    private let prSnapshotsKey = "githubPRSnapshots"
    private let prActivitiesKey = "githubPRActivities"
    private var prPollTimer: Timer?
    private var isCheckingPullRequests = false
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

        startPullRequestPolling()
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
            let activities = loadActivities(for: session.name)
            let title = activities.isEmpty ? session.name : "\(session.name)  (\(activities.count) new)"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = sessionMenu(for: session.name)
            menu.addItem(item)
        }
    }

    private func sessionMenu(for sessionName: String) -> NSMenu {
        let submenu = NSMenu()
        let links = loadLinks(for: sessionName)
        let activities = loadActivities(for: sessionName)

        let focusItem = NSMenuItem(title: "Open / Focus Terminal", action: #selector(focusSession(_:)), keyEquivalent: "")
        focusItem.target = self
        focusItem.representedObject = sessionName
        submenu.addItem(focusItem)

        let openAllItem = NSMenuItem(title: "Open All Links in Chrome", action: #selector(openAllLinks(_:)), keyEquivalent: "")
        openAllItem.target = self
        openAllItem.representedObject = sessionName
        openAllItem.isEnabled = !links.isEmpty
        submenu.addItem(openAllItem)

        submenu.addItem(NSMenuItem.separator())

        if !activities.isEmpty {
            submenu.addItem(sectionItem("PR Activity"))
            for activity in activities {
                let link = SessionLink(title: activity.displayName, url: activity.url)
                let item = NSMenuItem(title: "\(activity.displayName) - \(activity.message)", action: #selector(openLink(_:)), keyEquivalent: "")
                item.target = self
                item.toolTip = activity.url
                item.representedObject = SessionLinkPayload(sessionName: sessionName, link: link)
                submenu.addItem(item)
            }

            let clearItem = NSMenuItem(title: "Clear PR Activity", action: #selector(clearSessionActivities(_:)), keyEquivalent: "")
            clearItem.target = self
            clearItem.representedObject = sessionName
            submenu.addItem(clearItem)
            submenu.addItem(NSMenuItem.separator())
        }

        if links.isEmpty {
            submenu.addItem(disabledItem("No links saved"))
        } else {
            submenu.addItem(sectionItem("Links"))
            for link in links {
                let item = NSMenuItem(title: link.title, action: #selector(openLink(_:)), keyEquivalent: "")
                item.target = self
                item.toolTip = link.url
                item.representedObject = SessionLinkPayload(sessionName: sessionName, link: link)
                submenu.addItem(item)
            }
        }

        submenu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: "Add Link from Clipboard", action: #selector(addLinkFromClipboard(_:)), keyEquivalent: "")
        addItem.target = self
        addItem.representedObject = sessionName
        submenu.addItem(addItem)

        let removeMenuItem = NSMenuItem(title: "Remove Link", action: nil, keyEquivalent: "")
        let removeSubmenu = NSMenu()
        if links.isEmpty {
            removeSubmenu.addItem(disabledItem("No links saved"))
        } else {
            for link in links {
                let item = NSMenuItem(title: link.title, action: #selector(removeLink(_:)), keyEquivalent: "")
                item.target = self
                item.toolTip = link.url
                item.representedObject = SessionLinkPayload(sessionName: sessionName, link: link)
                removeSubmenu.addItem(item)
            }
        }
        removeMenuItem.submenu = removeSubmenu
        submenu.addItem(removeMenuItem)

        return submenu
    }

    @objc private func openLink(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SessionLinkPayload else {
            return
        }

        openInChrome(payload.link.url)
        clearActivity(sessionName: payload.sessionName, url: payload.link.url)
        rebuildMenu()
    }

    @objc private func openAllLinks(_ sender: NSMenuItem) {
        guard let sessionName = sender.representedObject as? String else {
            return
        }

        for link in loadLinks(for: sessionName) {
            openInChrome(link.url)
        }
    }

    @objc private func addLinkFromClipboard(_ sender: NSMenuItem) {
        guard
            let sessionName = sender.representedObject as? String,
            let clipboardText = NSPasteboard.general.string(forType: .string)
        else {
            showError("Copy one or more http or https URLs first, then add them to the session.")
            return
        }

        let clipboardURLs = webURLs(from: clipboardText)
        guard !clipboardURLs.isEmpty else {
            showError("Copy one or more comma- or newline-separated http or https URLs first.")
            return
        }

        var linksBySession = loadAllLinks()
        var links = linksBySession[sessionName, default: []]
        let existingURLs = Set(links.map(\.url))
        var urlsToAdd: [URL] = []
        var seenURLs: Set<String> = []

        for url in clipboardURLs {
            guard !existingURLs.contains(url.absoluteString),
                  !seenURLs.contains(url.absoluteString)
            else {
                continue
            }

            seenURLs.insert(url.absoluteString)
            urlsToAdd.append(url)
        }

        guard !urlsToAdd.isEmpty else {
            showError("Those links are already saved for \"\(sessionName)\".")
            return
        }

        for url in urlsToAdd {
            links.append(SessionLink(title: titleForURL(url), url: url.absoluteString))
        }

        linksBySession[sessionName] = links
        saveAllLinks(linksBySession)
        rebuildMenu()
    }

    @objc private func removeLink(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? SessionLinkPayload else {
            return
        }

        var linksBySession = loadAllLinks()
        var links = linksBySession[payload.sessionName, default: []]
        links.removeAll { $0.url == payload.link.url }

        if links.isEmpty {
            linksBySession.removeValue(forKey: payload.sessionName)
        } else {
            linksBySession[payload.sessionName] = links
        }

        saveAllLinks(linksBySession)
        clearActivity(sessionName: payload.sessionName, url: payload.link.url)
        rebuildMenu()
    }

    @objc private func clearSessionActivities(_ sender: NSMenuItem) {
        guard let sessionName = sender.representedObject as? String else {
            return
        }

        var activities = loadAllActivities()
        activities.removeValue(forKey: sessionName)
        saveAllActivities(activities)
        rebuildMenu()
    }

    private func openInChrome(_ url: String) {
        let result = runCommand(executable: "/usr/bin/open", arguments: ["-a", "Google Chrome", url])
        if case let .failure(error) = result {
            showError(error.message)
        }
    }

    private func webURLs(from text: String) -> [URL] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .compactMap { token in
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    let url = URL(string: trimmed),
                    let scheme = url.scheme?.lowercased(),
                    scheme == "http" || scheme == "https",
                    url.host != nil
                else {
                    return nil
                }

                return url
            }
    }

    private func titleForURL(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if path.isEmpty {
            return host
        }

        return "\(host)/\(path)"
    }

    private func loadLinks(for sessionName: String) -> [SessionLink] {
        loadAllLinks()[sessionName, default: []]
    }

    private func loadAllLinks() -> [String: [SessionLink]] {
        guard let data = UserDefaults.standard.data(forKey: sessionLinksKey) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: [SessionLink]].self, from: data)) ?? [:]
    }

    private func saveAllLinks(_ linksBySession: [String: [SessionLink]]) {
        guard let data = try? JSONEncoder().encode(linksBySession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: sessionLinksKey)
    }

    private func loadActivities(for sessionName: String) -> [PullRequestActivity] {
        loadAllActivities()[sessionName, default: []].sorted {
            $0.updatedAt > $1.updatedAt
        }
    }

    private func loadAllActivities() -> [String: [PullRequestActivity]] {
        guard let data = UserDefaults.standard.data(forKey: prActivitiesKey) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: [PullRequestActivity]].self, from: data)) ?? [:]
    }

    private func saveAllActivities(_ activitiesBySession: [String: [PullRequestActivity]]) {
        guard let data = try? JSONEncoder().encode(activitiesBySession) else {
            return
        }

        UserDefaults.standard.set(data, forKey: prActivitiesKey)
    }

    private func saveActivity(sessionName: String, status: PullRequestStatus, message: String) {
        var activitiesBySession = loadAllActivities()
        var activities = activitiesBySession[sessionName, default: []]
        activities.removeAll { $0.url == status.url }
        activities.append(PullRequestActivity(
            displayName: status.displayName,
            message: message,
            updatedAt: status.updatedAt,
            url: status.url
        ))
        activitiesBySession[sessionName] = activities
        saveAllActivities(activitiesBySession)
    }

    private func clearActivity(sessionName: String, url: String) {
        var activitiesBySession = loadAllActivities()
        var activities = activitiesBySession[sessionName, default: []]
        activities.removeAll { $0.url == url }

        if activities.isEmpty {
            activitiesBySession.removeValue(forKey: sessionName)
        } else {
            activitiesBySession[sessionName] = activities
        }

        saveAllActivities(activitiesBySession)
    }

    private func startPullRequestPolling() {
        prPollTimer?.invalidate()
        prPollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkPullRequests()
        }

        checkPullRequests()
    }

    private func checkPullRequests() {
        guard !isCheckingPullRequests else {
            return
        }

        isCheckingPullRequests = true
        let pullRequestLinks = savedPullRequestLinks()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            var snapshots = self.loadPullRequestSnapshots()

            for pullRequestLink in pullRequestLinks {
                guard let status = self.loadPullRequestStatus(url: pullRequestLink.url) else {
                    continue
                }

                let key = self.snapshotKey(for: pullRequestLink)
                let oldSnapshot = snapshots[key]
                let newSnapshot = PullRequestSnapshot(
                    fingerprint: status.fingerprint,
                    reviewDecision: status.reviewDecision,
                    state: status.state,
                    title: status.title,
                    updatedAt: status.updatedAt
                )

                if let oldSnapshot,
                   oldSnapshot.fingerprint != newSnapshot.fingerprint {
                    let message = self.pullRequestChangeDescription(status: status, oldSnapshot: oldSnapshot)
                    self.saveActivity(sessionName: pullRequestLink.sessionName, status: status, message: message)
                    self.notifyPullRequestChanged(
                        sessionName: pullRequestLink.sessionName,
                        status: status,
                        message: message
                    )
                }

                snapshots[key] = newSnapshot
            }

            self.savePullRequestSnapshots(snapshots)

            DispatchQueue.main.async {
                self.isCheckingPullRequests = false
                self.rebuildMenu()
            }
        }
    }

    private func savedPullRequestLinks() -> [PullRequestLink] {
        loadAllLinks().flatMap { sessionName, links in
            links.compactMap { link in
                isGitHubPullRequestURL(link.url) ? PullRequestLink(sessionName: sessionName, url: link.url) : nil
            }
        }
    }

    private func isGitHubPullRequestURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              url.host?.lowercased() == "github.com"
        else {
            return false
        }

        let parts = url.path.split(separator: "/")
        return parts.count >= 4 && parts[2] == "pull" && Int(parts[3]) != nil
    }

    private func loadPullRequestStatus(url: String) -> PullRequestStatus? {
        let fields = "url,title,updatedAt,reviewDecision,state,isDraft,mergedAt,latestReviews"
        let command = "gh pr view \(shellQuoted(url)) --json \(fields)"
        let result = runCommand(executable: "/bin/zsh", arguments: ["-lc", command])

        guard case let .success(output) = result,
              let data = output.data(using: .utf8)
        else {
            return nil
        }

        return try? JSONDecoder().decode(PullRequestStatus.self, from: data)
    }

    private func notifyPullRequestChanged(
        sessionName: String,
        status: PullRequestStatus,
        message: String
    ) {
        displayNotification(
            title: sessionName,
            subtitle: "PR changed: \(status.displayName)",
            body: message
        )
    }

    private func pullRequestChangeDescription(
        status: PullRequestStatus,
        oldSnapshot: PullRequestSnapshot
    ) -> String {
        if oldSnapshot.state != status.state {
            return "State changed to \(status.state.lowercased())."
        }

        if oldSnapshot.reviewDecision != status.reviewDecision {
            let decision = status.reviewDecision?.isEmpty == false ? status.reviewDecision! : "review pending"
            return "Review status changed to \(decision.lowercased())."
        }

        if status.mergedAt != nil {
            return "PR was merged."
        }

        return "New PR activity: comment, review, commit, or metadata update."
    }

    private func snapshotKey(for pullRequestLink: PullRequestLink) -> String {
        "\(pullRequestLink.sessionName)\t\(pullRequestLink.url)"
    }

    private func loadPullRequestSnapshots() -> [String: PullRequestSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: prSnapshotsKey) else {
            return [:]
        }

        return (try? JSONDecoder().decode([String: PullRequestSnapshot].self, from: data)) ?? [:]
    }

    private func savePullRequestSnapshots(_ snapshots: [String: PullRequestSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }

        UserDefaults.standard.set(data, forKey: prSnapshotsKey)
    }

    private func displayNotification(title: String, subtitle: String, body: String) {
        let script = """
        on run argv
          display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv) sound name "Glass"
        end run
        """

        _ = runOsascript(script: script, arguments: [title, subtitle, body])
    }

    private func addRefreshAndQuit() {
        menu.addItem(NSMenuItem.separator())

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshMenu), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let checkPRsItem = NSMenuItem(title: "Check PRs Now", action: #selector(checkPullRequestsNow), keyEquivalent: "")
        checkPRsItem.target = self
        menu.addItem(checkPRsItem)

        let quitItem = NSMenuItem(title: "Quit Zellij Session Menu", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func refreshMenu() {
        rebuildMenu()
        statusItem.button?.performClick(nil)
    }

    @objc private func checkPullRequestsNow() {
        checkPullRequests()
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
