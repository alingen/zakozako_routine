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

    /// 全達成直後のポップアップ専用。ホーム更新で先に表示済みになっていても、
    /// 操作への反応として必ず全達成の候補から選ぶ。通常表示側には表示済みを共有する。
    func selectAllCompletedReaction(
        conditions: [ReactionCondition], lines: [ReactionLine], context: ReactionContext,
        now: Date = .now, calendar: Calendar = .current,
        randomUnit: () -> Double = { Double.random(in: 0..<1) }
    ) -> InteractionComment? {
        guard let match = ReactionConditionEvaluator.matches(
            conditions: conditions, context: context, trigger: .homeUpdated,
            now: now, calendar: calendar
        ).first(where: { $0.condition.id == "routine_all_completed" }) else { return nil }
        var state = readState(day: AppDay.startOfDay(for: now, calendar: calendar))
        guard let line = InteractionCommentSelector.select(
            from: lines.filter { $0.conditionId == match.condition.id && $0.supports(.general) }.map(\.comment),
            touchArea: "character", now: now, calendar: calendar,
            excluding: state.lastLineID, randomUnit: randomUnit
        ) else { return nil }
        state.consumed.insert(match.consumptionKey)
        state.lastLineID = line.id
        save(state)
        return line
    }

    /// ホームのミニ莉央用。`candidates` の条件のうち、今の状態に合い、表示済みでないものから
    /// priority が最も高いものを選ぶ(同点は抽選)。順番は CMS の priority で決め、コードに書かない。
    /// - `reusable`: 表示済みでも選べる条件(全達成のお祝いなど、操作への返事として毎回出したいもの)。
    /// - `consume`: false なら表示済みにしない(放置で来た莉央の一言のような、雰囲気づくりの一言)。
    /// - `completedRoutineID`: 完了操作の直後だけ渡す。初達成はこの約束の履歴だけで判定する。
    func selectHomeReaction(
        candidates: Set<String>, reusable: Set<String> = [], consume: Bool = true,
        conditions: [ReactionCondition], lines: [ReactionLine], context: ReactionContext,
        completedRoutineID: UUID? = nil,
        now: Date = .now, calendar: Calendar = .current,
        randomUnit: () -> Double = { Double.random(in: 0..<1) }
    ) -> (comment: InteractionComment, conditionID: String)? {
        var state = readState(day: AppDay.startOfDay(for: now, calendar: calendar))
        let linesByCondition = Dictionary(grouping: lines.filter {
            $0.active && $0.weight > 0 && $0.supports(.general)
        }, by: \.conditionId)
        let usable = ReactionConditionEvaluator.matches(
            conditions: conditions, context: context,
            trigger: completedRoutineID.map(ReactionTrigger.routineCompleted) ?? .homeUpdated,
            now: now, calendar: calendar
        ).filter { match in
            candidates.contains(match.condition.id)
                && (reusable.contains(match.condition.id) || !state.consumed.contains(match.consumptionKey))
                && linesByCondition[match.condition.id]?.isEmpty == false
        }
        guard let priority = usable.map(\.condition.priority).max() else { return nil }
        let highest = usable.filter { $0.condition.priority == priority }
        let match = highest[Int(unit(randomUnit) * Double(highest.count))]
        guard let line = InteractionCommentSelector.select(
            from: (linesByCondition[match.condition.id] ?? []).map(\.comment), touchArea: "character",
            now: now, calendar: calendar, excluding: state.lastLineID, randomUnit: randomUnit
        ) else { return nil }
        if consume {
            state.consumed.insert(match.consumptionKey)
            state.lastLineID = line.id
            save(state)
        }
        return (line, match.condition.id)
    }

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
        let linesByCondition = Dictionary(grouping: lines.filter {
            $0.active && $0.weight > 0 && $0.supports(.general)
        }, by: \.conditionId)
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

    /// 操作への返答・ミニ莉央専用。発生条件は共通、表示先だけをシートで分ける。
    /// 出現回数は各UIのScheduleで制限済みなので、通常会話で消費済みでも返答する。
    func selectForPresentation(
        conditions: [ReactionCondition], lines: [ReactionLine], context: ReactionContext,
        target: ReactionDisplayTarget, trigger: ReactionTrigger = .homeUpdated,
        conditionID: String? = nil, routineTitle: String? = nil,
        now: Date = .now, calendar: Calendar = .current,
        randomUnit: () -> Double = { Double.random(in: 0..<1) }
    ) -> ReactionLine? {
        var matches = ReactionConditionEvaluator.matches(
            conditions: conditions, context: context, trigger: trigger, now: now, calendar: calendar
        )
        // 放置中のタップでは、操作そのものに加え「未達成がある」など現在の状態も使う。
        if target != .general, case .action = trigger {
            matches += ReactionConditionEvaluator.matches(
                conditions: conditions, context: context, trigger: .homeUpdated, now: now, calendar: calendar
            )
        }
        let candidates = lines.filter {
            $0.active && $0.weight > 0 && $0.supports(target, routineTitle: routineTitle)
        }
        matches = matches.filter { match in
            (conditionID == nil || match.condition.id == conditionID)
                && candidates.contains { $0.conditionId == match.condition.id }
        }
        guard let priority = matches.map({ $0.condition.priority }).max() else { return nil }
        let highest = matches.filter { $0.condition.priority == priority }
        let match = highest[Int(unit(randomUnit) * Double(highest.count))]
        var state = readState(day: AppDay.startOfDay(for: now, calendar: calendar))
        guard let selected = InteractionCommentSelector.select(
            from: candidates.filter { $0.conditionId == match.condition.id }.map(\.comment),
            touchArea: "character", now: now, calendar: calendar,
            excluding: state.lastLineID, randomUnit: randomUnit
        ), let line = candidates.first(where: { $0.id == selected.id }) else { return nil }
        // コンパクトな演出で使っただけなら、通常コメントの条件は消費しない。
        if target == .general { state.consumed.insert(match.consumptionKey) }
        state.lastLineID = line.id
        save(state)
        return line
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
