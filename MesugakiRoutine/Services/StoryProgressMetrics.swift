import Foundation

/// Immutable values available while evaluating CMS event conditions.
struct StoryProgressMetrics: Equatable {
    let cumulativeAchievementDays: Int
    let continuousDays: Int
    let trust: Int
    let profileValues: [String: String]
    let completedEventIds: Set<String>

    init(
        continuousDays: Int,
        cumulativeAchievementDays: Int = 0,
        trust: Int = 0,
        profileValues: [String: String] = [:],
        completedEventIds: Set<String> = []
    ) {
        self.cumulativeAchievementDays = cumulativeAchievementDays
        self.continuousDays = continuousDays
        self.trust = trust
        self.profileValues = profileValues
        self.completedEventIds = completedEventIds
    }
}

@MainActor
protocol StoryProgressMetricsProviding {
    func current(at date: Date, calendar: Calendar) throws -> StoryProgressMetrics
}

/// Bridges the existing routine domain and the story-state repository without
/// maintaining a second streak counter.
@MainActor
struct StoryProgressMetricsProvider: StoryProgressMetricsProviding {
    let routineRepository: RoutineRepository
    let storyStateRepository: StoryStateRepository

    func current(
        at date: Date = .now,
        calendar: Calendar = .current
    ) throws -> StoryProgressMetrics {
        let routines = routineRepository.fetchAll()
        let profileValues = try storyStateRepository.profileValues()
        let actualContinuousDays = RoutineStreak.overallStreak(
            routines: routines,
            now: date,
            calendar: calendar
        )
        let completedEventIds = Set(
            try storyStateRepository.eventProgresses()
                .filter(\.isCompleted)
                .map(\.eventId)
        )
        return StoryProgressMetrics(
            continuousDays: profileValues[StoryStateRepository.debugContinuousAchievementDaysKey]
                .flatMap(Int.init) ?? actualContinuousDays,
            cumulativeAchievementDays:
                profileValues[StoryStateRepository.debugCumulativeAchievementDaysKey]
                .flatMap(Int.init) ?? 0,
            trust: profileValues[StoryStateRepository.trustKey].flatMap(Int.init) ?? 0,
            profileValues: profileValues,
            completedEventIds: completedEventIds
        )
    }
}

/// Lightweight test/preview adapter that avoids constructing repositories.
@MainActor
struct ClosureStoryProgressMetricsProvider: StoryProgressMetricsProviding {
    let resolve: (Date, Calendar) throws -> StoryProgressMetrics

    func current(at date: Date, calendar: Calendar) throws -> StoryProgressMetrics {
        try resolve(date, calendar)
    }
}
