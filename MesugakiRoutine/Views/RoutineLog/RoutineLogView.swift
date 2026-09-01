import SwiftUI

struct RoutineLogView: View {
    @Environment(\.modelContext) private var modelContext
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
                legend
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
                HStack {
                    Image(systemName: icon(for: achievement.routine.type))
                        .foregroundStyle(color(for: achievement.routine.type))
                    Text(achievement.routine.title)
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int((achievement.rate * 100).rounded()))%")
                        .font(.subheadline.bold())
                    Text("(\(achievement.completedCount)/\(achievement.applicableCount)日)")
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                }
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
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let day = calendar.component(.day, from: date)
        let completed = viewModel.completedRoutines(on: date)
        return VStack(spacing: 4) {
            Text("\(day)")
                .font(.subheadline)
                .foregroundStyle(isToday ? Color.white : AppColor.text)
                .frame(width: 28, height: 28)
                .background(isToday ? AppColor.primary : Color.clear, in: Circle())
            HStack(spacing: 3) {
                ForEach(completed, id: \.id) { routine in
                    Image(systemName: icon(for: routine.type))
                        .font(.system(size: 10))
                        .foregroundStyle(color(for: routine.type))
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(viewModel.routines, id: \.id) { routine in
                HStack(spacing: 4) {
                    Image(systemName: icon(for: routine.type))
                        .foregroundStyle(color(for: routine.type))
                    Text(routine.title)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }
            }
        }
        .padding(.top, 8)
    }

    private func icon(for type: RoutineType) -> String {
        switch type {
        case .morning: return "sun.max.fill"
        case .night: return "moon.stars.fill"
        case .custom: return "star.fill"
        }
    }

    private func color(for type: RoutineType) -> Color {
        switch type {
        case .morning: return AppColor.warning
        case .night: return AppColor.secondary
        case .custom: return AppColor.muted
        }
    }
}

#Preview {
    NavigationStack {
        RoutineLogView()
    }
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self], inMemory: true)
}
