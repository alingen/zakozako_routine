import Charts
import SwiftUI

struct RoutineStatisticsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let routine: Routine

    @State private var selectedYear: Int

    private let calendar = Calendar.current

    init(routine: Routine) {
        self.routine = routine
        let currentYear = Calendar.current.component(
            .year,
            from: AppDay.anchor(.now, calendar: .current)
        )
        _selectedYear = State(initialValue: currentYear)
    }

    var body: some View {
        VStack(spacing: 0) {
            routineHeader
            yearPicker

            TabView(selection: $selectedYear) {
                ForEach(availableYears, id: \.self) { year in
                    DeferredView {
                        statisticsPage(for: year)
                    }
                        .tag(year)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(AppColor.background.ignoresSafeArea())
        .navigationTitle("達成状況")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var availableYears: [Int] {
        RoutineYearStatisticsCalculator.availableYears(for: routine, calendar: calendar)
    }

    private var routineHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: routine.iconName ?? "checkmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppColor.primary)
                .frame(width: 48, height: 48)
                .background(AppColor.primarySoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .font(.headline)
                    .foregroundStyle(AppColor.text)
                    .lineLimit(2)
                Text(goalDescription)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var yearPicker: some View {
        HStack {
            Button {
                moveYear(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedYear == availableYears.first)
            .accessibilityLabel("前年")

            Spacer()
            Text(verbatim: "\(selectedYear)年")
                .font(.title3.bold())
                .foregroundStyle(AppColor.text)
                .contentTransition(.numericText())
            Spacer()

            Button {
                moveYear(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(selectedYear == availableYears.last)
            .accessibilityLabel("翌年")
        }
        .foregroundStyle(AppColor.primary)
        .padding(.horizontal, 8)
        .background(AppColor.surface)
        .overlay(alignment: .bottom) {
            Divider().overlay(AppColor.border)
        }
    }

    private func statisticsPage(for year: Int) -> some View {
        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: year,
            calendar: calendar
        )

        return ScrollView {
            VStack(spacing: 16) {
                headlineStatistics(statistics)
                if routine.progressStatisticsArchiveData != nil {
                    Text("設定変更前の実績は、当時の達成ルールで集計しています")
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                monthlyChart(statistics)
                weekdayChart(statistics)
                hourlyChart(statistics)
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(AppColor.background)
    }

    private func headlineStatistics(_ statistics: RoutineYearStatistics) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    metric(
                        value: "\(statistics.longestStreak)",
                        label: "最高連続",
                        detail: nil
                    )
                    Divider()
                    metric(
                        value: percentage(statistics.completionRate),
                        label: "達成率",
                        detail: "\(statistics.completedCount)/\(statistics.applicableCount)"
                    )
                    Divider()
                    metric(
                        value: "\(statistics.completedCount)回",
                        label: "完了",
                        detail: nil
                    )
                }
            } else {
                HStack(spacing: 0) {
                    metric(
                        value: "\(statistics.longestStreak)",
                        label: "最高連続",
                        detail: nil
                    )
                    Divider().frame(height: 56)
                    metric(
                        value: percentage(statistics.completionRate),
                        label: "達成率",
                        detail: "\(statistics.completedCount)/\(statistics.applicableCount)"
                    )
                    Divider().frame(height: 56)
                    metric(
                        value: "\(statistics.completedCount)回",
                        label: "完了",
                        detail: nil
                    )
                }
            }
        }
        .padding(.vertical, 16)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.border))
        .accessibilityElement(children: .combine)
    }

    private func metric(value: String, label: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(AppColor.text)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.muted)
            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColor.muted)
            } else {
                Text(" ")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func monthlyChart(_ statistics: RoutineYearStatistics) -> some View {
        let chartData = statistics.monthly.filter { $0.applicableCount > 0 }
        statisticsCard(title: "月ごとの達成率") {
            if chartData.isEmpty {
                emptyMessage("この年の対象期間はありません")
            } else {
                Chart(chartData) { item in
                    AreaMark(
                        x: .value("月", item.month),
                        y: .value("達成率", item.completionRate * 100)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.primary.opacity(0.28), AppColor.primary.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("月", item.month),
                        y: .value("達成率", item.completionRate * 100)
                    )
                    .foregroundStyle(AppColor.primary)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("月", item.month),
                        y: .value("達成率", item.completionRate * 100)
                    )
                    .foregroundStyle(AppColor.primary)
                    .symbolSize(28)
                }
                .chartXScale(domain: 1...12)
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: [1, 4, 7, 10, 12]) { value in
                        AxisGridLine().foregroundStyle(AppColor.border)
                        AxisTick().foregroundStyle(AppColor.muted)
                        AxisValueLabel {
                            if let month = value.as(Int.self) {
                                Text("\(month)月")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine().foregroundStyle(AppColor.border)
                        AxisValueLabel {
                            if let rate = value.as(Int.self) {
                                Text("\(rate)%")
                            }
                        }
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("月ごとの達成率")
            }
        }
    }

    @ViewBuilder
    private func weekdayChart(_ statistics: RoutineYearStatistics) -> some View {
        statisticsCard(title: "達成した曜日") {
            if statistics.completedCount == 0 {
                emptyMessage("この年の達成記録はありません")
            } else {
                Chart(statistics.weekdays) { item in
                    BarMark(
                        x: .value("曜日", weekdayLabel(item.weekday)),
                        y: .value("完了数", item.completedCount)
                    )
                    .foregroundStyle(AppColor.primary.gradient)
                    .cornerRadius(4)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(AppColor.border)
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("曜日別の完了数")
            }
        }
    }

    @ViewBuilder
    private func hourlyChart(_ statistics: RoutineYearStatistics) -> some View {
        statisticsCard(title: "達成した時間帯") {
            if statistics.completedCount == 0 {
                emptyMessage("この年の達成記録はありません")
            } else {
                Chart(statistics.hours) { item in
                    AreaMark(
                        x: .value("時刻", item.hour),
                        y: .value("完了数", item.completedCount)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColor.secondary.opacity(0.25), AppColor.secondary.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("時刻", item.hour),
                        y: .value("完了数", item.completedCount)
                    )
                    .foregroundStyle(AppColor.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                }
                .chartXScale(domain: 0...23)
                .chartXAxis {
                    AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                        AxisGridLine().foregroundStyle(AppColor.border)
                        AxisTick().foregroundStyle(AppColor.muted)
                        AxisValueLabel {
                            if let hour = value.as(Int.self) {
                                Text("\(hour)時")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(AppColor.border)
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
                .accessibilityLabel("時間帯別の完了数")
            }
        }
    }

    private func statisticsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColor.text)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.border))
    }

    private func emptyMessage(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppColor.muted)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private var goalDescription: String {
        "現在：\(routine.period.pickerLabel) \(routine.targetCount)回"
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        guard symbols.indices.contains(weekday - 1) else { return "" }
        return symbols[weekday - 1]
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func moveYear(by offset: Int) {
        guard let currentIndex = availableYears.firstIndex(of: selectedYear) else { return }
        let newIndex = currentIndex + offset
        guard availableYears.indices.contains(newIndex) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedYear = availableYears[newIndex]
        }
    }
}

/// `TabView(.page)` が表示する年の内容だけを組み立て、長期履歴でも初期表示を軽くする。
private struct DeferredView<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

#Preview {
    let calendar = Calendar.current
    let routine = Routine(
        title: "本を読む",
        createdAt: calendar.date(byAdding: .month, value: -3, to: .now) ?? .now,
        iconName: "book",
        progressEvents: [
            calendar.date(byAdding: .day, value: -2, to: .now) ?? .now,
            calendar.date(byAdding: .day, value: -1, to: .now) ?? .now,
            .now,
        ]
    )
    return NavigationStack {
        RoutineStatisticsView(routine: routine)
    }
}
