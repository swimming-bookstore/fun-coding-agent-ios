import Foundation
import UIKit

struct ChatSession: Identifiable {
    var id: String { path }
    let path: String
    let title: String
    let preview: String
}

@MainActor
final class FunViewModel: ObservableObject {
    @Published var snapshot = Snapshot(
        title: "Fun",
        usage: "0.0% of 500k",
        usageTip: "0 / 500000 last prompt tokens",
        working: false,
        loggedIn: false,
        empty: true,
        emptyNote: "Log in to Grok to start a chat.",
        thinking: "",
        steer: "",
        steerCount: "",
        rooms: [],
        items: [],
        queue: [],
        login: nil,
        toast: ""
    )
    @Published var draft: String = ""
    @Published var chats: [ChatSession] = []
    @Published private(set) var currentChatPath: String?

    private var app: FunApp?
    private var bridge: DelegateBridge?
    private var lastOpenedCode = ""
    private var home = URL(fileURLWithPath: "/")
    private var workspacePath = ""
    private var wasWorking = false

    func start() {
        guard app == nil else { return }
        let home = dataRoot()
        let workspace = home.appendingPathComponent("workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        self.home = home
        workspacePath = workspace.path
        setenv("HOME", home.path, 1)
        setenv("XDG_CONFIG_HOME", home.appendingPathComponent(".config").path, 1)
        setenv("XDG_DATA_HOME", home.appendingPathComponent(".local/share").path, 1)
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let extra = "/usr/bin:/bin:/usr/sbin:/sbin"
        setenv("PATH", path.isEmpty ? extra : "\(path):\(extra)", 1)
        let app = FunApp()
        let bridge = DelegateBridge(owner: self)
        self.app = app
        self.bridge = bridge
        app.start(delegate: bridge)
        app.addFolder(workspace: workspace.path)
        app.openRoom(workspace: workspace.path)
        reloadChats()
        currentChatPath = chats.first?.path
    }

    var currentTitle: String {
        if let title = chats.first(where: { $0.path == currentChatPath })?.title, !title.isEmpty {
            return title
        }
        return snapshot.title.isEmpty ? "Fun" : snapshot.title
    }

    /// Simulator reinstalls wipe the sandbox; keep data on the host Mac.
    /// Device builds stay in Application Support.
    private func dataRoot() -> URL {
        #if targetEnvironment(simulator)
        let macHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"]
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? NSHomeDirectory()
        let home = URL(fileURLWithPath: macHome, isDirectory: true)
            .appendingPathComponent(".local/share/fun-ios", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
        #else
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support")
        let home = support.appendingPathComponent("fun", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
        #endif
    }

    func stop() {
        app?.shutdown()
        app = nil
        bridge = nil
    }

    func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        app?.submit(text: text)
    }

    func interrupt() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        app?.interrupt(text: text)
    }

    func abort() { app?.abort() }
    func newChat() {
        let known = Set(chats.map(\.path))
        app?.newChat()
        reloadChats()
        currentChatPath = chats.first { !known.contains($0.path) }?.path
    }
    func loginGrok() { app?.loginGrok() }
    func logoutGrok() { app?.logoutGrok() }
    func dismissLogin() { app?.dismissLogin() }
    func dismissToast() { app?.dismissToast() }

    func queueSendNow(_ i: UInt32) { app?.queueSendNow(index: i) }
    func queueDrop(_ i: UInt32) { app?.queueDrop(index: i) }
    func queueMove(_ i: UInt32, delta: Int32) { app?.queueMove(index: i, delta: delta) }
    func queueEdit(_ i: UInt32) {
        guard let text = app?.queueEdit(index: i), !text.isEmpty else { return }
        let cur = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = cur.isEmpty ? text : "\(cur)\n\(text)"
    }

    func reloadChats() {
        chats = ChatStore.load(home: home, workspace: workspacePath)
    }

    func openChat(_ path: String) {
        guard path != currentChatPath else { return }
        // Core loads the newest session in the workspace; bump mtime and re-add the folder.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
        currentChatPath = path
        reopenWorkspace()
        reloadChats()
    }

    func removeChat(_ path: String) {
        let wasCurrent = path == currentChatPath
        try? FileManager.default.removeItem(atPath: path)
        if wasCurrent {
            if let next = ChatStore.load(home: home, workspace: workspacePath).first {
                openChat(next.path)
            } else {
                newChat()
            }
        } else {
            reloadChats()
        }
    }

    private func reopenWorkspace() {
        guard !workspacePath.isEmpty else { return }
        app?.removeFolder()
        app?.addFolder(workspace: workspacePath)
    }

    fileprivate func handleSnapshot(_ snap: Snapshot) {
        let finished = wasWorking && !snap.working
        wasWorking = snap.working
        snapshot = snap
        if finished {
            reloadChats()
            if currentChatPath == nil {
                currentChatPath = chats.first?.path
            }
        }
        if let login = snap.login, !login.openUrl.isEmpty, login.userCode != lastOpenedCode {
            lastOpenedCode = login.userCode
            if let url = URL(string: login.openUrl) {
                UIApplication.shared.open(url)
            }
        }
        if snap.login == nil { lastOpenedCode = "" }
    }
}

private enum ChatStore {
    static func load(home: URL, workspace: String) -> [ChatSession] {
        guard !workspace.isEmpty else { return [] }
        return jsonlFiles(in: sessionsDir(home: home, workspace: workspace)).map { url in
            let parsed = parse(url)
            return ChatSession(path: url.path, title: parsed.title, preview: parsed.preview)
        }
    }

    private static func sessionsDir(home: URL, workspace: String) -> URL {
        home
            .appendingPathComponent(".local/share/fun/sessions", isDirectory: true)
            .appendingPathComponent(folderName(workspace), isDirectory: true)
    }

    /// Matches fun-core session directory names.
    private static func folderName(_ cwd: String) -> String {
        let trimmed = cwd.drop(while: { $0 == "/" || $0 == "\\" })
        let safe = String(trimmed).map { ch -> Character in
            if ch == "/" || ch == "\\" || ch == ":" || ch.isWhitespace { return "-" }
            return ch
        }
        return "--\(String(safe))-\(pathDigest(cwd))--"
    }

    private static func pathDigest(_ cwd: String) -> String {
        var h: UInt64 = 0
        for b in cwd.utf8 {
            h = h &* 16_777_619 ^ UInt64(b)
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: h))
    }

    private static func jsonlFiles(in dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "jsonl" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    private static func parse(_ url: URL) -> (title: String, preview: String) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var title = ""
        var preview = ""
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let kind = (obj["kind"] as? String) ?? ""
            let body = (obj["text"] as? String) ?? ""
            if kind == "user", !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = String(body.prefix(72))
                preview = formatPreview("You", body)
            } else if kind == "assistant", !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                preview = formatPreview("Fun", body)
            }
        }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = "New chat"
        }
        if preview.isEmpty {
            preview = "No messages yet"
        }
        return (title, preview)
    }

    private static func formatPreview(_ who: String, _ body: String) -> String {
        let line = body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let clipped = String(line.prefix(40))
        return clipped.isEmpty ? who : "\(who): \(clipped)"
    }
}

private final class DelegateBridge: FunDelegate, @unchecked Sendable {
    private let hop: @Sendable (Snapshot) -> Void

    init(owner: FunViewModel) {
        hop = { [weak owner] snapshot in
            Task { @MainActor in owner?.handleSnapshot(snapshot) }
        }
    }

    func onSnapshot(snapshot: Snapshot) {
        hop(snapshot)
    }
}
