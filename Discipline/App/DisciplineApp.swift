import SwiftUI

@main
struct DisciplineApp: App {
    @State private var container: AppContainer
    @State private var session: SessionStore
    @AppStorage("appearance") private var appearance: AppearancePreference = .dark

    init() {
        let container = AppContainer.live()
        _container = State(initialValue: container)
        _session = State(initialValue: SessionStore(auth: container.auth, users: container.users))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .environment(session)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.Palette.accent)
                .fontDesign(.rounded)
                .onAppear { session.start() }
        }
    }
}
