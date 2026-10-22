import AVFoundation

enum MicrophonePermission {
    static var isGranted: Bool { AVAudioApplication.shared.recordPermission == .granted }
    static var isDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }

    /// Asks only if the user hasn't decided yet. Returns whether recording is allowed.
    static func request() async -> Bool {
        if isGranted { return true }
        if isDenied { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
