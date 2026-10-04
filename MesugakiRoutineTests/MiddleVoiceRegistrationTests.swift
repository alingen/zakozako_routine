import AVFoundation
import XCTest
@testable import MesugakiRoutine

final class MiddleVoiceRegistrationTests: XCTestCase {
    func testSecondEpisodeVoicesMatchDialogueAndAreDecodable() throws {
        let bundle = Bundle(for: StoryPlayer.self)
        let url = try XCTUnwrap(bundle.url(forResource: "story_content.generated", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let scenarios = try XCTUnwrap(json["scenarios"] as? [[String: Any]])
        let scenario = try XCTUnwrap(scenarios.first { $0["scenarioId"] as? String == "middle_001_2" })
        let nodes = try XCTUnwrap(scenario["nodes"] as? [[String: Any]])
        let expected = [
            "013": "なに？",
            "015": "え、でも見ていいって言ったじゃん",
            "019": "見られたらまずいものなんだ",
            "025": "え、なにしてんの？",
            "033": "だっさ〜w",
            "039": "あ、やっぱり動けないんだ",
            "042": "ざっこ〜",
            "043": "じゃあ続き読も",
            "047": "えーっと",
            "049": "『目的。だらしない生活から脱却し、[br]1年後には別人になる』",
            "164": "『人生はいつからでも[br]変えることができる』",
            "165": "『今日がその日だ。[br]今までの俺とは訣別する』",
            "166": "『1年後の俺は年収1000万、[br]爆美女にモテモテで困っている…』",
            "168": "『ゲーム、SNS、ジャンクフード[br]などの一時的な快楽に支配されない』",
            "059": "今ゲームしてたよね？",
            "063": "人生再建失敗しちゃったんだ？",
            "070": "『Day first』",
            "074": "…ふふっ、[br]Day firstってなに？",
            "076": "なんでちょっと英語でかっこつけたの？[br]1日目とかDay 1でいいじゃん",
            "079": "Day first…あははっ",
            "085": "でもDay firstさん、[br]1日目は全部やってるじゃん",
            "157": "ねえ、爆美女って何？",
            "028": "…ふふっ",
            "048": "『人生再建プログラム』",
            "065": "ふーん",
            "089": "2日目は？",
            "090": "起床：×。夜更かししてしまった",
            "091": "ランニング：△。筋肉痛だった",
            "092": "英語：×。仕事で余裕ない",
            "094": "3日目",
            "095": "起床：×",
            "096": "ランニング：×。暑かった",
            "097": "英語：×。仕事が忙しい",
            "100": "全部×じゃん",
            "103": "Day 4は？",
            "105": "ねえ",
            "107": "ないの？",
            "113": "人生再建できなかったんだ",
            "116": "ふふっ、あははっ",
            "118": "だって",
            "119": "人生再建プログラムなのに[br]その後全部白紙なんだもん",
            "122": "Day firstのとき？",
            "127": "やだ",
            "130": "もうだいたい覚えた",
            "134": "じゃあこうしよ",
            "139": "ここから全部埋まったら返してあげる",
            "141": "うん",
            "145": "…まだいっぱいあるね",
            "148": "じゃあ一生私のだね",
            "155": "え",
            "156": "私しかいないじゃん"
        ]
        let reusedAssetIDs = [
            "028": "voice_middle_001_1_116",
            "048": "voice_middle_001_1_142"
        ]
        let rioDialogue = nodes.filter {
            $0["speaker"] as? String == "rio" && $0["messageType"] as? String == "text"
        }
        XCTAssertEqual(rioDialogue.count, 51)
        XCTAssertEqual(Set(rioDialogue.compactMap { $0["nodeId"] as? String }),
                       Set(expected.keys.map { "middle_001_2_\($0)" }))
        XCTAssertEqual(nodes.filter { $0["voiceAssetId"] != nil }.count, expected.count)
        for (suffix, text) in expected {
            let nodeID = "middle_001_2_\(suffix)"
            let assetID = reusedAssetIDs[suffix] ?? "voice_\(nodeID)"
            let node = try XCTUnwrap(nodes.first { $0["nodeId"] as? String == nodeID })
            XCTAssertEqual(node["text"] as? String, text)
            XCTAssertEqual(node["voiceAssetId"] as? String, assetID)
            XCTAssertEqual(node["voiceFileName"] as? String, "\(assetID).mp3")
            let audioURL = try XCTUnwrap(bundle.url(forResource: assetID, withExtension: "mp3"))
            XCTAssertGreaterThan(try AVAudioPlayer(contentsOf: audioURL).duration, 0)
        }
    }

    func testAllRegisteredMiddleVoicesAreBundledAndDecodable() throws {
        let bundle = Bundle(for: StoryPlayer.self)
        let url = try XCTUnwrap(bundle.url(forResource: "story_content.generated", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let scenarios = try XCTUnwrap(json["scenarios"] as? [[String: Any]])
        let scenario = try XCTUnwrap(scenarios.first { $0["scenarioId"] as? String == "middle_001_1" })
        let nodes = try XCTUnwrap(scenario["nodes"] as? [[String: Any]])
        let voices = nodes.compactMap { $0["voiceFileName"] as? String }
        XCTAssertEqual(voices.count, 15)
        XCTAssertEqual(Set(voices).count, 14)
        let updatedVoices = [
            "…今の、前転で抜けれたよ": "voice_middle_001_1_049",
            "ありがとうございます。お気遣いなく": "voice_middle_001_1_061",
            "いいの？": "voice_middle_001_1_075"
        ]
        for (text, assetID) in updatedVoices {
            let node = try XCTUnwrap(nodes.first { $0["text"] as? String == text })
            XCTAssertEqual(node["voiceAssetId"] as? String, assetID)
            XCTAssertEqual(node["voiceFileName"] as? String, "\(assetID).mp3")
        }
        for name in Set(voices) {
            let audioURL = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil), name)
            let audio = try AVAudioPlayer(contentsOf: audioURL)
            XCTAssertGreaterThan(audio.duration, 0)
        }
    }
}
