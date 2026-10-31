import Foundation

enum Provider: String, CaseIterable, Codable {
    case deepgram, whisper
    var displayName: String {
        switch self {
        case .deepgram: return "Deepgram"
        case .whisper:  return "OpenAI"
        }
    }

    var keyURL: URL {
        switch self {
        case .deepgram: return URL(string: "https://console.deepgram.com/signup")!
        case .whisper:  return URL(string: "https://platform.openai.com/api-keys")!
        }
    }
}
