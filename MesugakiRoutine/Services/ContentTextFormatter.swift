import Foundation

/// シナリオ・交流・リアクションに共通するCMSの表記。スラッシュは通常の文字。
extension String {
    func replacingStoryTextMarkers() -> String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[br]", with: "\n")
            .replacingOccurrences(of: "[sp]", with: " ")
    }
}
