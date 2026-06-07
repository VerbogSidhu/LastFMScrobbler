import Foundation
import MusicKit

@MainActor
class AppleMusicManager: ObservableObject {
    @Published var isAuthorized = false
    @Published var recentTracks: [AppleMusicTrackData] = []
    @Published var errorMessage: String?
    @Published var isFetching = false
    
    init() {
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
        
        self.isFetching = true
        
        // Fetch up to 100 recent tracks (Apple Music often caps it, but good to specify)
        guard let url = URL(string: "https://api.music.apple.com/v1/me/recent/played/tracks?limit=100") else {
            self.isFetching = false
            return
        }
        
        do {
            let request = MusicDataRequest(urlRequest: URLRequest(url: url))
            let response = try await request.response()
            
            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(AppleMusicRecentTracksResponse.self, from: response.data)
            
            // Filter consecutive duplicates (often returned if a song was on repeat)
            var deduplicated: [AppleMusicTrackData] = []
            for track in decodedResponse.data {
                if deduplicated.last?.id != track.id {
                    deduplicated.append(track)
                }
            }
            
            self.recentTracks = deduplicated
        } catch {
            self.errorMessage = "Failed to fetch recent tracks: \(error.localizedDescription)"
            print("Apple Music Fetch Error: \(error)")
        }
        
        self.isFetching = false
    }
}
