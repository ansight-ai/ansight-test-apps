#!/usr/bin/env swift
// Play a fixture into an explicitly selected CoreAudio output, such as BlackHole 2ch.
// This never changes the Mac's default input, output, or system-sound device.
// Usage: ./scripts/play-to-audio-device.sh --list
//        ./scripts/play-to-audio-device.sh --device "BlackHole 2ch" fixtures/audio/expected.wav
// Optional: --lead-in 1 --tail 1 keeps the selected output open and silent around playback.
// --list returns JSON. Prefer a device UID when multiple devices have the same name.

import AVFoundation
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

private struct PlayerError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct AudioDevice: Codable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let inputChannels: Int
    let outputChannels: Int
}

private struct Options {
    var list = false
    var help = false
    var device: String?
    var file: String?
    var leadIn: TimeInterval = 0
    var tail: TimeInterval = 0.5
}

private final class PlaybackState: @unchecked Sendable {
    private let gate = NSLock()
    private var didFinish = false
    private var interrupted = false

    func finish() { gate.lock(); defer { gate.unlock() }; didFinish = true }
    func interrupt() { gate.lock(); defer { gate.unlock() }; interrupted = true }
    var finished: Bool { gate.lock(); defer { gate.unlock() }; return didFinish }
    var cancelled: Bool { gate.lock(); defer { gate.unlock() }; return interrupted }
}

private func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw PlayerError(message: "\(operation) failed (CoreAudio OSStatus \(status)).")
    }
}

private func stringProperty(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    let storage = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
    storage.initialize(to: nil)
    defer { storage.deinitialize(count: 1); storage.deallocate() }
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage), "Reading device identity")
    guard let value = storage.pointee else { throw PlayerError(message: "Device \(device) returned an empty identity.") }
    return value.takeRetainedValue() as String
}

private func channelCount(_ device: AudioDeviceID, _ scope: AudioObjectPropertyScope) throws -> Int {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size), "Reading device channel count")
    guard size > 0 else { return 0 }
    let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { storage.deallocate() }
    try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage), "Reading device channels")
    let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
    return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
}

private func listDevices() throws -> [AudioDevice] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size), "Enumerating audio devices")
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard !ids.isEmpty else { return [] }
    let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!) }
    try check(status, "Enumerating audio devices")
    return try ids.map { device in
        AudioDevice(id: device, name: try stringProperty(device, kAudioObjectPropertyName),
                    uid: try stringProperty(device, kAudioDevicePropertyDeviceUID),
                    inputChannels: try channelCount(device, kAudioObjectPropertyScopeInput),
                    outputChannels: try channelCount(device, kAudioObjectPropertyScopeOutput))
    }
}

private func parseOptions() throws -> Options {
    var options = Options()
    let arguments = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--list": options.list = true
        case "--help", "-h": options.help = true
        case "--device", "--lead-in", "--tail":
            index += 1
            guard index < arguments.count else { throw PlayerError(message: "\(argument) requires a value.") }
            let value = arguments[index]
            if argument == "--device" { options.device = value }
            else {
                guard let seconds = Double(value), seconds.isFinite, (0...30).contains(seconds) else {
                    throw PlayerError(message: "\(argument) must be a number between 0 and 30 seconds.")
                }
                if argument == "--lead-in" { options.leadIn = seconds } else { options.tail = seconds }
            }
        default:
            guard !argument.hasPrefix("-"), options.file == nil else { throw PlayerError(message: "Unexpected argument: \(argument)") }
            options.file = argument
        }
        index += 1
    }
    if options.help { return options }
    if options.list {
        guard arguments.count == 1 else { throw PlayerError(message: "Use --list on its own.") }
    } else if options.device == nil || options.file == nil {
        throw PlayerError(message: "Supply --device <exact name or UID> and an audio file, or use --list.")
    }
    return options
}

private func verifyRoute(_ unit: AudioUnit, _ device: AudioDevice) throws {
    var current: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    try check(AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &current, &size),
              "Checking this player's output device")
    guard current == device.id else { throw PlayerError(message: "The player lost the selected output device. Playback stopped.") }
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var alive: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    try check(AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &alive), "Checking selected device availability")
    guard alive != 0 else { throw PlayerError(message: "The selected output device disconnected. Playback stopped.") }
}

private func wait(until deadline: Date, state: PlaybackState, unit: AudioUnit, device: AudioDevice,
                  finishOnPlayback: Bool = false) throws -> Bool {
    while Date() < deadline {
        if state.cancelled { throw PlayerError(message: "Playback cancelled.") }
        try verifyRoute(unit, device)
        if finishOnPlayback && state.finished { return true }
        // Service the main run loop while CoreAudio renders on its own real-time thread.
        if !RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) {
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
    if state.cancelled { throw PlayerError(message: "Playback cancelled.") }
    try verifyRoute(unit, device)
    return state.finished
}

private func play(_ options: Options) throws {
    let selector = options.device!
    let devices = try listDevices().filter { $0.name == selector || $0.uid == selector }
    guard !devices.isEmpty else { throw PlayerError(message: "Audio device '\(selector)' was not found. Run --list; install BlackHole 2ch if needed.") }
    guard devices.count == 1 else { throw PlayerError(message: "More than one device matches '\(selector)'. Select its exact UID from --list.") }
    let device = devices[0]
    guard device.outputChannels > 0 else { throw PlayerError(message: "'\(device.name)' has no output channels.") }
    let url = URL(fileURLWithPath: (options.file! as NSString).expandingTildeInPath)
    guard FileManager.default.isReadableFile(atPath: url.path) else { throw PlayerError(message: "Cannot read audio file: \(url.path)") }
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.processingFormat.sampleRate > 0 else { throw PlayerError(message: "The audio file contains no playable samples.") }
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let state = PlaybackState()
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    defer { player.stop(); engine.stop() }
    guard let unit = engine.outputNode.audioUnit else { throw PlayerError(message: "CoreAudio did not provide an output audio unit.") }

    // This sets an AudioUnit property on this engine only. Never set hardware default-device properties.
    var deviceID = device.id
    try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                   &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)), "Selecting '\(device.name)' for this player")
    try verifyRoute(unit, device)
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    interrupt.setEventHandler { state.interrupt() }
    terminate.setEventHandler { state.interrupt() }
    interrupt.resume()
    terminate.resume()
    defer { interrupt.cancel(); terminate.cancel() }

    // Print and flush the exact destination before starting the output engine.
    print("DEVICE name=\(device.name) uid=\(device.uid) id=\(device.id) outputChannels=\(device.outputChannels)")
    print("FILE path=\(url.path) seconds=\(String(format: "%.3f", duration)) sampleRate=\(file.processingFormat.sampleRate) channels=\(file.processingFormat.channelCount)")
    fflush(stdout)
    engine.prepare()
    try engine.start()
    try verifyRoute(unit, device)
    print("READY leadInSeconds=\(options.leadIn) tailSeconds=\(options.tail)")
    fflush(stdout)
    _ = try wait(until: Date().addingTimeInterval(options.leadIn), state: state, unit: unit, device: device)
    player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { callback in
        if callback == .dataPlayedBack { state.finish() }
    }
    player.play()
    guard try wait(until: Date().addingTimeInterval(duration + 15), state: state, unit: unit, device: device, finishOnPlayback: true) else {
        throw PlayerError(message: "Timed out waiting for the file to finish playing through the selected audio device.")
    }
    _ = try wait(until: Date().addingTimeInterval(options.tail), state: state, unit: unit, device: device)
    print("COMPLETED uid=\(device.uid) frames=\(file.length)")
}

do {
    let options = try parseOptions()
    if options.help {
        print("Usage: play-to-audio-device.sh --list\n       play-to-audio-device.sh --device <exact name or UID> [--lead-in seconds] [--tail seconds] <audio-file>\n\nPlays at real-time speed through one explicit output. Default tail silence: 0.5 seconds. System audio defaults are preserved.")
    } else if options.list {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(listDevices()), as: UTF8.self))
    } else {
        try play(options)
    }
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
    exit(1)
}
