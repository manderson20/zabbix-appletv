//
//  ZabbixAppleTVDashboardApp.swift
//  ZabbixAppleTVDashboard
//
//  Created by Mathew Anderson on 7/7/26.
//

import AVFoundation
import SwiftUI

@main
struct ZabbixAppleTVDashboardApp: App {
    init() {
        Self.configureNonInterruptingAudio()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Declares this app a passive audio *mixer* rather than an audio *source*, so music already
    /// playing from Apple Music / Spotify / Pandora keeps going when the dashboard is brought to
    /// the foreground. The app plays no audio of its own; the point is purely to promise tvOS it
    /// never will in a way that interrupts.
    ///
    /// `.ambient` is the only category that both never interrupts other audio when the session
    /// activates and is happy to coexist with another app owning the "now playing" audio. The
    /// default (`.soloAmbient`) would silence background audio the moment anything in this process
    /// touched the audio session — a stray UI/focus sound is enough — which is exactly the
    /// "my music stops when I open the dashboard" symptom this prevents. `.mixWithOthers` is
    /// redundant for `.ambient` but stated explicitly so the intent survives a future category
    /// change.
    ///
    /// Note this is only about not interrupting *someone else's* playback. It is not the same as
    /// background-audio playback capability (UIBackgroundModes), which this app deliberately does
    /// not want — that is for an app that is itself the music source.
    private static func configureNonInterruptingAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            // A dashboard with no audio of its own has nothing to fail toward — if the category
            // can't be set, the worst case is tvOS's default handling, so there's nothing to do
            // but carry on rather than block the UI from coming up.
        }
    }
}
