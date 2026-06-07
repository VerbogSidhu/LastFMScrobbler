import SwiftUI

struct ContentView: View {
    @StateObject private var appleMusicManager = AppleMusicManager()
    @StateObject private var lastFMManager = LastFMManager()
    
    @State private var showingLastFMLogin = false
    @State private var scrobbleCount: Double = 5
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header Status
                HStack {
                    StatusBadge(title: "Apple Music", isConnected: appleMusicManager.isAuthorized)
                    StatusBadge(title: "Last.fm", isConnected: lastFMManager.isAuthenticated)
                }
                .padding()
                
                if !appleMusicManager.isAuthorized {
                    Button("Connect Apple Music") {
                        Task { await appleMusicManager.requestAuthorization() }
                    }
                    .buttonStyle(.borderedProminent)
                } else if !lastFMManager.isAuthenticated {
                    Button("Connect Last.fm") {
                        showingLastFMLogin = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    // Main Interface
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Ready to Scrobble")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Button("Logout") {
                                lastFMManager.logout()
                            }
                            .foregroundColor(.red)
                        }
                        
                        Text("Logged in as \(lastFMManager.username ?? "Unknown")")
                            .foregroundColor(.secondary)
                        
                        Divider()
                        
                        if appleMusicManager.recentTracks.isEmpty {
                            if appleMusicManager.isFetching {
                                ProgressView("Fetching History...")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                Button("Fetch Recent Tracks") {
                                    Task { await appleMusicManager.fetchRecentlyPlayed() }
                                }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            Text("Found \(appleMusicManager.recentTracks.count) recent tracks.")
                            
                            if appleMusicManager.recentTracks.count > 0 {
                                VStack(alignment: .leading) {
                                    Text("How many to scrobble? \(Int(scrobbleCount))")
                                    Slider(value: $scrobbleCount, in: 1...Double(appleMusicManager.recentTracks.count), step: 1)
                                }
                                .padding(.vertical)
                            }
                            
                            if lastFMManager.isScrobbling {
                                ProgressView("Scrobbling to Last.fm...")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                Button(action: {
                                    Task {
                                        await lastFMManager.scrobble(tracks: appleMusicManager.recentTracks, count: Int(scrobbleCount))
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "music.note")
                                        Text("Scrobble to Last.fm")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.large)
                            }
                            
                            List(Array(appleMusicManager.recentTracks.prefix(Int(scrobbleCount)))) { track in
                                VStack(alignment: .leading) {
                                    Text(track.attributes?.name ?? "Unknown Track")
                                        .font(.headline)
                                    Text(track.attributes?.artistName ?? "Unknown Artist")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .listStyle(.plain)
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Scrobbler")
            .sheet(isPresented: $showingLastFMLogin) {
                if let url = lastFMManager.getAuthURL() {
                    LastFMLoginView(url: url, onTokenReceived: { token in
                        Task {
                            await lastFMManager.fetchSession(token: token)
                        }
                    }, isPresented: $showingLastFMLogin)
                }
            }
            // Sync slider safely
            .onChange(of: appleMusicManager.recentTracks.count) { newCount in
                if newCount > 0 {
                    scrobbleCount = min(5, Double(newCount))
                }
            }
            .alert("Error", isPresented: Binding<Bool>(
                get: { appleMusicManager.errorMessage != nil || lastFMManager.errorMessage != nil },
                set: { _ in
                    appleMusicManager.errorMessage = nil
                    lastFMManager.errorMessage = nil
                }
            )) {
                Button("OK") {
                    appleMusicManager.errorMessage = nil
                    lastFMManager.errorMessage = nil
                }
            } message: {
                Text(appleMusicManager.errorMessage ?? lastFMManager.errorMessage ?? "Unknown error")
            }
            .alert("Success", isPresented: Binding<Bool>(
                get: { lastFMManager.successMessage != nil },
                set: { _ in lastFMManager.successMessage = nil }
            )) {
                Button("OK") {
                    lastFMManager.successMessage = nil
                }
            } message: {
                Text(lastFMManager.successMessage ?? "")
            }
        }
    }
}

struct StatusBadge: View {
    let title: String
    let isConnected: Bool
    
    var body: some View {
        HStack {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption)
                .bold()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
