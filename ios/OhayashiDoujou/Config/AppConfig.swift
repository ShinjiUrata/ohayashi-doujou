import Foundation

/// 環境別の URL や設定を保持する。
///
/// URL は xcconfig で定義され、Info.plist を経由して読み込まれる。
///  - Debug.xcconfig: API_BASE_URL = https://api-y24cifx6uq-an.a.run.app
///  - Release.xcconfig: API_BASE_URL = https://api-p4eslkaoea-an.a.run.app
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

  /// Cloud Run API の URL(Debug/Release で別)。
  public static var apiBaseURL: URL {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
          let url = URL(string: raw), !raw.isEmpty else {
      fatalError("Info.plist の APIBaseURL が未設定または不正")
    }
    return url
  }

  /// Cloud Storage 譜面バケットの URL 接頭辞。個別譜面は `<prefix>/<id>.json` で取得。
  public static var chartsBaseURL: URL {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "ChartsBaseURL") as? String,
          let url = URL(string: raw), !raw.isEmpty else {
      fatalError("Info.plist の ChartsBaseURL が未設定または不正")
    }
    return url
  }

  /// 譜面公開 IAP のプロダクト ID(Debug/Release で別)。
  ///
  /// App Store Connect のチーム内で IAP プロダクト ID は一意制約があるため、
  /// dev アプリレコード用に `.dev` サフィックス付きの別 ID を用意している。
  ///  - Debug: `rhythm.chart.publish.single.dev`(お囃子道場 (Dev) アプリ)
  ///  - Release: `rhythm.chart.publish.single`(お囃子道場 アプリ)
  public static var iapPublishProductID: String {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "IAPPublishProductID") as? String,
          !raw.isEmpty else {
      fatalError("Info.plist の IAPPublishProductID が未設定または不正")
    }
    return raw
  }
}
