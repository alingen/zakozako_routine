import Foundation
import SwiftData

/// ユーザーが「やらないと決めた行動」。悪習慣を1つずつ潰していく想定で、同時に挑戦中(`isActive`)に
/// できるのは1件のみ(`BlockedBehaviorRepository`側で担保する)。triggerText はユーザー入力との
/// マッチング用キーワード。
@Model
final class BlockedBehavior {
    @Attribute(.unique) var id: UUID
    var title: String
    var triggerText: String
    var counterMessage: String
    /// この行動をやめる理由(例: 「仕事をさぼらないため」)。「負けそう」ボタンを押した時、\
    /// キャラクターがこれを引き合いに出してからかう材料として使う。空文字なら特に触れない。
    var reason: String = ""
    /// この行動の代わりに勧める具体的な行動(例: 「音楽をかける」)。「負けそう」ボタンを押した時、\
    /// 煽り・理由に続けて実際にやることとして勧める。空文字なら特に勧めない。
    var alternativeAction: String = ""
    /// 検出を有効にする時間帯(0〜1439分、真夜中またぎも可)。どちらか nil なら常に検出する。
    var activeStartMinute: Int?
    var activeEndMinute: Int?
    /// 現在挑戦中かどうか。true になれるのは同時に1件のみ。
    var isActive: Bool
    /// 「まもれた/まもれなかった」の記録が続いている連続日数。まもれなかった日があると0にリセットされる。
    var currentStreakDays: Int = 0
    /// 直近で「まもれた/まもれなかった」を記録した対象日(前日分を記録するため、記録した日の前日の日付が入る)。
    var lastCheckInDate: Date?
    /// 14日間守り切って「卒業」した日時。nilならまだ挑戦中。
    var masteredAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        triggerText: String = "",
        counterMessage: String = "",
        reason: String = "",
        alternativeAction: String = "",
        activeStartMinute: Int? = nil,
        activeEndMinute: Int? = nil,
        isActive: Bool = true,
        currentStreakDays: Int = 0,
        lastCheckInDate: Date? = nil,
        masteredAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.triggerText = triggerText
        self.counterMessage = counterMessage
        self.reason = reason
        self.alternativeAction = alternativeAction
        self.activeStartMinute = activeStartMinute
        self.activeEndMinute = activeEndMinute
        self.isActive = isActive
        self.currentStreakDays = currentStreakDays
        self.lastCheckInDate = lastCheckInDate
        self.masteredAt = masteredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 14日間の達成に必要な連続日数。
    static let masteryStreakDays = 14

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
