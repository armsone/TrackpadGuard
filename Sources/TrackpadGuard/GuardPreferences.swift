import Foundation
import TrackpadGuardCore

struct GuardPreferences: Codable, Equatable {
    var isEnabled = true
    var blockPointerMovement = true
    var blockClicks = true
    var blockScrolling = true
    var launchAtLogin = false
    var activationRegion = ActivationRegion.default
}
