import Observation

/// In-app updates are disabled for this local WMusic development build.
/// There is no WMusic appcast or signing key, so the upstream Bòcan feed must
/// never be queried or allowed to replace this app.
@Observable
@MainActor
final class UpdateController {
    private(set) var canCheckForUpdates = false

    func checkForUpdates() {}
}
