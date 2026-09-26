import SwiftUI

struct RoutineLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel = RoutineLogViewModel()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summarySection
                calendarSection
            }
            .padding()
        }
        .background(AppColor.background)
        .navigationTitle("記録")
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
    }

    private var summarySection: some View {
        // 各行は最低44ptあるので、行の間は詰めてカレンダーを画面内に入れる。
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppColor.accent)
                Text("連続 \(viewModel.streakDays)日")
                    .font(.headline)
            }

            Text("直近30日の記録")
                .font(.caption)
                .foregroundStyle(AppColor.muted)

            ForEach(viewModel.achievements) { achievement in
                NavigationLink {
                    RoutineStatisticsView(routine: achievement.routine)
                } label: {
                    achievementRow(achievement)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(achievement.routine.title)、達成率\(Int((achievement.rate * 100).rounded()))パーセント、"
                        + "\(achievement.applicableCount)\(achievement.unitLabel)中"
                        + "\(achievement.completedCount)\(achievement.unitLabel)達成"
                )
                .accessibilityHint("個別の達成状況を表示")
            }

            if viewModel.hasLoaded && viewModel.achievements.isEmpty {
                Text("達成状況を表示する約束がありません")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            // 「やらないこと」は達成率ではなく勝ち負けで数えるので、線で分けて置く。
            if let behavior = viewModel.activeBehavior {
                Divider()
                    .overlay(AppColor.border)

                NavigationLink {
                    BlockedBehaviorRecordView(behavior: behavior)
                } label: {
                    behaviorRow(behavior)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(behaviorAccessibilityLabel(behavior))
                .accessibilityHint("やらないことの記録を表示")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    private func behaviorRow(_ behavior: BlockedBehavior) -> some View {
        HStack(spacing: 8) {
            Image(systemName: behavior.iconName ?? "nosign")
                .foregroundStyle(AppColor.secondary)
                .frame(width: 22)
            Text(behavior.title)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            Spacer()
            Text(behaviorRecordText)
                .font(.subheadline.bold())
                .foregroundStyle(AppColor.text)
                .monospacedDigit()
            chevron
        }
    }

    private var behaviorRecordText: String {
        let count = viewModel.behaviorRecentCount
        return count.isEmpty ? "記録はまだありません" : "\(count.kept)勝 \(count.lost)敗"
    }

    private func behaviorAccessibilityLabel(_ behavior: BlockedBehavior) -> String {
        "\(behavior.title)、直近30日 \(behaviorRecordText)"
    }

    /// やらないことの記録と同じく、月送り・曜日・日付を1枚の白いカードにまとめる。
    private var calendarSection: some View {
        VStack(spacing: 8) {
            monthHeader
            weekdayHeader
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(viewModel.daysInDisplayedMonth().enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(for: date)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding()
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppColor.border))
    }

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("前の月")
            Spacer()
            Text(viewModel.displayedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
                .foregroundStyle(AppColor.text)
            Spacer()
            Button {
                viewModel.goToNextMonth()
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

    private var weekdayHeader: some View {
        HStack {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: AppDay.anchor(.now, calendar: calendar))
        let day = calendar.component(.day, from: date)
        let completed = viewModel.completedRoutines(on: date)
        return VStack(spacing: 4) {
            CalendarDayNumber(day: day, isToday: isToday)
            completionDots(count: completed.count)
                // やらないことの記録の ○/✕ と同じ高さに固定し、約束の数で行の高さを変えない。
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendarAccessibilityLabel(for: date, completed: completed))
    }

    /// 達成した約束の数を点で表す。11ptの絵柄は小さい端末で見分けられず、4件以上で折り返すため。
    private func completionDots(count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle()
                    .fill(AppColor.secondary)
                    .frame(width: 6, height: 6)
            }
            if count > 3 {
                Image(systemName: "plus")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(AppColor.secondary)
            }
        }
    }

    @ViewBuilder
    private func achievementRow(_ achievement: RoutineAchievement) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    achievementTitle(achievement)
                    Spacer()
                    chevron
                }
                HStack(spacing: 8) {
                    Spacer()
                    achievementNumbers(achievement)
                }
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 8) {
                achievementTitle(achievement)
                Spacer()
                achievementNumbers(achievement)
                chevron
            }
        }
    }

    private func achievementTitle(_ achievement: RoutineAchievement) -> some View {
        HStack(spacing: 8) {
            Image(systemName: achievement.routine.iconName ?? routineIcon)
                .foregroundStyle(AppColor.secondary)
                .frame(width: 22)
            Text(achievement.routine.title)
                .font(.subheadline)
                .foregroundStyle(AppColor.text)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    private func achievementNumbers(_ achievement: RoutineAchievement) -> some View {
        HStack(spacing: 8) {
            Text("\(Int((achievement.rate * 100).rounded()))%")
                .font(.subheadline.bold())
                .foregroundStyle(AppColor.text)
            Text("\(achievement.completedCount)/\(achievement.applicableCount)\(achievement.unitLabel)")
                .font(.caption)
                .foregroundStyle(AppColor.muted)
                .monospacedDigit()
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppColor.muted)
    }

    private func calendarAccessibilityLabel(for date: Date, completed: [Routine]) -> String {
        let dateLabel = date.formatted(.dateTime.month().day().weekday(.wide))
        guard !completed.isEmpty else { return "\(dateLabel)、達成なし" }
        return "\(dateLabel)、達成：\(completed.map(\.title).joined(separator: "、"))"
    }

    private let routineIcon = "checkmark.circle.fill"
}

#Preview {
    NavigationStack {
        RoutineLogView()
    }
    .modelContainer(for: [Routine.self, BlockedBehavior.self], inMemory: true)
}

/// カレンダーの日付。今日は塗りつぶさず、太字と本文色の輪で示す
/// (Primary は「今押すべき操作」専用で、赤い塗りは「負けた」の × と紛らわしいため)。
struct CalendarDayNumber: View {
    let day: Int
    let isToday: Bool

    var body: some View {
        Text("\(day)")
            .font(isToday ? .subheadline.weight(.semibold) : .subheadline)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .foregroundStyle(AppColor.text)
            .frame(width: 28, height: 28)
            .overlay {
                if isToday {
                    Circle().stroke(AppColor.text, lineWidth: 1.5)
                }
            }
    }
}
