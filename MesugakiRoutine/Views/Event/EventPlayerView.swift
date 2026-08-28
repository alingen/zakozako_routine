import SwiftUI

/// イベントを種類に応じて適切な画面で再生する振り分けビュー。
/// - 小イベント(`.small`): LINE風UI(`EventConversationView`)
/// - 大イベント(`.big`): ギャルゲー風UI(`BigEventView`)
struct EventPlayerView: View {
    let event: EventDefinition

    var body: some View {
        switch event.eventType {
        case .small:
            EventConversationView(eventId: event.eventId)
        case .big:
            BigEventView(eventId: event.eventId)
        }
    }
}
