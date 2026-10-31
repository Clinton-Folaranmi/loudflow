import Foundation

struct Turn: Codable, Equatable {
    var speaker: Int
    var at: TimeInterval
    var text: String
    // Where the last word ends. Older clips don't have it.
    var end: TimeInterval? = nil
}
