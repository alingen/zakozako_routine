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
                monthHeader
                weekdayHeader
                LazyVGrid(columns: columns, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(AppColor.warning)
                Text("継続 \(viewModel.streakDays)日")
                    .font(.headline)
            }

            Text("直近30日の達成率")
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
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColor.border))
    }

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(viewModel.displayedMonth, format: .dateTime.year().month(.wide))
                .font(.headline)
            Spacer()
            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
            }
        }
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
        let iconColumns = Array(
            repeating: GridItem(.flexible(), spacing: 1),
            count: min(max(completed.count, 1), 3)
        )
        return VStack(spacing: 4) {
            Text("\(day)")
                .font(.subheadline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(isToday ? Color.white : AppColor.text)
                .frame(width: 28, height: 28)
                .background(isToday ? AppColor.primary : Color.clear, in: Circle())
            LazyVGrid(columns: iconColumns, spacing: 1) {
                ForEach(completed, id: \.id) { routine in
                    Image(systemName: routine.iconName ?? routineIcon)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(AppColor.primary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 12, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendarAccessibilityLabel(for: date, completed: completed))
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
            Image(systemName: routineIcon)
                .foregroundStyle(AppColor.primary)
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
            Text("(\(achievement.completedCount)/\(achievement.applicableCount)\(achievement.unitLabel))")
                .font(.caption2)
                .foregroundStyle(AppColor.muted)
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
