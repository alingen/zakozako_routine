import Foundation

/// 台本ベースの会話(今日の会話・小イベント・大イベント)で共有するデータ構造。
/// AIは一切使わず、Google スプレッドシート(正本)から `tools/scenario-sync` で生成された
/// `Resources/GeneratedScenarios/*.generated.json` を読み込んで順に再生する。生成物は直接編集しない。
///
/// 巨大なシナリオ分岐は想定しない。基本は「共通 → 選択肢 → A/Bの数メッセージ → 共通へ合流」程度で、
/// 合流は `ScriptChoice.next` / `ScriptMessage.next` にメッセージidを指定して表現する。
///
/// ## 台本の役割分担(横方向 / 縦方向)
///
/// - **今日の会話(scenario_type=daily)= 横方向**。毎日キャラに会い、日常を見て、雑談し、
///   ユーザーのことを少し知ってもらう。関係性は進展させない。`{{fact:}}` でユーザー情報に触れたり、
///   `minPhase` で「毎日話してて慣れてきた」程度の変化を反映するのは可。
///   ただし「前より信用してる」「あなたは特別」「好きになってきた」のような
///   関係性を確定させる発言は書かない(= `advancesToPhase` は持たせない)。
/// - **イベント(scenario_type=small_event / large_event)= 縦方向**。信用される・秘密を知る・
///   弱さを見せてもらう・関係性が変わる。関係性を確定させる発言はここに置き、
///   大イベントは `advancesToPhase` でフェーズを進める。
///
/// `minPhase` / `maxPhase` は「今の関係性フェーズ(RelationshipState.phase)」で1メッセージ単位に
/// 表示可否を切り替える。条件に合わないメッセージは丸ごとスキップされる
/// (スキップされても破綻しないよう、選択肢や分岐の要になるメッセージには付けないこと)。

/// 台本内の発言者。
enum ScriptSpeaker: String, Codable {
    case character
    /// ユーザー側の吹き出し。選択肢を選んだ内容の反映などに使う。
    case user
}

/// メッセージの種類。
enum ScriptMessageType: String, Codable {
    case text
    /// 画像メッセージ。`imageName`(Assets.xcassetsの画像名)を表示し、`text`があれば下にキャプションとして出す。
    case image
}

/// 選択肢や台本メッセージで、ユーザープロフィール情報(UserProfileFact)として保存する内容。
/// 例: key="hasSiblings", value="いる"。将来の別の会話から `{{fact:hasSiblings}}` で参照できる。
struct SaveFact: Codable, Hashable {
    let key: String
    let value: String
}

/// 保存済みユーザー情報に対する比較演算子(選択肢の表示条件で使う)。
enum RequirementOperator: String, Codable, Hashable {
    case eq, ne, gt, gte, lt, lte, exists
}

/// 選択肢の表示条件。保存済みの `key` の値が条件を満たすときだけその選択肢を提示する。
struct ChoiceRequirement: Codable, Hashable {
    let key: String
    let op: RequirementOperator
    let value: String

    enum CodingKeys: String, CodingKey {
        case key
        case op = "operator"
        case value
    }
}

/// 選択肢1つぶん。
struct ScriptChoice: Codable, Hashable {
    let text: String
    /// この選択肢を選んだ後に進むメッセージid。nilなら台本の配列順で次の要素へ。
    let next: String?
    /// 非nilなら、この選択肢を選んだ時に指定のキーでユーザー情報を保存する。
    let saveFact: SaveFact?
    /// 非nilなら、条件を満たすときだけこの選択肢を表示する。
    let requirement: ChoiceRequirement?
}

/// 台本の1メッセージ。
struct ScriptMessage: Codable, Identifiable, Hashable {
    let id: String
    let speaker: ScriptSpeaker
    /// テキストメッセージなら本文。画像メッセージなら任意のキャプション(空可)。
    let text: String
    /// 画像メッセージ(`type == .image`)の時に表示する画像名(Assets.xcassets)。
    let imageName: String?
    /// 非nilかつ非空なら、この吹き出しの後に選択肢を提示する。
    let choices: [ScriptChoice]?
    /// 次に進むメッセージid。nilなら配列順で次の要素へ。末尾かつnilなら会話終了。
    let next: String?
    /// 非nilなら、このメッセージを表示した時に指定のキーでユーザー情報を保存する
    /// (選択肢を伴わない台本行から情報を保存したい場合に使う)。
    let saveFact: SaveFact?

    /// 関係性フェーズ(RelationshipState.phase)がこの値以上のときだけ表示する。
    let minPhase: Int?
    /// 関係性フェーズがこの値以下のときだけ表示する(初期の関係でだけ出したいセリフ用)。
    let maxPhase: Int?

    // --- 大イベント(ギャルゲー風UI)専用。小イベント/今日の会話では未使用 ---
    /// 名前ウィンドウに出す話者名。nilならキャラクター名(speaker == .character 時)。
    let speakerName: String?
    /// このメッセージ以降の背景画像(Assets)。nilなら直前の背景を維持。
    let background: String?
    /// このメッセージで表示するキャラクター立ち絵(Assets)。nilなら直前の立ち絵を維持。
    let portrait: String?
    /// このメッセージで前面に表示する一枚絵(CG, Assets)。nilなら表示しない。
    let cg: String?

    private let rawType: ScriptMessageType?
    var type: ScriptMessageType { rawType ?? .text }

    enum CodingKeys: String, CodingKey {
        case id, speaker, text, imageName, choices, next, saveFact
        case minPhase, maxPhase
        case speakerName, background, portrait, cg
        case rawType = "type"
    }
}

/// 1本の会話台本。
struct ConversationScript: Codable {
    let messages: [ScriptMessage]

    var first: ScriptMessage? { messages.first }

    func message(id: String) -> ScriptMessage? {
        messages.first { $0.id == id }
    }

    /// `current` の次に再生すべきメッセージ。優先度: `current.next` 指定 > 配列順の次 > なし(会話終了)。
    func message(after current: ScriptMessage) -> ScriptMessage? {
        if let nextID = current.next {
            return message(id: nextID)
        }
        guard let index = messages.firstIndex(where: { $0.id == current.id }),
              messages.indices.contains(index + 1) else {
            return nil
        }
        return messages[index + 1]
    }
}
