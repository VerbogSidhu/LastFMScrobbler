import Foundation
import CryptoKit

extension String {
    // Standard URL encoding doesn't cover all characters (like '+' and '&') that cause issues in Last.fm form data
    func rfc3986Encoded() -> String {
        let unreserved = "-._~/?"
        let allowed = NSMutableCharacterSet.alphanumeric()
        allowed.addCharacters(in: unreserved)
        return self.addingPercentEncoding(withAllowedCharacters: allowed as CharacterSet) ?? self
    }
}

@MainActor
class LastFMManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var sessionKey: String?
    @Published var username: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    @Published var isScrobbling = false
    
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
        
        var tracksToScrobble = Array(tracks.prefix(count))
        if tracksToScrobble.isEmpty { return }
        
        self.isScrobbling = true
        var totalAccepted = 0
        var currentTimestamp = Int(Date().timeIntervalSince1970)
        
        // Last.fm limits batch scrobbles to 50 per request
        let batchSize = 50
        
        for batchStart in stride(from: 0, to: tracksToScrobble.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, tracksToScrobble.count)
            let batch = Array(tracksToScrobble[batchStart..<batchEnd])
            
            var params: [String: String] = [
                "method": "track.scrobble",
                "api_key": Config.lastFMApiKey,
                "sk": sk
            ]
            
            for (index, track) in batch.enumerated() {
                let artist = track.attributes?.artistName ?? "Unknown Artist"
                let title = track.attributes?.name ?? "Unknown Track"
                let album = track.attributes?.albumName ?? ""
                
                params["artist[\(index)]"] = artist
                params["track[\(index)]"] = title
                params["album[\(index)]"] = album
                params["timestamp[\(index)]"] = String(currentTimestamp)
                
                // Subtract 3 mins for fake timestamps going backwards
                currentTimestamp -= 180 
            }
            
            guard let request = createRequest(params: params, isPost: true) else {
                self.errorMessage = "Failed to construct scrobble request."
                self.isScrobbling = false
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let decoder = JSONDecoder()
                let response = try decoder.decode(LastFMScrobbleResponse.self, from: data)
                
                if let scrobbles = response.scrobbles?.attr {
                    totalAccepted += scrobbles.accepted
                } else if let message = response.message {
                    self.errorMessage = "Scrobble Error: \(message)"
                    self.isScrobbling = false
                    return
                }
            } catch {
                self.errorMessage = "Failed to scrobble: \(error.localizedDescription)"
                self.isScrobbling = false
                return
            }
        }
        
        self.successMessage = "Successfully scrobbled \(totalAccepted) tracks!"
        self.isScrobbling = false
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
            
            let postString = allParams.map { "\($0.key.rfc3986Encoded())=\($0.value.rfc3986Encoded())" }.joined(separator: "&")
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
