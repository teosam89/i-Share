import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The Maps key is never stored in source. It comes from Info.plist (GMSApiKey),
    // which is filled from the GOOGLE_MAPS_API_KEY build setting defined in the
    // git-ignored ios/Flutter/Secrets.xcconfig (copy Secrets.xcconfig.example).
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
       !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    } else {
      NSLog("GMSApiKey is empty: set GOOGLE_MAPS_API_KEY in ios/Flutter/Secrets.xcconfig")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
