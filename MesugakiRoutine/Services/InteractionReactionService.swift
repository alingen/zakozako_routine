import Foundation

/// 保存するのは表示履歴と日替わり候補だけ。達成・失敗・来訪の正本は既存Repository。
@MainActor
final class InteractionReactionService {
    private struct PresentationState: Codable {
        var day: Date
        var poolIDs: [String] = []
        var previousPoolIDs: [String] = []
        var consumed: Set<String> = []
        var lastLineID: String?
    }

    private let defaults: UserDefaults
    private let storageKey = "interaction.reactionPresentation.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func select(
        conditions: [ReactionCondition], lines: [ReactionLine], interactions: [InteractionComment],
        context: ReactionContext, trigger: ReactionTrigger, touchArea: String = "character",
        profileValues: [String: String] = [:], now: Date = .now, calendar: Calendar = .current,
        randomUnit: () -> Double = { Double.random(in: 0..<1) }
    ) -> InteractionComment? {
        var state = readState(day: AppDay.startOfDay(for: now, calendar: calendar))
        let matches = ReactionConditionEvaluator.matches(conditions: conditions, context: context,
            trigger: trigger, now: now, calendar: calendar).filter { !state.consumed.contains($0.consumptionKey) }
        // strength / premiumOnly は保持するだけ。現在の候補制限には使わない。
        let linesByCondition = Dictionary(grouping: lines.filter { $0.active && $0.weight > 0 }, by: \.conditionId)
        let usable = matches.filter { linesByCondition[$0.condition.id]?.isEmpty == false }
        let priority = usable.map { $0.condition.priority }.max()
        let highest = usable.filter { $0.condition.priority == priority }
        if !highest.isEmpty {
            let index = Int(unit(randomUnit) * Double(highest.count))
            let match = highest[index]
            if let line = InteractionCommentSelector.select(
                from: (linesByCondition[match.condition.id] ?? []).map(\.comment), touchArea: touchArea,
                now: now, calendar: calendar, excluding: state.lastLineID, randomUnit: randomUnit
            ) {
                state.consumed.insert(match.consumptionKey)
                state.lastLineID = line.id
                save(state)
                return line
            }
        }
        // 操作専用のセリフが無い場合は、呼び出し側に既存の操作用フォールバックを任せる。
        if case .action = trigger { return nil }

        let eligible = InteractionCommentSelector.candidates(from: interactions, touchArea: touchArea,
            now: now, calendar: calendar, profileValues: profileValues)
        let eligibleIDs = Set(eligible.map(\.id))
        state.poolIDs.removeAll { !eligibleIDs.contains($0) }
        while state.poolIDs.count < min(3, eligible.count) {
            let unused = eligible.filter { !state.poolIDs.contains($0.id) }
            let fresh = unused.filter { !state.previousPoolIDs.contains($0.id) }
            guard let next = InteractionCommentSelector.select(from: fresh.isEmpty ? unused : fresh,
                touchArea: touchArea, now: now, calendar: calendar, profileValues: profileValues,
                randomUnit: randomUnit) else { break }
            state.poolIDs.append(next.id)
        }
        let selected = InteractionCommentSelector.select(
            from: eligible.filter { state.poolIDs.contains($0.id) }, touchArea: touchArea,
            now: now, calendar: calendar, profileValues: profileValues,
            excluding: state.lastLineID, randomUnit: randomUnit
        )
        state.lastLineID = selected?.id
        save(state)
        return selected
    }

    private func unit(_ random: () -> Double) -> Double { min(max(random(), 0), 1.0.nextDown) }

    private func readState(day: Date) -> PresentationState {
        guard let data = defaults.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(PresentationState.self, from: data) else {
            return PresentationState(day: day)
        }
        guard saved.day == day else {
            return PresentationState(day: day, previousPoolIDs: saved.poolIDs)
        }
        return saved
    }

    private func save(_ state: PresentationState) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: storageKey) }
    }
}
