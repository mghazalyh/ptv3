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
      let allowAppleNetworkRecognition = arguments["allowAppleNetworkRecognition"] as? Bool ?? false
      self?.speechSync.transcribe(
        location: location,
        start: start,
        duration: duration,
        allowAppleNetworkRecognition: allowAppleNetworkRecognition,
        callback: callback
      )
    }
  }
}

/// Uses Apple's Speech recognizer to transcribe a bounded video-audio excerpt.
/// Prefers offline recognition. If unavailable, Apple's network-based
/// recognition is allowed ONLY after separate in-app opt-in for this attempt.
/// The microphone is never captured and the app does not operate its own
/// speech-recognition server. Unsupported audio leaves captions unchanged.
private final class SpeechSubtitleSync {
  private var exporter: AVAssetExportSession?
  private var speechTask: SFSpeechRecognitionTask?
  private var timeout: Timer?
  private var temporaryAudio: URL?
  private var pending: FlutterResult?
  private var excerptStart = 0.0

  func transcribe(location: String, start: Double, duration: Double,
                  allowAppleNetworkRecognition: Bool,
                  callback: @escaping FlutterResult) {
    guard pending == nil else {
      callback(FlutterError(code: "busy", message: "Speech sync is already running.", details: nil))
      return
    }
    guard start.isFinite, duration.isFinite, start >= 0,
          duration >= 15, duration <= 55 else {
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

    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
      callback(FlutterError(code: "speech_unavailable",
                            message: "English speech recognition is unsupported by this iPad.",
                            details: nil))
      return
    }

    // Never silently upload movie audio. When an offline speech model is not
    // supported, Flutter first shows a consent dialog; the caller must
    // explicitly approve this single network-assisted attempt.
    let onDeviceOnly = recognizer.supportsOnDeviceRecognition
    if !onDeviceOnly && !allowAppleNetworkRecognition {
      callback(FlutterError(
        code: "network_required",
        message: "This iPad needs Apple's online speech recognition service.",
        details: nil
      ))
      return
    }
    guard recognizer.isAvailable else {
      callback(FlutterError(
        code: "speech_service_unavailable",
        message: "Apple's speech recognition service is unavailable. Check internet and Speech Recognition settings.",
        details: nil
      ))
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
                           recognizer: recognizer, onDeviceOnly: onDeviceOnly)
      }
    }
  }

  private func exportExcerpt(_ mediaURL: URL, start: Double, duration: Double,
                             recognizer: SFSpeechRecognizer,
                             onDeviceOnly: Bool) {
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
        self.recognizeFile(audioURL, recognizer: recognizer,
                           onDeviceOnly: onDeviceOnly)
      }
    }
  }

  private func recognizeFile(_ url: URL, recognizer: SFSpeechRecognizer,
                             onDeviceOnly: Bool) {
    let request = SFSpeechURLRecognitionRequest(url: url)
    // False explicitly permits Apple's server only after the user's approval
    // in the Flutter consent dialog. True keeps audio on the device.
    request.requiresOnDeviceRecognition = onDeviceOnly
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
          if onDeviceOnly {
            self.finishFailure("offline_recognition_failed",
              "Offline English recognition failed; Apple's online service may work with consent.")
          } else {
            self.finishFailure("recognition_failed",
              "Apple online speech recognition failed. Check internet or Speech permission.")
          }
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
