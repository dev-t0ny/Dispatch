import Foundation

final class SessionStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Key {
        static let presets = "dispatch.presets"
        static let lastLaunch = "dispatch.lastLaunch"
        static let activeSession = "dispatch.activeSession"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadPresets() -> [LaunchPreset] {
        decode([LaunchPreset].self, forKey: Key.presets) ?? []
    }

    func savePresets(_ presets: [LaunchPreset]) {
        encode(presets, forKey: Key.presets)
    }

    func loadLastLaunch() -> LaunchRequest? {
        decode(LaunchRequest.self, forKey: Key.lastLaunch)
    }

    func saveLastLaunch(_ request: LaunchRequest) {
        encode(request, forKey: Key.lastLaunch)
    }

    func loadActiveSession() -> ActiveSession? {
        decode(ActiveSession.self, forKey: Key.activeSession)
    }

    func saveActiveSession(_ session: ActiveSession?) {
        guard let session else {
            defaults.removeObject(forKey: Key.activeSession)
            return
        }
        encode(session, forKey: Key.activeSession)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
