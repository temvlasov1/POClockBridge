import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

@main
struct POClockBridgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var extensionDetected = false

    var body: some View {
        NavigationStack {
            List {
                Section("AUv3 status") {
                    Label(
                        extensionDetected ? "PO Clock Bridge is registered" : "Waiting for iOS registration",
                        systemImage: extensionDetected ? "checkmark.circle.fill" : "clock"
                    )
                    .foregroundStyle(extensionDetected ? Color.green : Color.secondary)
                    Text("Open AUM after launching this app once. Add PO Clock Bridge as an Audio Unit Extension effect on the RØDE input channel.")
                }

                Section("Pocket Operator → RØDE") {
                    Text("Use a stereo PO sync mode with sync on one channel and audio on the other. Connect the PO stereo output to both AI‑Micro inputs with the correct stereo breakout cable.")
                    Text("Default plug-in preset: clock L, 2 PPQN, stereo passthrough, adaptive threshold, MIDI Clock + Tap.")
                }

                Section("AUM routing") {
                    setupStep(1, "Create a stereo hardware-input channel for the AI‑Micro.")
                    setupStep(2, "Insert PO Clock Bridge in the channel’s effect slot.")
                    setupStep(3, "Open AUM’s MIDI routing matrix and route the plug-in MIDI output to MIDI Control.")
                    setupStep(4, "MIDI-learn note 60 (C3) to AUM Tap Tempo, or route F8 Clock to an app that accepts MIDI Clock.")
                }

                Section("Ableton Link") {
                    Text("The AUv3 does not claim to control the host’s Link timeline. AUM’s own Link session can follow the bridge through its Tap Tempo mapping. See KNOWN_LIMITATIONS.md in the repository for the sandbox/process explanation.")
                }

                Section("Build") {
                    Text("PO Clock Bridge 0.2 • iOS 16+")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("PO Clock Bridge")
            .task { refreshRegistration() }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in
                    refreshRegistration()
                }
        }
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.16), in: Circle())
            Text(text)
        }
    }

    private func refreshRegistration() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicEffect,
            componentSubType: 0x70636C6B,       // 'pclk'
            componentManufacturer: 0x504F4342,  // 'POCB'
            componentFlags: 0,
            componentFlagsMask: 0
        )
        extensionDetected = !AVAudioUnitComponentManager.shared()
            .components(matching: description)
            .isEmpty
    }
}
