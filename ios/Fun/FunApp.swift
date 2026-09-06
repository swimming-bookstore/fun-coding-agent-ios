import SwiftUI

@main
struct FunIOSApp: App {
    @StateObject private var viewModel = FunViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
