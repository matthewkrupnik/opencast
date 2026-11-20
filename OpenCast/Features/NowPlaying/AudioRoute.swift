import AVFoundation

/// What the current audio output is, reduced to the values Now Playing shows.
/// Built from plain port data so the mapping can be tested without a live
/// `AVAudioSession`.
nonisolated struct AudioRoute: Equatable, Sendable {
    /// One `AVAudioSessionPortDescription`, copied out so it can cross actors.
    struct Output: Equatable, Sendable {
        var portType: AVAudioSession.Port
        var portName: String
    }

    /// The output's name, e.g. "AirPods Pro" or "Kitchen". For the built-in
    /// speaker it is the system's own name, which the AirPlay button still
    /// reads out as its accessibility value.
    let name: String
    let systemImage: String
    /// False for the built-in speaker or receiver: the default needs no label.
    let isExternal: Bool

    static let builtIn = AudioRoute(outputs: [])

    private static let builtInPorts: Set<AVAudioSession.Port> = [.builtInSpeaker, .builtInReceiver]

    init(outputs: [Output]) {
        // A route can list a built-in port next to an external one; the
        // external one is where the sound the user is missing went.
        guard let external = outputs.first(where: { !Self.builtInPorts.contains($0.portType) }) else {
            name = outputs.lazy.compactMap(\.portName.trimmedNonEmpty).first ?? "Route"
            systemImage = "speaker.wave.2"
            isExternal = false
            return
        }

        let name = external.portName.trimmedNonEmpty ?? Self.fallbackName(for: external.portType)
        self.name = name
        systemImage = Self.systemImage(for: external.portType, name: name)
        isExternal = true
    }

    init(_ route: AVAudioSessionRouteDescription) {
        self.init(outputs: route.outputs.map { Output(portType: $0.portType, portName: $0.portName) })
    }

    private static func systemImage(for portType: AVAudioSession.Port, name: String) -> String {
        switch portType {
        case .airPlay:
            return "airplayaudio"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            // The port type cannot tell AirPods from other Bluetooth gear, but
            // their default name (kept when renamed with an owner's prefix) can.
            if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
            if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
            if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
            return "headphones"
        case .headphones:
            return "headphones"
        case .carAudio:
            return "car"
        case .HDMI, .displayPort:
            return "tv"
        default:
            return "hifispeaker"
        }
    }

    private static func fallbackName(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .airPlay: "AirPlay"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: "Bluetooth"
        case .headphones: "Headphones"
        case .carAudio: "Car"
        case .HDMI: "HDMI"
        case .displayPort: "DisplayPort"
        case .usbAudio: "USB Audio"
        default: "External Audio"
        }
    }
}
