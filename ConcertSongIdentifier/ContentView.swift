//
//  ContentView.swift
//  ConcertSongIdentifier
//
//  Created by Caelen Fry on 12/21/24.
//

import SwiftUI
import ShazamKit
import AVFoundation

struct SongMatch: Identifiable, Equatable {
    let id = UUID()
    let startTimestamp: String
    var endTimestamp: String?
    let title: String
    let artist: String
    let artworkURL: URL?
    let appleMusicURL: URL?
}

class ShazamRecognizer: NSObject, SHSessionDelegate, ObservableObject {
    private var audioEngine = AVAudioEngine()
    private var session = SHSession()
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var matchedSongs: [SongMatch] = []

    private var startTime: Date?
    private var pauseStartTime: Date?
    private var elapsedPausedTime: TimeInterval = 0

    override init() {
        super.init()
        session.delegate = self
    }

    func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }

    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    func startRecording() {
        setupAudioSession()
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 && format.channelCount > 0 else {
            print("Invalid audio format detected!")
            return
        }

        inputNode.removeTap(onBus: 0)

        if startTime == nil {
            startTime = Date()
        } else if let pauseStartTime = pauseStartTime {
            elapsedPausedTime += Date().timeIntervalSince(pauseStartTime)
            self.pauseStartTime = nil
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.session.matchStreamingBuffer(buffer, at: nil)
        }

        do {
            try audioEngine.start()
            isRecording = true
            isPaused = false
        } catch {
            print("Audio Engine failed to start: \(error.localizedDescription)")
        }
    }

    func pauseRecording() {
        audioEngine.pause()
        isRecording = false
        isPaused = true
        pauseStartTime = Date()
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
        isPaused = false
    }

    func resetMatchedSongs() {
        matchedSongs.removeAll()
        startTime = nil
        elapsedPausedTime = 0
        pauseStartTime = nil
        isRecording = false
        isPaused = false
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        if let mediaItem = match.mediaItems.first {
            let title = mediaItem.title ?? "Unknown Title"
            let artist = mediaItem.artist ?? "Unknown Artist"
            let artworkURL = mediaItem.artworkURL
            let appleMusicURL = mediaItem.appleMusicURL
            let timestamp = calculateTimestamp()

            DispatchQueue.main.async {
                if let lastSong = self.matchedSongs.last, lastSong.title == title && lastSong.artist == artist {
                    self.matchedSongs[self.matchedSongs.count - 1].endTimestamp = timestamp
                } else {
                    self.matchedSongs.append(SongMatch(startTimestamp: timestamp, endTimestamp: nil, title: title, artist: artist, artworkURL: artworkURL, appleMusicURL: appleMusicURL))
                }
            }
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        print("No match found or error: \(String(describing: error))")
    }

    func calculateTimestamp() -> String {
        guard let start = startTime else { return "00:00" }
        let elapsed = Date().timeIntervalSince(start) - elapsedPausedTime
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct ContentView: View {
    @StateObject private var shazamRecognizer = ShazamRecognizer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 10) {
                ControlButtons(shazamRecognizer: shazamRecognizer)
                SongListView(shazamRecognizer: shazamRecognizer)
            }
        }
    }
}

struct ControlButtons: View {
    @ObservedObject var shazamRecognizer: ShazamRecognizer

    var body: some View {
        HStack {
            Button(action: { shazamRecognizer.resetMatchedSongs() }) {
                Text("Reset")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            Spacer()
            Button(action: {
                if shazamRecognizer.isRecording {
                    shazamRecognizer.pauseRecording()
                } else {
                    shazamRecognizer.requestMicrophoneAccess { granted in
                        if granted { shazamRecognizer.startRecording() }
                    }
                }
            }) {
                Text(shazamRecognizer.isRecording ? "Pause Recording" : (shazamRecognizer.isPaused ? "Resume Recording" : "Start Recording"))
                    .padding()
                    .background(shazamRecognizer.isRecording ? Color.green : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}

struct SongRow: View {
    let song: SongMatch

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                AsyncImage(url: song.artworkURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .cornerRadius(10)
                    default:
                        Color.gray.frame(width: 50, height: 50).cornerRadius(10)
                    }
                }
                VStack {
                    Text(song.startTimestamp)
                    Text(song.endTimestamp ?? "")
                }
                .frame(width: 80)
                .padding(5)
                .background(Color.gray.opacity(0.4))
                .cornerRadius(10)
                .foregroundColor(.white)
                if let appleMusicURL = song.appleMusicURL {
                    Button(action: { UIApplication.shared.open(appleMusicURL) }) {
                        Text("Open in Apple Music")
                            .foregroundColor(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white)
                            .cornerRadius(10)
                    }
                }
            }
            Text("\(song.title) by \(song.artist)")
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
        }
    }
}

struct SongListView: View {
    @ObservedObject var shazamRecognizer: ShazamRecognizer

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(shazamRecognizer.matchedSongs) { song in
                    SongRow(song: song)
                        .id(song.id)
                }
            }
            .onChange(of: shazamRecognizer.matchedSongs) { _ in
                if let lastSong = shazamRecognizer.matchedSongs.last {
                    proxy.scrollTo(lastSong.id, anchor: .bottom)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
