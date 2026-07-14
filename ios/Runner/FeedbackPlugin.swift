import Flutter
import UIKit
import AVFoundation

public class SwiftFeedbackPlugin: NSObject, FlutterPlugin {
  private var audioPlayer: AVAudioPlayer?
  private var soundData: Data?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.example.pos/feedback",
      binaryMessenger: registrar.messenger()
    )
    let instance = SwiftFeedbackPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
