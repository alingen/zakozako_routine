import SwiftUI

struct RoutineLogView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RoutineLogViewModel()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
        .navigationTitle("記録")
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
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
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
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
                        .foregroundStyle(.secondary)
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
        case .morning: return .orange
        case .night: return .indigo
        case .custom: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        RoutineLogView()
    }
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self], inMemory: true)
}
