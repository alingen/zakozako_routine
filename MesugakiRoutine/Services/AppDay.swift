import Foundation

/// アプリ内で「1日」を数える基準。深夜のちょっとした夜更かしで日付が変わって
/// 連続記録が途切れたりしないよう、日付の境界を 0時ではなく朝4時にしている
/// (習慣トラッカーでよくある「day start time」)。
///
/// 「約束」「やらないこと」の期間集計(日/週/月)・対象曜日判定・連続達成日数の
/// 計算はすべてここを経由する。通知の発火時刻(何時何分に鳴らすか)自体には関係ない。
enum AppDay {
    /// この時刻(0〜23時)に日付が切り替わる。
    static let startHour = 4

    /// 実時刻を、日付境界が `startHour` になるよう補正した時刻に変換する。
    /// 例: startHour=4 のとき、深夜1時は前日の21時として扱われる。
    /// `Calendar.component(.weekday:)` など「その瞬間がどの暦日か」を調べる時に使う。
    static func anchor(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .hour, value: -startHour, to: date) ?? date
    }

    /// `date`(実時刻の一点)が属する「業務日」の開始時刻(実時刻。例: 朝4時)を返す。
    static func startOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        let anchoredStart = calendar.startOfDay(for: anchor(date, calendar: calendar))
        return calendar.date(byAdding: .hour, value: startHour, to: anchoredStart) ?? anchoredStart
    }

    /// カレンダー上の「その日」のラベル(0時などの代表値。月間カレンダーのマス目など)を、
    /// その日に対応する業務日の開始時刻(例: その日の朝4時)に変換する。
    /// `startOfDay(for:)` とは向きが逆(こちらはラベル→期間、あちらは瞬間→期間)。
    static func start(ofCalendarDay day: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: startHour, to: midnight) ?? midnight
    }
}
