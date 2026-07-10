import Foundation
import SwiftData

/// ユーザーが「やらないと決めた行動」。triggerText はユーザー入力とのマッチング用キーワード。
@Model
final class BlockedBehavior {
    @Attribute(.unique) var id: UUID
    var title: String
    var behaviorDescription: String
    var triggerText: String
    var counterMessage: String
    /// この行動の代わりに勧める行動(例: 「水を飲む」)。空文字なら特に勧めない。
    var alternativeAction: String = ""
    /// 検出を有効にする時間帯(0〜1439分、真夜中またぎも可)。どちらか nil なら常に検出する。
    var activeStartMinute: Int?
    var activeEndMinute: Int?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        behaviorDescription: String = "",
        triggerText: String = "",
        counterMessage: String = "",
        alternativeAction: String = "",
        activeStartMinute: Int? = nil,
        activeEndMinute: Int? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.behaviorDescription = behaviorDescription
        self.triggerText = triggerText
        self.counterMessage = counterMessage
        self.alternativeAction = alternativeAction
        self.activeStartMinute = activeStartMinute
        self.activeEndMinute = activeEndMinute
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 指定した日時が、この行動の検出対象時間帯に入っているか。時間帯未指定なら常に true。
    func isWithinActiveWindow(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let start = activeStartMinute, let end = activeEndMinute else { return true }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if start <= end {
            return (start...end).contains(currentMinute)
        } else {
            // 例: 22:00〜翌6:00 のような日をまたぐ時間帯
            return currentMinute >= start || currentMinute <= end
        }
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}
