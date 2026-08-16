import Foundation
import TrackpadGuardCore

struct GuardPreferences: Codable, Equatable {
    var isEnabled = true
    var blockPointerMovement = true
    var blockClicks = true
    var blockScrolling = true
    var launchAtLogin = false
    var restartProtectionAfterWake = true
    var activationRegion = ActivationRegion.default

    init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case blockPointerMovement
        case blockClicks
        case blockScrolling
        case launchAtLogin
        case restartProtectionAfterWake
        case activationRegion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        blockPointerMovement = try values.decodeIfPresent(Bool.self, forKey: .blockPointerMovement) ?? true
        blockClicks = try values.decodeIfPresent(Bool.self, forKey: .blockClicks) ?? true
        blockScrolling = try values.decodeIfPresent(Bool.self, forKey: .blockScrolling) ?? true
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        restartProtectionAfterWake = try values.decodeIfPresent(Bool.self, forKey: .restartProtectionAfterWake) ?? true
        activationRegion = try values.decodeIfPresent(ActivationRegion.self, forKey: .activationRegion) ?? .default
    }
}
