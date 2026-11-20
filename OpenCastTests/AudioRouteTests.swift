import AVFoundation
import Testing
@testable import OpenCast

@Suite("Audio route display")
struct AudioRouteTests {
    private func route(_ outputs: (AVAudioSession.Port, String)...) -> AudioRoute {
        AudioRoute(outputs: outputs.map { AudioRoute.Output(portType: $0.0, portName: $0.1) })
    }

    @Test("The built-in speaker or receiver is not external but keeps its name", arguments: [
        AVAudioSession.Port.builtInSpeaker, .builtInReceiver,
    ])
    func builtInIsNotExternal(port: AVAudioSession.Port) {
        let route = route((port, "Speaker"))
        #expect(!route.isExternal)
        #expect(route.name == "Speaker")
    }

    @Test("No outputs reads as the built-in route")
    func noOutputs() {
        #expect(AudioRoute.builtIn == route())
        #expect(!AudioRoute.builtIn.isExternal)
        #expect(AudioRoute.builtIn.name == "Route")
    }

    @Test("AirPlay shows the receiver's name")
    func airPlay() {
        let route = route((.airPlay, "Kitchen"))
        #expect(route.isExternal)
        #expect(route.name == "Kitchen")
        #expect(route.systemImage == "airplayaudio")
    }

    @Test("AirPods get their own symbols, even when renamed with an owner's prefix", arguments: [
        ("AirPods", "airpods"),
        ("Matt's AirPods Pro", "airpodspro"),
        ("AirPods Max", "airpodsmax"),
        ("WH-1000XM5", "headphones"),
    ])
    func bluetoothSymbols(name: String, symbol: String) {
        let route = route((.bluetoothA2DP, name))
        #expect(route.isExternal)
        #expect(route.name == name)
        #expect(route.systemImage == symbol)
    }

    @Test("Each external port type maps to a fitting symbol", arguments: [
        (AVAudioSession.Port.headphones, "headphones"),
        (.bluetoothLE, "headphones"),
        (.bluetoothHFP, "headphones"),
        (.carAudio, "car"),
        (.HDMI, "tv"),
        (.displayPort, "tv"),
        (.usbAudio, "hifispeaker"),
        (.lineOut, "hifispeaker"),
    ])
    func portSymbols(port: AVAudioSession.Port, symbol: String) {
        let route = route((port, "Device"))
        #expect(route.isExternal)
        #expect(route.systemImage == symbol)
    }

    @Test("An external output wins over a built-in one listed before it")
    func externalWinsOverBuiltIn() {
        let route = route((.builtInSpeaker, "Speaker"), (.carAudio, "My Car"))
        #expect(route.isExternal)
        #expect(route.name == "My Car")
        #expect(route.systemImage == "car")
    }

    @Test("A blank port name falls back to a name for its type", arguments: [
        (AVAudioSession.Port.airPlay, "AirPlay"),
        (.bluetoothA2DP, "Bluetooth"),
        (.headphones, "Headphones"),
        (.carAudio, "Car"),
        (.HDMI, "HDMI"),
        (.virtual, "External Audio"),
    ])
    func blankNameFallsBack(port: AVAudioSession.Port, name: String) {
        #expect(route((port, "  ")).name == name)
    }
}
