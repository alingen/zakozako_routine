import DeviceActivity
import FamilyControls
import Foundation

enum ScreenTimeMonitoringError: LocalizedError {
    case authorizationRequired
    case authorizationConflict
    case authorizationCanceled
    case invalidAccount
    case restricted
    case networkRequired
    case passcodeRequired
    case unavailable
    case authorizationFailed(String)
    case missingSelection
    case invalidSelection
    case monitoringFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationRequired:
            return "スクリーンタイムの許可が必要です。タップして許可を確認してください。"
        case .authorizationConflict:
            return "ほかのスクリーンタイム管理アプリと権限が競合しています。設定の「スクリーンタイム」→「スクリーンタイムへのアクセスが許可されたApp」で、ほかの管理アプリをオフにしてからもう一度お試しください。"
        case .authorizationCanceled:
            return "スクリーンタイムの許可がキャンセルされました。"
        case .invalidAccount:
            return "スクリーンタイムを利用できるApple AccountでiCloudにサインインしてください。"
        case .restricted:
            return "この端末ではスクリーンタイムの利用が制限されています。設定を確認してください。"
        case .networkRequired:
            return "スクリーンタイムの許可にはネットワーク接続が必要です。接続を確認してもう一度お試しください。"
        case .passcodeRequired:
            return "スクリーンタイムを利用するには、端末にパスコードを設定してください。"
        case .unavailable:
            return "この端末では現在スクリーンタイムを利用できません。設定を確認してもう一度お試しください。"
        case let .authorizationFailed(message):
            return "スクリーンタイムの許可を確認できませんでした。\n\(message)"
        case .missingSelection:
            return "計測するアプリを1つ以上選んでください。"
        case .invalidSelection:
            return "選択したアプリを読み込めませんでした。もう一度選び直してください。"
        case let .monitoringFailed(message):
            return "スクリーンタイムの監視を開始できませんでした。\n\(message)"
        }
    }

    var offersSettingsAction: Bool {
        switch self {
        case .authorizationRequired,
             .authorizationConflict,
             .invalidAccount,
             .restricted,
             .passcodeRequired,
             .unavailable:
            return true
        case .authorizationCanceled,
             .networkRequired,
             .authorizationFailed,
             .missingSelection,
             .invalidSelection,
             .monitoringFailed:
            return false
        }
    }

    static func fromAuthorizationError(_ error: Error) -> ScreenTimeMonitoringError {
        guard let familyControlsError = error as? FamilyControlsError else {
            return .authorizationFailed(error.localizedDescription)
        }

        switch familyControlsError {
        case .authorizationConflict:
            return .authorizationConflict
        case .authorizationCanceled:
            return .authorizationCanceled
        case .invalidAccountType:
            return .invalidAccount
        case .restricted:
            return .restricted
        case .networkError:
            return .networkRequired
        case .authenticationMethodUnavailable:
            return .passcodeRequired
        case .unavailable:
            return .unavailable
        case .invalidArgument:
            return .authorizationFailed(familyControlsError.localizedDescription)
        case .unauthorized:
            return .authorizationRequired
        @unknown default:
            return .authorizationFailed(familyControlsError.localizedDescription)
        }
    }
}

/// Family Controlsのシステム認証画面をアプリ全体で同時に1件だけ表示する。
@MainActor
final class ScreenTimeAuthorizationCoordinator {
    static let shared = ScreenTimeAuthorizationCoordinator()

    private let statusProvider: () -> AuthorizationStatus
    private let requestOperation: () async throws -> Void
    private var inFlightRequest: Task<Void, Error>?

    init(
        statusProvider: @escaping () -> AuthorizationStatus = {
            AuthorizationCenter.shared.authorizationStatus
        },
        requestOperation: @escaping () async throws -> Void = {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        }
    ) {
        self.statusProvider = statusProvider
        self.requestOperation = requestOperation
    }

    var isAuthorized: Bool {
        Self.isAuthorized(statusProvider())
    }

    func requestAuthorizationIfNeeded() async throws {
        if isAuthorized { return }

        if let inFlightRequest {
            try await inFlightRequest.value
            guard isAuthorized else {
                throw ScreenTimeMonitoringError.authorizationRequired
            }
            return
        }

        let requestOperation = self.requestOperation
        let request = Task { @MainActor in
            do {
                try await requestOperation()
            } catch {
                throw ScreenTimeMonitoringError.fromAuthorizationError(error)
            }
        }
        inFlightRequest = request
        defer { inFlightRequest = nil }

        try await request.value
        guard isAuthorized else {
            throw ScreenTimeMonitoringError.authorizationRequired
        }
    }

    static func isAuthorized(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *), status == .approvedWithDataAccess { return true }
        return false
    }
}

/// 「スマホを見ない」で選択したアプリ群を日次で監視し、拡張機能から届いた
/// 上限超過イベントを既存の「負けた」記録へ橋渡しする。
@MainActor
final class ScreenTimeMonitoringService {
    private let center: DeviceActivityCenter
    private let authorizationCoordinator: ScreenTimeAuthorizationCoordinator

    init(center: DeviceActivityCenter = DeviceActivityCenter()) {
        self.center = center
        authorizationCoordinator = .shared
    }

    init(
        center: DeviceActivityCenter,
        authorizationCoordinator: ScreenTimeAuthorizationCoordinator
    ) {
        self.center = center
        self.authorizationCoordinator = authorizationCoordinator
    }

    var isAuthorized: Bool {
        authorizationCoordinator.isAuthorized
    }

    func requestAuthorizationIfNeeded() async throws {
        try await authorizationCoordinator.requestAuthorizationIfNeeded()
    }

    /// アプリ内の1日（朝4時〜翌朝3:59）と同じ区切りで毎日リセットする。
    static var dailySchedule: DeviceActivitySchedule {
        DeviceActivitySchedule(
            intervalStart: DateComponents(hour: AppDay.startHour, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: AppDay.startHour - 1, minute: 59, second: 59),
            repeats: true
        )
    }

    static func thresholdComponents(limitMinutes: Int) -> DateComponents {
        let clampedMinutes = min(max(limitMinutes, 1), 1_439)
        return DateComponents(
            hour: clampedMinutes / 60,
            minute: clampedMinutes % 60
        )
    }

    static func decodeSelection(from data: Data?) throws -> FamilyActivitySelection {
        guard let data else { throw ScreenTimeMonitoringError.invalidSelection }
        do {
            return try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        } catch {
            throw ScreenTimeMonitoringError.invalidSelection
        }
    }

    /// 新規保存時に呼ぶ。現在の監視があれば同じIDの設定で置き換える。
    func startMonitoring(for behavior: BlockedBehavior) throws {
        guard behavior.trackingKind == .screenTime else { return }
        guard isAuthorized else {
            throw ScreenTimeMonitoringError.authorizationRequired
        }

        let selection = try Self.decodeSelection(from: behavior.screenTimeSelectionData)
        guard Self.hasSelection(selection) else {
            throw ScreenTimeMonitoringError.missingSelection
        }

        let activity = DeviceActivityName(ScreenTimeMonitorShared.activityRawName(for: behavior.id))
        let eventName = DeviceActivityEvent.Name(
            ScreenTimeMonitorShared.eventRawName(
                for: behavior.id,
                limitMinutes: behavior.screenTimeLimitMinutes
            )
        )
        let threshold = Self.thresholdComponents(limitMinutes: behavior.screenTimeLimitMinutes)
        let event: DeviceActivityEvent

        if #available(iOS 17.4, *) {
            // 作成前に今日使った時間も含め、登録し直しを抜け道にしない。
            event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: threshold,
                includesPastActivity: true
            )
        } else {
            event = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: threshold
            )
        }

        center.stopMonitoring([activity])
        do {
            try center.startMonitoring(
                activity,
                during: Self.dailySchedule,
                events: [eventName: event]
            )
        } catch {
            throw ScreenTimeMonitoringError.monitoringFailed(error.localizedDescription)
        }
    }

    /// OS側の登録が失われている時だけ復元する。通常の画面更新では閾値をリセットしない。
    func ensureMonitoring(for behavior: BlockedBehavior) throws {
        guard behavior.trackingKind == .screenTime else { return }
        guard isAuthorized else {
            throw ScreenTimeMonitoringError.authorizationRequired
        }
        let activity = DeviceActivityName(ScreenTimeMonitorShared.activityRawName(for: behavior.id))
        guard !center.activities.contains(activity) else { return }
        try startMonitoring(for: behavior)
    }

    func stopMonitoring(for behavior: BlockedBehavior) {
        guard behavior.trackingKind == .screenTime else { return }
        let activity = DeviceActivityName(ScreenTimeMonitorShared.activityRawName(for: behavior.id))
        center.stopMonitoring([activity])
        ScreenTimeMonitorShared.removeActiveInterval(for: behavior.id)
    }

    func discardStoredSignals(for behavior: BlockedBehavior) {
        ScreenTimeMonitorShared.removePendingSignals(for: behavior.id)
        ScreenTimeMonitorShared.removeActiveInterval(for: behavior.id)
    }

    /// 拡張機能が確認した「上限超過」と「1日の監視完了」をSwiftDataへ反映する。
    /// 通知ファイルは保存成功後にだけ削除するため、処理中にアプリが終了しても再試行できる。
    @discardableResult
    func consumePendingSignals(using repository: BlockedBehaviorRepository) -> Int {
        let pendingSignals = ScreenTimeMonitorShared.pendingSignals().sorted { lhs, rhs in
            if lhs.signal.appDayStart != rhs.signal.appDayStart {
                return lhs.signal.appDayStart < rhs.signal.appDayStart
            }
            // 同じ日なら失敗を先に入れ、監視完了が後から来ても成功で上書きされないことを明示する。
            if lhs.signal.kind != rhs.signal.kind {
                return lhs.signal.kind == .thresholdExceeded
            }
            return lhs.signal.occurredAt < rhs.signal.occurredAt
        }
        guard !pendingSignals.isEmpty else { return 0 }

        var recordedCount = 0
        for pending in pendingSignals {
            let signal = pending.signal
            guard let behavior = repository.fetch(id: signal.behaviorID),
                  behavior.trackingKind == .screenTime else {
                // 削除・設定変更済みの古い通知は捨てる。
                ScreenTimeMonitorShared.acknowledge(pending)
                continue
            }

            do {
                let didRecord = try repository.recordScreenTimeSignal(
                    signal,
                    for: behavior
                )
                ScreenTimeMonitorShared.acknowledge(pending)
                if didRecord, signal.kind == .thresholdExceeded {
                    recordedCount += 1
                }
                if behavior.masteredAt != nil {
                    stopMonitoring(for: behavior)
                }
            } catch BlockedBehaviorRepositoryError.screenTimeSignalNotReady {
                // 朝4時の境界直前なら、日付が切り替わった次回foregroundで処理する。
            } catch is BlockedBehaviorRepositoryError {
                // すでに無効化された項目の通知は再試行しても保存できない。
                ScreenTimeMonitorShared.acknowledge(pending)
            } catch {
                // 一時的なSwiftData保存失敗ならファイルを残し、次回foregroundで再試行する。
            }
        }
        return recordedCount
    }

    private static func hasSelection(_ selection: FamilyActivitySelection) -> Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }
}
