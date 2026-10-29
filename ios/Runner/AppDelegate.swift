import AVFoundation
import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Scoped to a user tap: never continuously listens to the microphone or
  // the device audio. The audio comes from a bounded excerpt of the movie URL.
  private let speechSync = SpeechSubtitleSync()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "playtorrio/speech_subtitle_sync",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, callback in
      guard call.method == "transcribeExcerpt" else {
        callback(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let location = arguments["mediaUrl"] as? String,
            let start = (arguments["startSeconds"] as? NSNumber)?.doubleValue,
            let duration = (arguments["durationSeconds"] as? NSNumber)?.doubleValue else {
        callback(FlutterError(code: "invalid_args", message: "Missing playback excerpt", details: nil))
        return
      }
      self?.speechSync.transcribe(location: location, start: start,
                                 duration: duration, callback: callback)
    }
  }
}

/// Uses Apple's built-in, on-device Speech recognizer to transcribe only a
/// 75-second excerpt exported from a playable local/HTTP AVFoundation asset.
/// The app does not capture the microphone and does not upload audio to a third
/// party. Unsupported files and streams fail visibly without changing captions.
private final class SpeechSubtitleSync {
  private var exporter: AVAssetExportSession?
  private var speechTask: SFSpeechRecognitionTask?
  private var timeout: Timer?
  private var temporaryAudio: URL?
  private var pending: FlutterResult?
  private var excerptStart = 0.0

  func transcribe(location: String, start: Double, duration: Double,
                  callback: @escaping FlutterResult) {
    guard pending == nil else {
      callback(FlutterError(code: "busy", message: "Speech sync is already running.", details: nil))
      return
    }
    guard start.isFinite, duration.isFinite, start >= 0,
          duration >= 15, duration <= 80 else {
      callback(FlutterError(code: "invalid_range", message: "Invalid audio sample range.", details: nil))
      return
    }

    let mediaURL: URL
    if location.hasPrefix("/") {
      mediaURL = URL(fileURLWithPath: location)
    } else if let candidate = URL(string: location),
              ["https", "http", "file"].contains(candidate.scheme?.lowercased() ?? "") {
      mediaURL = candidate
    } else {
      callback(FlutterError(code: "unsupported_source",
                            message: "Speech sync needs a local file or directly readable HTTP video.",
                            details: nil))
      return
    }

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
          recognizer.supportsOnDeviceRecognition else {
      callback(FlutterError(code: "speech_unavailable",
                            message: "English on-device speech recognition is not available on this iPad.",
                            details: nil))
      return
    }

    pending = callback
    excerptStart = start
    timeout = Timer.scheduledTimer(withTimeInterval: 105, repeats: false) { [weak self] _ in
      self?.finishFailure("timeout", "Speech alignment timed out. Subtitle timing was not changed.")
    }
    SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
      DispatchQueue.main.async {
        guard let self = self, self.pending != nil else { return }
        guard authorization == .authorized else {
          self.finishFailure("speech_permission",
            "Allow Speech Recognition in iOS Settings to align subtitles to spoken audio.")
          return
        }
        self.exportExcerpt(mediaURL, start: start, duration: duration,
                           recognizer: recognizer)
      }
    }
  }

  private func exportExcerpt(_ mediaURL: URL, start: Double, duration: Double,
                             recognizer: SFSpeechRecognizer) {
    let asset = AVURLAsset(url: mediaURL)
    guard let session = AVAssetExportSession(
      asset: asset, presetName: AVAssetExportPresetAppleM4A
    ) else {
      finishFailure("unsupported_media",
        "iOS cannot extract audio from this video format or streaming URL. Try an MP4/HLS source.")
      return
    }
    let audioURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("ptv-speech-\(UUID().uuidString).m4a")
    session.outputURL = audioURL
    session.outputFileType = .m4a
    session.shouldOptimizeForNetworkUse = false
    session.timeRange = CMTimeRange(
      start: CMTime(seconds: start, preferredTimescale: 600),
      duration: CMTime(seconds: duration, preferredTimescale: 600)
    )
    temporaryAudio = audioURL
    exporter = session
    session.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, self.pending != nil else { return }
        guard session.status == .completed else {
          self.finishFailure("audio_extract_failed",
            "iOS could not read this stream's audio. Try another MP4/HLS source.")
          return
        }
        self.recognizeFile(audioURL, recognizer: recognizer)
      }
    }
  }

  private func recognizeFile(_ url: URL, recognizer: SFSpeechRecognizer) {
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false
    request.taskHint = .dictation
    speechTask = recognizer.recognitionTask(with: request) { [weak self] transcript, error in
      DispatchQueue.main.async {
        guard let self = self, self.pending != nil else { return }
        if let recognized = transcript, recognized.isFinal {
          // Never return the full transcript to logs or permanent storage.
          let words = recognized.bestTranscription.segments.prefix(600).map { word in
            [
              "text": word.substring,
              "startSeconds": self.excerptStart + word.timestamp
            ] as [String: Any]
          }
          if words.isEmpty {
            self.finishFailure("no_speech", "No recognizable English speech found in this sample.")
          } else {
            self.finishSuccess(words)
          }
        } else if error != nil {
          self.finishFailure("recognition_failed",
            "On-device speech recognition failed. Subtitle timing was not changed.")
        }
      }
    }
  }

  private func finishSuccess(_ words: [[String: Any]]) {
    guard let callback = pending else { return }
    pending = nil
    cleanup()
    callback(["words": words])
  }

  private func finishFailure(_ code: String, _ message: String) {
    guard let callback = pending else { return }
    pending = nil
    cleanup()
    callback(FlutterError(code: code, message: message, details: nil))
  }

  private func cleanup() {
    timeout?.invalidate()
    timeout = nil
    exporter?.cancelExport()
    exporter = nil
    speechTask?.cancel()
    speechTask = nil
    if let file = temporaryAudio {
      try? FileManager.default.removeItem(at: file)
    }
    temporaryAudio = nil
  }
}
