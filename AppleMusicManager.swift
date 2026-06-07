import Foundation
import MusicKit

@MainActor
class AppleMusicManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var recentTracks: [AppleMusicTrackData] = []
    @Published var errorMessage: String?
    
    init() {
        // Initial check for authorization status if already granted
        if MusicAuthorization.currentStatus == .authorized {
            self.isAuthorized = true
        }
    }
    
    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        if status == .authorized {
            self.isAuthorized = true
        } else {
            self.isAuthorized = false
            self.errorMessage = "Apple Music access denied. Please enable it in Settings."
        }
    }
    
    func fetchRecentlyPlayed() async {
        guard isAuthorized else {
            self.errorMessage = "Not authorized to access Apple Music."
            return
        }
        
        // Apple Music API endpoint for recently played tracks
        guard let url = URL(string: "https://api.music.apple.com/v1/me/recent/played/tracks") else { return }
        
        do {
            let request = MusicDataRequest(urlRequest: URLRequest(url: url))
            let response = try await request.response()
            
            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(AppleMusicRecentTracksResponse.self, from: response.data)
            
            // Limit to the tracks we received, could be adjusted with pagination or query params if needed
            self.recentTracks = decodedResponse.data
        } catch {
            self.errorMessage = "Failed to fetch recent tracks: \(error.localizedDescription)"
            print("Apple Music Fetch Error: \(error)")
        }
    }
}
