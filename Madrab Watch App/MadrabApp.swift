import SwiftUI

@main
struct Madrab_Watch_AppApp: App {
    @State private var client = WatchSyncClient(session: LiveWatchConnectivitySession())

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
                .task { client.activate() }
        }
    }
}
