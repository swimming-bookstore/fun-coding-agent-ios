import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var viewModel: FunViewModel

    var body: some View {
        TabView {
            ChatView(viewModel: viewModel)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            SettingsView(viewModel: viewModel)
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            viewModel.start()
            #if FUN_DEMO
            DemoDriver.maybeStart(viewModel: viewModel)
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            viewModel.stop()
        }
        .sheet(item: loginBinding) { login in
            LoginSheet(login: login, onCancel: viewModel.dismissLogin)
        }
        .alert(
            "Grok",
            isPresented: Binding(
                get: { !viewModel.snapshot.toast.isEmpty },
                set: { if !$0 { viewModel.dismissToast() } }
            )
        ) {
            Button("OK", action: viewModel.dismissToast)
        } message: {
            Text(viewModel.snapshot.toast)
        }
    }

    private var loginBinding: Binding<LoginInfo?> {
        Binding(
            get: { viewModel.snapshot.login },
            set: { if $0 == nil { viewModel.dismissLogin() } }
        )
    }
}

private struct ChatView: View {
    @ObservedObject var viewModel: FunViewModel
    @State private var showChats = false

    var body: some View {
        NavigationStack {
            ThreadView(viewModel: viewModel)
                .navigationTitle(viewModel.currentTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showChats = true
                        } label: {
                            Label("Chats", systemImage: "list.bullet")
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text(viewModel.snapshot.usage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(viewModel.snapshot.usageTip)
                    }
                    if viewModel.snapshot.working {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Cancel", role: .destructive) { viewModel.abort() }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.newChat()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                    }
                }
                .sheet(isPresented: $showChats) {
                    ChatListView(viewModel: viewModel, isPresented: $showChats)
                        .onAppear { viewModel.reloadChats() }
                }
        }
    }
}

private struct ChatListView: View {
    @ObservedObject var viewModel: FunViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                if viewModel.chats.isEmpty {
                    Text("No chats yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.chats) { chat in
                    let selected = chat.path == viewModel.currentChatPath
                    Button {
                        viewModel.openChat(chat.path)
                        isPresented = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.title)
                                .fontWeight(selected ? .semibold : .regular)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(chat.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .listRowBackground(selected ? Color(uiColor: .tertiarySystemFill) : nil)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            viewModel.removeChat(chat.path)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.newChat()
                        isPresented = false
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: FunViewModel

    var body: some View {
        NavigationStack {
            List {
                if viewModel.snapshot.loggedIn {
                    Button("Log Out of Grok", role: .destructive, action: viewModel.logoutGrok)
                } else {
                    Button("Log In to Grok", action: viewModel.loginGrok)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ThreadView: View {
    @ObservedObject var viewModel: FunViewModel
    private let threadEnd = "thread-end"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.snapshot.items.isEmpty {
                        emptyNote
                    }
                    ForEach(viewModel.snapshot.items, id: \.id) { item in
                        ChatItemView(item: item).id(item.id)
                    }
                    Color.clear.frame(height: 1).id(threadEnd)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    docks
                    Composer(viewModel: viewModel)
                }
                .background(.bar)
            }
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: viewModel.snapshot.items.last?.id) { _, _ in scrollToEnd(proxy) }
            .onChange(of: viewModel.snapshot.items.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: viewModel.snapshot.thinking) { _, _ in scrollToEnd(proxy) }
            .onChange(of: viewModel.snapshot.steer) { _, _ in scrollToEnd(proxy) }
            .onChange(of: viewModel.snapshot.queue.count) { _, _ in scrollToEnd(proxy) }
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var emptyNote: some View {
        VStack(spacing: 12) {
            Text(viewModel.snapshot.loggedIn ? "Send a message to start." : "Log in to Grok to start a chat.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !viewModel.snapshot.loggedIn {
                Button("Log In to Grok", action: viewModel.loginGrok)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private var docks: some View {
        VStack(spacing: 0) {
            if !viewModel.snapshot.thinking.isEmpty {
                Dock(title: "Thinking") {
                    Text(viewModel.snapshot.thinking)
                        .italic()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(6)
                }
            }
            if !viewModel.snapshot.steer.isEmpty {
                Dock(title: "Send Now") {
                    HStack {
                        Text(viewModel.snapshot.steer).lineLimit(1)
                        Spacer()
                        if !viewModel.snapshot.steerCount.isEmpty {
                            Text(viewModel.snapshot.steerCount)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !viewModel.snapshot.queue.isEmpty {
                Dock(title: "Queue") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.snapshot.queue, id: \.index) { item in
                            QueueRow(item: item, total: viewModel.snapshot.queue.count, viewModel: viewModel)
                        }
                    }
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            proxy.scrollTo(threadEnd, anchor: .bottom)
        }
    }
}

private struct Dock<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

private struct QueueRow: View {
    let item: QueueItem
    let total: Int
    @ObservedObject var viewModel: FunViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(item.index + 1).")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(oneLine(item.text)).lineLimit(1)
                Spacer(minLength: 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Send Now") { viewModel.queueSendNow(item.index) }
                    Button("Edit") { viewModel.queueEdit(item.index) }
                    Button("Move Up") { viewModel.queueMove(item.index, delta: -1) }
                        .disabled(item.index == 0)
                    Button("Move Down") { viewModel.queueMove(item.index, delta: 1) }
                        .disabled(Int(item.index) + 1 >= total)
                    Button("Cancel", role: .destructive) { viewModel.queueDrop(item.index) }
                }
            }
        }
        .padding(6)
        .background(item.flash ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .controlSize(.small)
    }
}

private struct Composer: View {
    @ObservedObject var viewModel: FunViewModel
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                .onKeyPress { press in
                    if press.key == .escape {
                        viewModel.abort()
                        return .handled
                    }
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.option) { return .ignored }
                    if press.modifiers.contains(.control) {
                        viewModel.interrupt()
                        return .handled
                    }
                    viewModel.submit()
                    return .handled
                }
            Button {
                viewModel.submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { focused = true }
    }
}

private struct ChatItemView: View {
    let item: ChatItem

    var body: some View {
        switch item.kind {
        case .user:
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 56)
                bubble(outgoing: true) {
                    Text(item.body)
                }
            }
        case .agent:
            HStack(alignment: .bottom, spacing: 8) {
                bubble(outgoing: false) {
                    Group {
                        if item.streaming {
                            Text(item.body)
                        } else {
                            Text(markdown(item.body))
                        }
                    }
                }
                Spacer(minLength: 56)
            }
        case .note:
            Text(item.body)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        case .tool:
            HStack {
                DisclosureGroup(item.toolSummary) {
                    Text(item.toolDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer(minLength: 56)
            }
        case .marker:
            HStack {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                Text("New Messages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            }
        }
    }

    private func bubble<Content: View>(outgoing: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body)
            .foregroundStyle(outgoing ? Color.white : Color.primary)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                outgoing ? Color.accentColor : Color(uiColor: .secondarySystemFill),
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: outgoing ? 18 : 5,
                    bottomTrailingRadius: outgoing ? 5 : 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
    }
}

private struct LoginSheet: View {
    let login: LoginInfo
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with SuperGrok or X Premium")
                .font(.headline)
            Text(login.status)
                .textSelection(.enabled)
            if !login.userCode.isEmpty {
                Text(login.userCode)
                    .font(.title2.weight(.semibold))
                    .textSelection(.enabled)
            }
            if let url = URL(string: login.openUrl), !login.openUrl.isEmpty {
                Link(login.uri.isEmpty ? login.openUrl : login.uri, destination: url)
            } else if !login.uri.isEmpty {
                Text(login.uri)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}

extension LoginInfo: Identifiable {
    public var id: String { userCode + status }
}

private func oneLine(_ s: String) -> String {
    let line = s.split(whereSeparator: \.isNewline).map(String.init).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? s
    return String(line.prefix(80))
}

private func markdown(_ src: String) -> AttributedString {
    (try? AttributedString(markdown: src, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(src)
}
