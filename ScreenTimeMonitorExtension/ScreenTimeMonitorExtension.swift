import DeviceActivity
import Foundation

final class ScreenTimeMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard let behaviorID = ScreenTimeMonitorShared.behaviorID(
            fromActivityRawName: activity.rawValue
        ) else { return }
        ScreenTimeMonitorShared.beginMonitoringInterval(for: behaviorID)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard let behaviorID = ScreenTimeMonitorShared.behaviorID(
            fromActivityRawName: activity.rawValue
        ) else { return }
        ScreenTimeMonitorShared.enqueueIntervalCompleted(for: behaviorID)
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)

        guard let behaviorID = ScreenTimeMonitorShared.behaviorID(
            fromEventRawName: event.rawValue
        ) else {
            return
        }

        ScreenTimeMonitorShared.enqueueThresholdExceeded(
            for: behaviorID,
            limitMinutes: ScreenTimeMonitorShared.limitMinutes(
                fromEventRawName: event.rawValue
            )
        )
    }
}
