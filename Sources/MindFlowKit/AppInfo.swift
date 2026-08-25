import Foundation

/// App metadata read from the packaged Info.plist (falls back for dev runs).
public enum AppInfo {
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}