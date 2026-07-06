import Foundation

/// 環境別の URL や設定を保持する。
///
/// Phase 1 段階では URL 系は未使用(Phase 4 で追加)。
/// Debug/Release の分岐は xcconfig 経由で管理する予定。
public enum AppConfig {
  /// 現在のビルドが Debug かどうか。
  public static var isDebug: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
  }

  /// 表示用のアプリバージョン。
  public static var displayVersion: String {
    let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    return "\(short) (\(build))"
  }
}
