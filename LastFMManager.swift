import Foundation
import CryptoKit

@MainActor
class LastFMManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var sessionKey: String?
    @Published var username: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"
    
    // Check if we have a saved session
    init() {
        if let savedKey = UserDefaults.standard.string(forKey: "LastFMSessionKey"),
           let savedUser = UserDefaults.standard.string(forKey: "LastFMUsername") {
            self.sessionKey = savedKey
            self.username = savedUser
            self.isAuthenticated = true
        }
    }
    
    // MARK: - Authentication Flow
    
    func getAuthURL() -> URL? {
        let urlString = "http://www.last.fm/api/auth/?api_key=\(Config.lastFMApiKey)&cb=lastfmscrobbler://auth"
        return URL(string: urlString)
    }
    
    func fetchSession(token: String) async {
        let params: [String: String] = [
            "method": "auth.getSession",
            "api_key": Config.lastFMApiKey,
            "token": token
        ]
        
        guard let request = createRequest(params: params, isPost: false) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let response = try decoder.decode(LastFMSessionResponse.self, from: data)
            
            if let session = response.session {
                self.sessionKey = session.key
                self.username = session.name
                self.isAuthenticated = true
                
                // Save to UserDefaults
                UserDefaults.standard.set(session.key, forKey: "LastFMSessionKey")
                UserDefaults.standard.set(session.name, forKey: "LastFMUsername")
            } else if let message = response.message {
                self.errorMessage = "Auth Error: \(message)"
            }
        } catch {
            self.errorMessage = "Failed to fetch session: \(error.localizedDescription)"
        }
    }
    
    func logout() {
        self.sessionKey = nil
        self.username = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "LastFMSessionKey")
        UserDefaults.standard.removeObject(forKey: "LastFMUsername")
    }
    
    // MARK: - Scrobbling
    
    func scrobble(tracks: [AppleMusicTrackData], count: Int) async {
        guard let sk = sessionKey else {
            self.errorMessage = "Not authenticated with Last.fm"
            return
        }
        
        let tracksToScrobble = Array(tracks.prefix(count))
        if tracksToScrobble.isEmpty { return }
        
        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": Config.lastFMApiKey,
            "sk": sk
        ]
        
        // Add batch parameters
        // Note: Apple Music Recent Tracks API doesn't provide the exact timestamp played,
        // so we will fake it by spacing them out backwards from the current time.
        // In a real app, you might want to use a more persistent DB to track precise scrobble times
        // or just submit them with recent timestamps.
        
        var currentTimestamp = Int(Date().timeIntervalSince1970)
        
        for (index, track) in tracksToScrobble.enumerated() {
            let artist = track.attributes?.artistName ?? "Unknown Artist"
            let title = track.attributes?.name ?? "Unknown Track"
            let album = track.attributes?.albumName ?? ""
            
            params["artist[\(index)]"] = artist
            params["track[\(index)]"] = title
            params["album[\(index)]"] = album
            params["timestamp[\(index)]"] = String(currentTimestamp)
            
            // Subtract typical song length for the next track's timestamp (e.g. 3 mins)
            currentTimestamp -= 180 
        }
        
        guard let request = createRequest(params: params, isPost: true) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let response = try decoder.decode(LastFMScrobbleResponse.self, from: data)
            
            if let scrobbles = response.scrobbles?.attr {
                self.successMessage = "Successfully scrobbled \(scrobbles.accepted) tracks!"
            } else if let message = response.message {
                self.errorMessage = "Scrobble Error: \(message)"
            }
        } catch {
            self.errorMessage = "Failed to scrobble: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helpers
    
    private func createRequest(params: [String: String], isPost: Bool) -> URLRequest? {
        var allParams = params
        allParams["api_sig"] = generateSignature(params: params)
        allParams["format"] = "json" // We want JSON back
        
        var urlComponents = URLComponents(string: baseURL)!
        
        if isPost {
            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            let postString = allParams.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
            request.httpBody = postString.data(using: .utf8)
            return request
        } else {
            urlComponents.queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "GET"
            return request
        }
    }
    
    private func generateSignature(params: [String: String]) -> String {
        let sortedKeys = params.keys.sorted()
        var sigString = ""
        
        for key in sortedKeys {
            if let value = params[key] {
                sigString += "\(key)\(value)"
            }
        }
        
        sigString += Config.lastFMSharedSecret
        
        let inputData = Data(sigString.utf8)
        let hashed = Insecure.MD5.hash(data: inputData)
        return hashed.map { String(format: "%02hhx", $0) }.joined()
    }
}
