import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferences: GuardPreferences {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let storageKey = "TrackpadGuard.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(GuardPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = GuardPreferences()
        }
    }

    func resetActivationRegion() {
        preferences.activationRegion = .default
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
