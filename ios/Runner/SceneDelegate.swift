import Flutter
import UIKit
import GoogleSignIn

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    if let url = URLContexts.first?.url {
      if GIDSignIn.sharedInstance.handle(url) { return }
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
