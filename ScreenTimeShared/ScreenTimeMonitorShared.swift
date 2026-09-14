import Foundation

enum ScreenTimeMonitorSignalKind: String, Codable, Sendable {
    case thresholdExceeded
    case intervalCompleted
}

struct ScreenTimeMonitorSignal: Codable, Equatable, Sendable {
    let behaviorID: UUID
    /// この通知が属する、朝4時始まりのアプリ内日付。
    let appDayStart: Date
    let occurredAt: Date
    let kind: ScreenTimeMonitorSignalKind
}

struct PendingScreenTimeMonitorSignal: Sendable {
    let fileName: String
    let signal: ScreenTimeMonitorSignal
}

/// App と Device Activity 拡張の間で、監視結果を受け渡す共有領域。
/// 1通知につき1ファイルを atomic に追加し、SwiftDataへの保存が終わった通知だけを
/// App側が削除することで、別プロセスとの競合やアプリ終了による通知消失を防ぐ。
enum ScreenTimeMonitorShared {
    static let appGroupID = "group.com.zakozako.mesugakiroutine"

    private struct ActiveInterval: Codable {
        let appDayStart: Date
        var completedAt: Date?
    }

    private static let activityNamePrefix = "screen-time-activity."
    private static let eventNamePrefix = "screen-time-limit."
    private static let pendingDirectoryName = "ScreenTimeMonitorSignals"
    private static let activeIntervalDirectoryName = "ScreenTimeActiveIntervals"
    private static let maximumPendingSignalCount = 90
    private static let appDayStartHour = 4

    static func activityRawName(for behaviorID: UUID) -> String {
        activityNamePrefix + behaviorID.uuidString.lowercased()
    }

    static func eventRawName(for behaviorID: UUID, limitMinutes: Int? = nil) -> String {
        let baseName = eventNamePrefix + behaviorID.uuidString.lowercased()
        guard let limitMinutes else { return baseName }
        return "\(baseName).\(min(max(limitMinutes, 1), 1_439))"
    }

    static func behaviorID(fromActivityRawName rawName: String) -> UUID? {
        guard rawName.hasPrefix(activityNamePrefix) else { return nil }
        return UUID(uuidString: String(rawName.dropFirst(activityNamePrefix.count)))
    }

    static func behaviorID(fromEventRawName rawName: String) -> UUID? {
        guard rawName.hasPrefix(eventNamePrefix) else { return nil }
        let payload = rawName.dropFirst(eventNamePrefix.count)
        guard let idPart = payload.split(separator: ".", maxSplits: 1).first else { return nil }
        return UUID(uuidString: String(idPart))
    }

    static func limitMinutes(fromEventRawName rawName: String) -> Int? {
        guard rawName.hasPrefix(eventNamePrefix) else { return nil }
        let payload = rawName.dropFirst(eventNamePrefix.count)
        let parts = payload.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, let minutes = Int(parts[1]) else { return nil }
        return min(max(minutes, 1), 1_439)
    }

    static func beginMonitoringInterval(for behaviorID: UUID, startedAt: Date = .now) {
        let start = appDayStart(containing: startedAt)
        guard !activeIntervals(for: behaviorID).contains(where: {
            $0.interval.appDayStart == start
        }) else { return }
        writeActiveInterval(
            ActiveInterval(appDayStart: start, completedAt: nil),
            for: behaviorID
        )
        pruneActiveIntervals(for: behaviorID, relativeTo: start)
    }

    static func enqueueThresholdExceeded(
        for behaviorID: UUID,
        limitMinutes: Int?,
        occurredAt: Date = .now
    ) {
        let intervals = activeIntervals(for: behaviorID)
        let callbackDay = appDayStart(containing: occurredAt)
        let currentInterval = intervals.last(where: {
            $0.interval.appDayStart == callbackDay && $0.interval.completedAt == nil
        })
        let previousInterval = intervals.last(where: {
            $0.interval.appDayStart < callbackDay
        })
        let elapsedMinutes = occurredAt.timeIntervalSince(callbackDay) / 60

        let matchedDay: Date
        if let limitMinutes,
           elapsedMinutes < Double(limitMinutes),
           let previousInterval {
            // 新しい日の上限時間より早く届いたイベントは物理的に当日分ではないため、
            // 猶予保持している直前intervalの遅延通知として扱う。
            matchedDay = previousInterval.interval.appDayStart
        } else if let currentInterval {
            matchedDay = currentInterval.interval.appDayStart
        } else if let previousInterval {
            matchedDay = previousInterval.interval.appDayStart
        } else {
            // 失敗は達成と異なり、開始記録が欠けても通知自体を失わない。
            matchedDay = callbackDay
        }

        enqueue(
            ScreenTimeMonitorSignal(
                behaviorID: behaviorID,
                appDayStart: matchedDay,
                occurredAt: occurredAt,
                kind: .thresholdExceeded
            )
        )
    }

    static func enqueueIntervalCompleted(for behaviorID: UUID, occurredAt: Date = .now) {
        let callbackDay = appDayStart(containing: occurredAt)
        let intervals = activeIntervals(for: behaviorID).filter {
            $0.interval.completedAt == nil
        }
        // 新日の開始が前日の終了より先に届いても、現在日より前に始まった最新intervalを閉じる。
        // 開始記録がなければ対象日を推測せず、未監視(unknown)として達成にしない。
        var completedInterval = intervals.last(where: {
            $0.interval.appDayStart < callbackDay
        })
        if completedInterval == nil,
           Calendar.autoupdatingCurrent.component(.hour, from: occurredAt) < appDayStartHour {
            // 3:59台に届いた終了通知では、callbackDay自身が終了対象になる。
            completedInterval = intervals.last(where: {
                $0.interval.appDayStart == callbackDay
            })
        }
        guard let completedInterval else { return }

        let didEnqueue = enqueue(
            ScreenTimeMonitorSignal(
                behaviorID: behaviorID,
                appDayStart: completedInterval.interval.appDayStart,
                occurredAt: occurredAt,
                kind: .intervalCompleted
            )
        )
        if didEnqueue {
            var completed = completedInterval.interval
            completed.completedAt = occurredAt
            writeActiveInterval(completed, for: behaviorID)
            pruneActiveIntervals(for: behaviorID, relativeTo: callbackDay)
        }
    }

    /// 未処理通知を読み取るだけで削除しない。永続化に成功した後、個別に acknowledge する。
    static func pendingSignals() -> [PendingScreenTimeMonitorSignal] {
        guard let directoryURL = sharedDirectoryURL(
            named: pendingDirectoryName,
            createIfNeeded: false
        ) else { return [] }

        return pendingFileURLs(in: directoryURL).compactMap { fileURL in
            guard let data = try? Data(contentsOf: fileURL),
                  let signal = try? JSONDecoder().decode(ScreenTimeMonitorSignal.self, from: data) else {
                // atomic 書き込みなので、読み取れないものは破損ファイルとして除去する。
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return PendingScreenTimeMonitorSignal(
                fileName: fileURL.lastPathComponent,
                signal: signal
            )
        }
    }

    static func acknowledge(_ pendingSignal: PendingScreenTimeMonitorSignal) {
        guard let directoryURL = sharedDirectoryURL(
            named: pendingDirectoryName,
            createIfNeeded: false
        ) else { return }
        try? FileManager.default.removeItem(
            at: directoryURL.appendingPathComponent(pendingSignal.fileName)
        )
    }

    static func removePendingSignals(for behaviorID: UUID) {
        for pending in pendingSignals() where pending.signal.behaviorID == behaviorID {
            acknowledge(pending)
        }
    }

    static func removeActiveInterval(for behaviorID: UUID) {
        for activeInterval in activeIntervals(for: behaviorID) {
            try? FileManager.default.removeItem(at: activeInterval.fileURL)
        }
    }

    @discardableResult
    private static func enqueue(_ signal: ScreenTimeMonitorSignal) -> Bool {
        guard let directoryURL = sharedDirectoryURL(
            named: pendingDirectoryName,
            createIfNeeded: true
        ), let encoded = try? JSONEncoder().encode(signal) else { return false }

        let milliseconds = Int64(signal.occurredAt.timeIntervalSince1970 * 1_000)
        let fileName = "\(milliseconds)-\(signal.kind.rawValue)-\(UUID().uuidString.lowercased()).json"
        do {
            try encoded.write(
                to: directoryURL.appendingPathComponent(fileName),
                options: .atomic
            )
            trimPendingFiles(in: directoryURL)
            return true
        } catch {
            // 拡張機能にはUIがないため、OSからの次のコールバックを待つ。
            return false
        }
    }

    private static func activeIntervals(
        for behaviorID: UUID
    ) -> [(fileURL: URL, interval: ActiveInterval)] {
        guard let directoryURL = sharedDirectoryURL(
            named: activeIntervalDirectoryName,
            createIfNeeded: false
        ) else { return [] }
        let prefix = "\(behaviorID.uuidString.lowercased())-"
        return pendingFileURLs(in: directoryURL)
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .compactMap { fileURL in
                guard let data = try? Data(contentsOf: fileURL),
                      let interval = try? JSONDecoder().decode(ActiveInterval.self, from: data) else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
                return (fileURL, interval)
            }
            .sorted { $0.interval.appDayStart < $1.interval.appDayStart }
    }

    private static func writeActiveInterval(
        _ interval: ActiveInterval,
        for behaviorID: UUID
    ) {
        guard let data = try? JSONEncoder().encode(interval),
              let directoryURL = sharedDirectoryURL(
                named: activeIntervalDirectoryName,
                createIfNeeded: true
              ) else { return }
        let dayIdentifier = Int64(interval.appDayStart.timeIntervalSince1970)
        let fileURL = directoryURL.appendingPathComponent(
            "\(behaviorID.uuidString.lowercased())-\(dayIdentifier).json"
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func pruneActiveIntervals(
        for behaviorID: UUID,
        relativeTo currentDay: Date
    ) {
        let retentionStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -2,
            to: currentDay
        ) ?? currentDay.addingTimeInterval(-2 * 86_400)
        for activeInterval in activeIntervals(for: behaviorID)
        where activeInterval.interval.appDayStart < retentionStart {
            try? FileManager.default.removeItem(at: activeInterval.fileURL)
        }
    }

    private static func sharedDirectoryURL(
        named name: String,
        createIfNeeded: Bool
    ) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return nil }

        let directoryURL = containerURL.appendingPathComponent(name, isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
        return directoryURL
    }

    private static func pendingFileURLs(in directoryURL: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func trimPendingFiles(in directoryURL: URL) {
        let files = pendingFileURLs(in: directoryURL)
        guard files.count > maximumPendingSignalCount else { return }
        for fileURL in files.prefix(files.count - maximumPendingSignalCount) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func appDayStart(containing date: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let anchored = calendar.date(
            byAdding: .hour,
            value: -appDayStartHour,
            to: date
        ) ?? date
        let midnight = calendar.startOfDay(for: anchored)
        return calendar.date(
            byAdding: .hour,
            value: appDayStartHour,
            to: midnight
        ) ?? midnight
    }
}
