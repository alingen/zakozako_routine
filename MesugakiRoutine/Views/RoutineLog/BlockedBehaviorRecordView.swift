import SwiftUI

/// 「やらないこと」1件の記録画面。月ごとの勝ち負けと、日ごとの ○ / × をカレンダーで見せる。
struct BlockedBehaviorRecordView: View {
    let behavior: BlockedBehavior

    @State private var displayedMonth: Date
    private let calendar: Calendar
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    init(behavior: BlockedBehavior, calendar: Calendar = .current) {
        self.behavior = behavior
        self.calendar = calendar
        let today = AppDay.anchor(.now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month], from: today)
        _displayedMonth = State(initialValue: calendar.date(from: components) ?? today)
    }

    var body: some View {
        let history = BlockedBehaviorHistory(behavior: behavior, calendar: calendar)

        ScrollView {
            VStack(spacing: 16) {
                header
                monthHeader
                summaryCard(history)
                calendarCard(history)
            }
            .padding()
        }
        .background(AppColor.background)
        .navigationTitle("やらないことの記録")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 12) {
            // 記録の一覧と同じく Purple にそろえる(Primary は飾りに使わない)。
            Image(systemName: behavior.iconName ?? "nosign")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppColor.secondary)
                .frame(width: 48, height: 48)
                .background(AppColor.secondary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(behavior.title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                    .lineLimit(2)
                Text(ruleText)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    /// 「1日1回まで」「1日20分まで」のような決まりの説明。
    private var ruleText: String {
        switch behavior.trackingKind {
        case .screenTime:
            return "1日\(formattedMinutes(behavior.screenTimeLimitMinutes))まで"
        case .manual:
            return "\(behavior.limitPeriod.pickerLabel)\(behavior.effectiveLimit)回まで"
        }
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)分" }
        if rest == 0 { return "\(hours)時間" }
        return "\(hours)時間\(rest)分"
    }

    // MARK: - 月送り

    private var monthHeader: some View {
        HStack {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("前の月")

            Spacer()
            Text(displayedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
                .foregroundStyle(AppColor.text)
            Spacer()

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("次の月")
        }
        // 矢印は「今押すべき操作」ではないので Primary にしない。
        .foregroundStyle(AppColor.text)
    }

    private func moveMonth(by value: Int) {
        guard let month = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = month
    }

    // MARK: - 勝ち負け・連続

    private func summaryCard(_ history: BlockedBehaviorHistory) -> some View {
        let monthCount = history.count(inMonthContaining: displayedMonth)
        let monthNumber = calendar.component(.month, from: displayedMonth)

        return HStack(alignment: .top, spacing: 0) {
            stat(label: "\(monthNumber)月", value: "\(monthCount.kept)勝 \(monthCount.lost)敗")
            stat(label: "連続", value: "\(history.currentStreak)日")
            stat(label: "最長", value: "\(history.longestStreak)日")
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AppColor.muted)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(AppColor.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - カレンダー

    private func calendarCard(_ history: BlockedBehaviorHistory) -> some View {
        VStack(spacing: 12) {
            HStack {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(daysInDisplayedMonth().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, outcome: history.outcome(onCalendarDay: day))
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }

            HStack(spacing: 16) {
                legend(mark: .kept, text: "守れた")
                legend(mark: .lost, text: "負けた")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(AppColor.text)
        }
        .padding()
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    private func dayCell(_ day: Date, outcome: BlockedBehaviorDayOutcome?) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: AppDay.anchor(.now, calendar: calendar))

        return VStack(spacing: 4) {
            CalendarDayNumber(day: calendar.component(.day, from: day), isToday: isToday)

            outcomeMark(outcome)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(day, outcome: outcome))
    }

    @ViewBuilder
    private func outcomeMark(_ outcome: BlockedBehaviorDayOutcome?) -> some View {
        switch outcome {
        case .kept:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColor.secondary)
        case .lost:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColor.error)
        case nil:
            Color.clear
        }
    }

    private func legend(mark: BlockedBehaviorDayOutcome, text: String) -> some View {
        HStack(spacing: 4) {
            outcomeMark(mark)
                .accessibilityHidden(true)
            Text(text)
        }
    }

    private func dayAccessibilityLabel(_ day: Date, outcome: BlockedBehaviorDayOutcome?) -> String {
        let dateLabel = day.formatted(.dateTime.month().day().weekday(.wide))
        switch outcome {
        case .kept: return "\(dateLabel)、守れた"
        case .lost: return "\(dateLabel)、負けた"
        case nil: return "\(dateLabel)、記録なし"
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private func daysInDisplayedMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let weekdayOfFirst = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmptyCount = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyCount)
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        while days.count % 7 != 0 {
            days.append(nil)
        }
        return days
    }
}
