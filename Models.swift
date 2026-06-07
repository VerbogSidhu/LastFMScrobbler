import Foundation

// MARK: - Last.fm Models
struct LastFMSessionResponse: Codable {
    let session: LastFMSession?
    let error: Int?
    let message: String?
}

struct LastFMSession: Codable {
    let name: String
    let key: String
    let subscriber: Int
}

struct LastFMScrobbleResponse: Codable {
    let scrobbles: ScrobbleResponseStatus?
    let error: Int?
    let message: String?
}

struct ScrobbleResponseStatus: Codable {
    let attr: ScrobbleAttr?
    
    enum CodingKeys: String, CodingKey {
        case attr = "@attr"
    }
}

struct ScrobbleAttr: Codable {
    let accepted: Int
    let ignored: Int
}

// MARK: - Apple Music API Models
// We use custom codable structs because MusicKit's history API via MusicDataRequest returns JSON,
// not necessarily standard `Song` objects unless explicitly decoded.
struct AppleMusicRecentTracksResponse: Codable {
    let data: [AppleMusicTrackData]
}

struct AppleMusicTrackData: Codable, Identifiable {
    let id: String
    let type: String
    let attributes: AppleMusicTrackAttributes?
}

struct AppleMusicTrackAttributes: Codable {
    let name: String
    let artistName: String
    let albumName: String?
    let durationInMillis: Int?
}
