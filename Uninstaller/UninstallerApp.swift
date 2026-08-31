import SwiftUI

@main
struct CheeseCoolUninstallerApp: App {
    var body: some Scene {
        WindowGroup {
            UninstallerView()
        }
        .windowResizability(.contentSize)
    }
}
