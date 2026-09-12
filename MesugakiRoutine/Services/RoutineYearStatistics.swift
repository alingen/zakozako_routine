import Foundation

struct RoutineMonthStatistics: Identifiable, Equatable {
    let month: Int
    let completedCount: Int
    let applicableCount: Int

    var id: Int { month }
    var completionRate: Double {
        applicableCount == 0 ? 0 : Double(completedCount) / Double(applicableCount)
    }
}

struct RoutineWeekdayStatistics: Identifiable, Equatable {
    let weekday: Int
    let completedCount: Int

    var id: Int { weekday }
}

struct RoutineHourStatistics: Identifiable, Equatable {
    let hour: Int
    let completedCount: Int

    var id: Int { hour }
}

struct RoutineYearStatistics: Equatable {
    let year: Int
    let longestStreak: Int
    let completedCount: Int
    let applicableCount: Int
    let monthly: [RoutineMonthStatistics]
    let weekdays: [RoutineWeekdayStatistics]
    let hours: [RoutineHourStatistics]

    var completionRate: Double {
        applicableCount == 0 ? 0 : Double(completedCount) / Double(applicableCount)
    }
}

struct RoutineCompletionSummary: Equatable {
    let completedCount: Int
    let applicableCount: Int
    let unitLabel: String
}

enum RoutineStatisticsArchiveError: LocalizedError {
    case corrupted
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .corrupted:
            return "過去の達成記録を読み込めません。記録を保護するため、設定変更を中止しました。"
        case let .unsupportedVersion(version):
            return "新しい形式の達成記録（version \(version)）は、このアプリでは更新できません。"
        }
    }
}

/// 1つの達成ルールが有効だった期間内の、1日／1週／1か月ぶんの確定結果。
/// `segmentID` が変わる設定変更点では、連続記録もいったん区切る。
private struct RoutineStatisticsOutcome: Codable, Equatable {
    let segmentID: UUID
    let start: Date
    let end: Date
    let assignedDay: Date
    let completedAt: Date?
    let periodRawValue: String
}

private struct RoutineStatisticsArchiveEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let outcomes: [RoutineStatisticsOutcome]
}

private struct RoutineNaturalPeriodKey: Hashable {
    let periodRawValue: String
    let start: Date
}

/// 1つの約束の実行ログを、期間単位の達成状況へ変換する。
///
/// 各日／週／月の `targetCount` 件目の実行時刻だけを、その期間の「完了時刻」として扱う。
/// ルール変更前の結果は `Routine.progressStatisticsArchiveData` に確定保存し、変更後の
/// ルールで過去を再解釈しない。
enum RoutineYearStatisticsCalculator {
    static func calculate(
        routine: Routine,
        year: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RoutineYearStatistics {
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) else {
            return emptyStatistics(year: year, calendar: calendar)
        }

        let outcomes = allOutcomes(for: routine, now: now, calendar: calendar)
            .filter { $0.assignedDay >= yearStart && $0.assignedDay < yearEnd }
        let completedOutcomes = outcomes.filter { $0.completedAt != nil }

        let monthly = (1...12).map { month in
            let monthOutcomes = outcomes.filter {
                calendar.component(.month, from: $0.assignedDay) == month
            }
            return RoutineMonthStatistics(
                month: month,
                completedCount: monthOutcomes.filter { $0.completedAt != nil }.count,
                applicableCount: monthOutcomes.count
            )
        }

        var weekdayCounts = Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 0) })
        var hourCounts = Dictionary(uniqueKeysWithValues: (0...23).map { ($0, 0) })
        for completedAt in completedOutcomes.compactMap(\.completedAt) {
            // 曜日は朝4時の日付境界、時刻は実際の時計時刻で集計する。
            let weekday = calendar.component(
                .weekday,
                from: AppDay.anchor(completedAt, calendar: calendar)
            )
            let hour = calendar.component(.hour, from: completedAt)
            weekdayCounts[weekday, default: 0] += 1
            hourCounts[hour, default: 0] += 1
        }

        let weekdayOrder = orderedWeekdays(calendar: calendar)
        return RoutineYearStatistics(
            year: year,
            longestStreak: longestCompletedRun(in: outcomes),
            completedCount: completedOutcomes.count,
            applicableCount: outcomes.count,
            monthly: monthly,
            weekdays: weekdayOrder.map {
                RoutineWeekdayStatistics(weekday: $0, completedCount: weekdayCounts[$0, default: 0])
            },
            hours: (0...23).map {
                RoutineHourStatistics(hour: $0, completedCount: hourCounts[$0, default: 0])
            }
        )
    }

    /// ルール変更直前までの結果を確定し、以後の設定変更で書き換わらないよう保存する。
    static func archiveCurrentRule(
        for routine: Routine,
        until end: Date,
        calendar: Calendar = .current
    ) throws {
        // 復号できない既存履歴を空として上書きしない。ルール変更自体を止めて記録を保護する。
        var archive = try decodedArchivedOutcomes(for: routine)
        let historyStart = routine.currentRuleStartedAt
        guard historyStart < end else { return }

        let outcomes = liveOutcomes(
            for: routine,
            historyStart: historyStart,
            now: end,
            segmentID: UUID(),
            includeOpenIncompletePeriod: false,
            includesEventAtEnd: false,
            calendar: calendar
        )
        guard !outcomes.isEmpty else { return }

        archive.append(contentsOf: outcomes)
        routine.progressStatisticsArchiveData = try JSONEncoder().encode(
            RoutineStatisticsArchiveEnvelope(
                version: RoutineStatisticsArchiveEnvelope.currentVersion,
                outcomes: archive
            )
        )
    }

    /// 目標回数へ到達した実時刻をすべて返す。カレンダーと全体継続日数で共用する。
    static func completionDates(
        for routine: Routine,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        Array(
            Set(allOutcomes(for: routine, now: now, calendar: calendar).compactMap(\.completedAt))
        ).sorted()
    }

    /// 現在の達成ルール内で連続して完了した期間数。進行中の未達期間はまだ失敗にしない。
    static func currentStreak(
        for routine: Routine,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let historyStart = routine.currentRuleStartedAt
        var outcomes = liveOutcomes(
            for: routine,
            historyStart: historyStart,
            now: now,
            segmentID: UUID(),
            includeOpenIncompletePeriod: true,
            includesEventAtEnd: true,
            calendar: calendar
        )
        if let last = outcomes.last,
           last.completedAt == nil,
           last.end > now {
            outcomes.removeLast()
        }

        var streak = 0
        for outcome in outcomes.reversed() {
            guard outcome.completedAt != nil else { break }
            streak += 1
        }
        return streak
    }

    /// 指定日と重なる日／週／月の期間で、目標回数に到達した実時刻を返す。
    static func completionDate(
        for routine: Routine,
        inPeriodContaining date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Date? {
        let requestedStart = AppDay.startOfDay(for: date, calendar: calendar)
        let requestedEnd = calendar.date(byAdding: .day, value: 1, to: requestedStart) ?? requestedStart
        return allOutcomes(for: routine, now: now, calendar: calendar)
            .filter { $0.end > requestedStart && $0.start < requestedEnd }
            .compactMap(\.completedAt)
            .sorted()
            .first
    }

    /// 指定された業務日（朝4時から翌朝4時）に、目標回数へ到達したか。
    static func wasCompleted(
        _ routine: Routine,
        on appDay: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let requestedDay = AppDay.startOfDay(for: appDay, calendar: calendar)
        return completionDates(for: routine, now: now, calendar: calendar).contains {
            AppDay.startOfDay(for: $0, calendar: calendar) == requestedDay
        }
    }

    /// 朝4時区切りの直近N暦日と重なる、期間単位の日／週／月の達成数。
    static func recentSummary(
        for routine: Routine,
        trailingCalendarDays: Int = 30,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RoutineCompletionSummary {
        guard trailingCalendarDays > 0 else {
            return RoutineCompletionSummary(
                completedCount: 0,
                applicableCount: 0,
                unitLabel: unitLabel(for: routine.period)
            )
        }

        let today = calendar.startOfDay(for: AppDay.anchor(now, calendar: calendar))
        guard let firstCalendarDay = calendar.date(
            byAdding: .day,
            value: -(trailingCalendarDays - 1),
            to: today
        ), let rangeEnd = calendar.date(
            byAdding: .day,
            value: 1,
            to: AppDay.start(ofCalendarDay: today, calendar: calendar)
        ) else {
            return RoutineCompletionSummary(
                completedCount: 0,
                applicableCount: 0,
                unitLabel: unitLabel(for: routine.period)
            )
        }

        let rangeStart = AppDay.start(ofCalendarDay: firstCalendarDay, calendar: calendar)
        let outcomes = allOutcomes(for: routine, now: now, calendar: calendar)
            .filter { $0.end > rangeStart && $0.start < rangeEnd }
        let periods = Set(outcomes.compactMap { HabitPeriod(rawValue: $0.periodRawValue) })
        let naturalPeriods = Set(outcomes.compactMap { outcome -> RoutineNaturalPeriodKey? in
            guard let period = HabitPeriod(rawValue: outcome.periodRawValue) else { return nil }
            return RoutineNaturalPeriodKey(
                periodRawValue: outcome.periodRawValue,
                start: period.window(containing: outcome.start, calendar: calendar).start
            )
        })
        // 同じ暦日／週／月の途中でルールを変えて複数セグメントができた場合も、
        // 「2日」のように見せず、設定単位に依存しない「2件」と表示する。
        let usesGenericUnit = periods.count > 1 || naturalPeriods.count < outcomes.count
        return RoutineCompletionSummary(
            completedCount: outcomes.filter { $0.completedAt != nil }.count,
            applicableCount: outcomes.count,
            unitLabel: usesGenericUnit
                ? "件"
                : unitLabel(for: periods.first ?? routine.period)
        )
    }

    static func availableYears(
        for routine: Routine,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Int] {
        let currentYear = calendar.component(.year, from: AppDay.anchor(now, calendar: calendar))
        let outcomes = allOutcomes(for: routine, now: now, calendar: calendar)
        guard let oldestDay = outcomes.map(\.assignedDay).min() else { return [currentYear] }
        let oldestYear = calendar.component(.year, from: oldestDay)
        guard oldestYear <= currentYear else { return [currentYear] }
        return Array(oldestYear...currentYear)
    }

    private static func allOutcomes(
        for routine: Routine,
        now: Date,
        calendar: Calendar
    ) -> [RoutineStatisticsOutcome] {
        let liveStart = routine.currentRuleStartedAt
        let live = liveOutcomes(
            for: routine,
            historyStart: liveStart,
            now: now,
            segmentID: UUID(),
            includeOpenIncompletePeriod: true,
            includesEventAtEnd: true,
            calendar: calendar
        )
        return archivedOutcomes(for: routine) + live
    }

    private static func liveOutcomes(
        for routine: Routine,
        historyStart: Date,
        now: Date,
        segmentID: UUID,
        includeOpenIncompletePeriod: Bool,
        includesEventAtEnd: Bool,
        calendar: Calendar
    ) -> [RoutineStatisticsOutcome] {
        guard historyStart <= now else { return [] }

        let trackingDay = calendar.startOfDay(for: AppDay.anchor(historyStart, calendar: calendar))
        let currentAppDay = calendar.startOfDay(for: AppDay.anchor(now, calendar: calendar))
        let targetCount = max(routine.targetCount, 1)
        let events = routine.progressEvents
            .filter {
                $0 >= historyStart && (includesEventAtEnd ? $0 <= now : $0 < now)
            }
            .sorted()
        var eventsByPeriodStart: [Date: [Date]] = [:]
        for event in events {
            let window = routine.period.window(containing: event, calendar: calendar)
            eventsByPeriodStart[window.start, default: []].append(event)
        }

        var opportunities: [Date: DateInterval] = [:]
        var cursor = trackingDay
        while cursor <= currentAppDay {
            let appDay = AppDay.start(ofCalendarDay: cursor, calendar: calendar)
            if routine.period != .day || isScheduled(
                on: appDay,
                weekdayValues: routine.activeWeekdayValues,
                calendar: calendar
            ) {
                let window = routine.period.window(containing: appDay, calendar: calendar)
                if window.end > historyStart {
                    opportunities[window.start] = window
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return opportunities.values.compactMap { window in
            let periodEvents = eventsByPeriodStart[window.start] ?? []
            let completedAt = periodEvents.count >= targetCount
                ? periodEvents[targetCount - 1]
                : nil

            // 設定変更時点でまだ未達だった途中期間は、失敗として固定しない。
            if completedAt == nil, window.end > now, !includeOpenIncompletePeriod {
                return nil
            }

            let assignedDay: Date
            if let completedAt {
                assignedDay = calendar.startOfDay(
                    for: AppDay.anchor(completedAt, calendar: calendar)
                )
            } else if window.end <= now {
                assignedDay = lastCalendarDay(before: window.end, calendar: calendar)
            } else {
                assignedDay = currentAppDay
            }

            return RoutineStatisticsOutcome(
                segmentID: segmentID,
                start: max(window.start, historyStart),
                end: includeOpenIncompletePeriod ? window.end : min(window.end, now),
                assignedDay: max(assignedDay, trackingDay),
                completedAt: completedAt,
                periodRawValue: routine.period.rawValue
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func archivedOutcomes(for routine: Routine) -> [RoutineStatisticsOutcome] {
        (try? decodedArchivedOutcomes(for: routine)) ?? []
    }

    private static func decodedArchivedOutcomes(
        for routine: Routine
    ) throws -> [RoutineStatisticsOutcome] {
        guard let data = routine.progressStatisticsArchiveData else { return [] }
        let decoder = JSONDecoder()

        // version 1以降。未知versionは旧形式として読み替えず、必ず更新を止める。
        if let envelope = try? decoder.decode(RoutineStatisticsArchiveEnvelope.self, from: data) {
            guard envelope.version == RoutineStatisticsArchiveEnvelope.currentVersion else {
                throw RoutineStatisticsArchiveError.unsupportedVersion(envelope.version)
            }
            return envelope.outcomes
        }

        throw RoutineStatisticsArchiveError.corrupted
    }

    private static func isScheduled(
        on day: Date,
        weekdayValues: [Int],
        calendar: Calendar
    ) -> Bool {
        guard !weekdayValues.isEmpty else { return true }
        let weekday = calendar.component(.weekday, from: AppDay.anchor(day, calendar: calendar))
        return weekdayValues.contains(weekday)
    }

    private static func longestCompletedRun(in outcomes: [RoutineStatisticsOutcome]) -> Int {
        Dictionary(grouping: outcomes, by: \.segmentID).values.reduce(0) { longest, segment in
            var segmentLongest = 0
            var current = 0
            for outcome in segment.sorted(by: { $0.start < $1.start }) {
                if outcome.completedAt != nil {
                    current += 1
                    segmentLongest = max(segmentLongest, current)
                } else {
                    current = 0
                }
            }
            return max(longest, segmentLongest)
        }
    }

    private static func lastCalendarDay(before periodEnd: Date, calendar: Calendar) -> Date {
        let endCalendarDay = calendar.startOfDay(
            for: AppDay.anchor(periodEnd, calendar: calendar)
        )
        return calendar.date(byAdding: .day, value: -1, to: endCalendarDay) ?? endCalendarDay
    }

    private static func orderedWeekdays(calendar: Calendar) -> [Int] {
        (0..<7).map { offset in
            ((calendar.firstWeekday - 1 + offset) % 7) + 1
        }
    }

    private static func unitLabel(for period: HabitPeriod) -> String {
        switch period {
        case .day: return "日"
        case .week: return "週"
        case .month: return "か月"
        }
    }

    private static func emptyStatistics(year: Int, calendar: Calendar) -> RoutineYearStatistics {
        RoutineYearStatistics(
            year: year,
            longestStreak: 0,
            completedCount: 0,
            applicableCount: 0,
            monthly: (1...12).map {
                RoutineMonthStatistics(month: $0, completedCount: 0, applicableCount: 0)
            },
            weekdays: orderedWeekdays(calendar: calendar).map {
                RoutineWeekdayStatistics(weekday: $0, completedCount: 0)
            },
            hours: (0...23).map {
                RoutineHourStatistics(hour: $0, completedCount: 0)
            }
        )
    }
}
