import Foundation

// Playback position ticks 30 times a second. It lives apart from AppModel so only the views
// that show it redraw on every tick, not the whole window.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published private(set) var byClip: [UUID: Double] = [:]

    func fraction(for id: UUID) -> Double { byClip[id] ?? 0 }
    func set(_ fraction: Double, for id: UUID) { byClip[id] = fraction }
    func clear(_ id: UUID) { byClip[id] = nil }
}
