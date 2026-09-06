import Foundation
import UIKit

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

    private var app: FunApp?
    private var bridge: DelegateBridge?
    private var lastOpenedCode = ""

    func start() {
        guard app == nil else { return }
        let home = dataRoot()
        let workspace = home.appendingPathComponent("workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
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
    func newChat() { app?.newChat() }
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

    fileprivate func handleSnapshot(_ snap: Snapshot) {
        snapshot = snap
        if let login = snap.login, !login.openUrl.isEmpty, login.userCode != lastOpenedCode {
            lastOpenedCode = login.userCode
            if let url = URL(string: login.openUrl) {
                UIApplication.shared.open(url)
            }
        }
        if snap.login == nil { lastOpenedCode = "" }
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
