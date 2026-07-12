import Foundation

/// ルーティンの対象曜日。rawValueは `Calendar.current.component(.weekday, from:)` の値(1=日曜〜7=土曜)に合わせている。
enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    case sunday = 1

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .monday: return "月"
        case .tuesday: return "火"
        case .wednesday: return "水"
        case .thursday: return "木"
        case .friday: return "金"
        case .saturday: return "土"
        case .sunday: return "日"
        }
    }

    static var allWeekdayValues: [Int] { allCases.map(\.rawValue) }
}
