#if FUN_DEMO
import Foundation

@MainActor
enum DemoDriver {
    private static var started = false

    static func maybeStart(viewModel: FunViewModel) {
        guard !started else { return }
        guard ProcessInfo.processInfo.environment["FUN_DEMO"] == "1" else { return }
        started = true
        Task { await run(viewModel: viewModel) }
    }

    private static func run(viewModel: FunViewModel) async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        viewModel.newChat()
        try? await Task.sleep(nanoseconds: 900_000_000)

        await type(viewModel, P1, cps: 16)
        try? await Task.sleep(nanoseconds: 400_000_000)
        viewModel.submit()
        try? await Task.sleep(nanoseconds: 350_000_000)

        await type(viewModel, P2, cps: 20)
        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.submit()
        try? await Task.sleep(nanoseconds: 200_000_000)

        await type(viewModel, P3, cps: 20)
        try? await Task.sleep(nanoseconds: 200_000_000)
        viewModel.submit()

        if await wait(25, until: { viewModel.snapshot.queue.count >= 2 }) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            viewModel.queueMove(0, delta: 1)
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if viewModel.snapshot.queue.count >= 2 {
                viewModel.queueMove(1, delta: -1)
            }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if !viewModel.snapshot.queue.isEmpty {
                viewModel.queueSendNow(0)
            }
        }

        _ = await wait(90) {
            !viewModel.snapshot.working
                && viewModel.snapshot.queue.isEmpty
                && viewModel.snapshot.items.contains { $0.kind == .agent }
        }
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        viewModel.stop()
        exit(0)
    }

    private static func type(_ viewModel: FunViewModel, _ text: String, cps: Int) async {
        viewModel.draft = ""
        var typed = ""
        let delay = 1_000_000_000 / UInt64(max(cps, 1))
        for ch in text {
            typed.append(ch)
            viewModel.draft = typed
            try? await Task.sleep(nanoseconds: delay)
        }
    }

    private static func wait(_ seconds: Double, until: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if until() { return true }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return until()
    }
}

private let P1 =
    "create a tiny python greet CLI that says hello in Korean to "
    + "\"수영 서점\" (swimming bookstore) as the default name, with argparse --loud "
    + "and --count, write tests, run them, and add a Makefile"
private let P2 = "also add a README in Korean"
private let P3 = "print a usage line too"
#endif
