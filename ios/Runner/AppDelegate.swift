import Flutter
import UIKit
import GoogleSignIn
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let registrar = self.registrar(forPlugin: "SwiftFeedbackPlugin") {
      SwiftFeedbackPlugin.register(with: registrar)
    }
    return result
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let handled = super.application(app, open: url, options: options)
    if GIDSignIn.sharedInstance.handle(url) { return true }
    return handled
  }
}

class SwiftFeedbackPlugin: NSObject, FlutterPlugin {
  private var audioPlayer: AVAudioPlayer?
  private var soundData: Data?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.example.pos/feedback",
      binaryMessenger: registrar.messenger()
    )
    let instance = SwiftFeedbackPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      result(true)
    case "loadSound":
      if let args = call.arguments as? FlutterStandardTypedData {
        soundData = args.data
        result(true)
      } else {
        result(false)
      }
    case "playBeep":
      playSound(volume: 1.0, rate: 1.0)
      result(true)
    case "playError":
      playSound(volume: 0.8, rate: 0.85)
      result(true)
    case "playSuccess":
      playSound(volume: 1.0, rate: 1.2)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func playSound(volume: Float, rate: Float) {
    guard let data = soundData else { return }
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    try? AVAudioSession.sharedInstance().setActive(true)
    let player = try? AVAudioPlayer(data: data)
    player?.volume = volume
    player?.enableRate = true
    player?.rate = rate
    player?.prepareToPlay()
    player?.play()
    audioPlayer = player
  }
}
