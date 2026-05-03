import AVFoundation
import Foundation

@MainActor
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-input-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        recorder.record()
        self.recorder = recorder
        return url
    }

    func stop() {
        recorder?.stop()
        recorder = nil
    }
}
