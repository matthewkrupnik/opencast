import Foundation
import Observation
import OpenCastPlayback

@MainActor
final class SmartSpeedManager {
    private let playback: AVFoundationPlaybackController
    private let settingsStore: PlaybackSettingsStore
    private var integration: HybridSmartSpeedIntegration?
    private var observationTask: Task<Void, Never>?

    init(playback: AVFoundationPlaybackController, settingsStore: PlaybackSettingsStore) {
        self.playback = playback
        self.settingsStore = settingsStore
        startObserving()
    }

    private func startObserving() {
        observationTask = Task {
            var lastIdentity: PlaybackItemSourceIdentity? = nil
            var lastEnabled: Bool? = nil
            
            while !Task.isCancelled {
                let currentIdentity = playback.currentItemSourceIdentity
                let currentEnabled = settingsStore.isSmartSpeedEnabled
                
                if currentIdentity != lastIdentity || currentEnabled != lastEnabled {
                    lastIdentity = currentIdentity
                    lastEnabled = currentEnabled
                    updateIntegration(identity: currentIdentity, enabled: currentEnabled)
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000) // 5Hz polling for identity changes
            }
        }
    }

    private func updateIntegration(identity: PlaybackItemSourceIdentity?, enabled: Bool) {
        integration?.setEnabled(false)
        integration = nil

        guard enabled, let identity = identity, identity.kind == .localFile else {
            return
        }

        // We need to fetch the underlying settings. We construct a basic settings object based on UI settings
        var settings = SmartSpeedSettings()
        settings.baselineSpeed = Double(playback.rate) // Note: this might change dynamically, but we only set on init
        
        // Unfortunately AVFoundationPlaybackController.player is private. We can't pass AVPlayer!
        // We will pass the controller and use position/rate.
        integration = HybridSmartSpeedIntegration(controller: playback, url: identity.assetURL, settings: settings) { [weak playback] in
            playback?.rate ?? 1.0
        }
        integration?.setEnabled(true)
    }
}
