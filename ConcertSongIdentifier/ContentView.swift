//
//  ContentView.swift
//  ConcertSongIdentifier
//
//  Created by Caelen Fry on 12/21/24.

import SwiftUI
import ShazamKit
import AVFoundation

class ShazamRecognizer: NSObject, SHSessionDelegate, ObservableObject {
    private var audioEngine = AVAudioEngine() // Handles audio recording
    private var session = SHSession() // ShazamKit session
    @Published var isRecording = false // Changed to Published to make it accessible
    @Published var matchedSong: (title: String, artist: String)? = nil // Holds matched song details

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

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.session.matchStreamingBuffer(buffer, at: nil) // Send audio to ShazamKit
        }

        do {
            try audioEngine.start()
            isRecording = true
        } catch {
            print("Audio Engine failed to start: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }

    func session(_ session: SHSession, didFind match: SHMatch) {
        if let mediaItem = match.mediaItems.first {
            let title = mediaItem.title ?? "Unknown Title"
            let artist = mediaItem.artist ?? "Unknown Artist"
            DispatchQueue.main.async {
                self.matchedSong = (title: title, artist: artist)
            }
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        print("No match found or error: \(String(describing: error))")
    }
}

struct ContentView: View {
    @StateObject private var shazamRecognizer = ShazamRecognizer()
    @State private var songInfo: String = "Press the button to identify a song"

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                Text(songInfo)
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()

                Button(action: {
                    if shazamRecognizer.isRecording {
                        shazamRecognizer.stopRecording()
                    } else {
                        shazamRecognizer.requestMicrophoneAccess { granted in
                            if granted {
                                shazamRecognizer.startRecording()
                            } else {
                                songInfo = "Microphone access denied."
                            }
                        }
                    }
                }) {
                    Text(shazamRecognizer.isRecording ? "Stop Recording" : "Start Recording")
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .onReceive(shazamRecognizer.$matchedSong) { song in
                if let song = song {
                    songInfo = "Matched: \(song.title) by \(song.artist)"
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
