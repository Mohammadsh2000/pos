import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioPlayer: AVAudioPlayer?
  private var soundData: Data?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "com.example.pos/feedback",
      binaryMessenger: engineBridge.pluginRegistry.registrar(forPlugin: "com.example.pos.feedback")!.messenger()
    )
    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "isAvailable":
        result(true)
      case "loadSound":
        if let args = call.arguments as? FlutterStandardTypedData {
          self?.soundData = args.data
          result(true)
        } else {
          result(false)
        }
      case "playBeep":
        self?.playSound(volume: 1.0, rate: 1.0)
        result(true)
      case "playError":
        self?.playSound(volume: 0.8, rate: 0.85)
        result(true)
      case "playSuccess":
        self?.playSound(volume: 1.0, rate: 1.2)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
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
