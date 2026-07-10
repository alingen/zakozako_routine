# メスガキルーティン (MesugakiRoutine)

日々のルーティン実行と、「やらないと決めた行動」の抑制を、キャラクターAIが支援するiOSアプリ。

このアプリの中心的な価値は「キャラクターと実際に声で会話しながらルーティンを習慣化すること」であり、
テキストUIはあくまで補助と位置づけている。そのため「ルーティンの進行」「キャラクターの応答生成」
「テキスト会話」「音声会話」を明確に分離した設計にしている。

公開審査リスクを考慮し、アプリ内部の表示名は「メスガキ」ではなく **「小悪魔コーチ」** にしている
(コードベース・リポジトリ名としての "Mesugaki" は内部識別子としてのみ使用)。

## 現在実装済みの機能

- ルーティン管理(作成・編集・削除、朝/夜/カスタム種別)
- ルーティンステップ管理(追加・削除・並び替え・名称編集)
- ルーティン実行セッション(開始・再開・完了/スキップ/失敗の記録)
- ステップごとのイベントログ(RoutineEvent として永続化)
- キャラクター設定(名前・煽り強度・褒め方・叱り方・禁止表現・プリセット選択)
- キャラクター応答生成: ローカルテンプレート、およびOpenAI Chat Completions API(APIキーがKeychainにある場合、自動でこちらに切り替わる)
- 音声会話の基盤: Apple標準の音声認識(Speech framework)+ 音声合成(AVSpeechSynthesizer)による、話しかけると返事をしてくれるループ(`RoutineSessionView`に最小限のマイクボタンとして配線済み。UI/UXの作り込みは別途行う前提)
- 「やらないこと」リストの管理と、自由入力テキストとの簡易マッチング
- 初回起動時のサンプルデータ投入(朝/夜ルーティン、やらないことリスト、デフォルトキャラ)
- SwiftData によるローカル永続化

未実装(意図的にダミー/未着手):

- OpenAI Realtime API(GPT-Live) 連携本体(`VoiceConversationEngine` の別実装として追加する想定。現状はApple標準音声によるつなぎの実装)
- Siri Shortcuts / App Intents(「Hey Siri、〜で朝ルーティン」のような特定ルーティン起動)
- ローカル通知
- Supabase / Firebase 等とのバックエンド同期
- 複数キャラクタープリセットの拡充(現状はデフォルト1体のみ投入)
- 音声会話モードの本格的なUI/UXデザイン(現状は動作確認用の最小限のボタン)

## ディレクトリ構成

```
MesugakiRoutine/
  App/
    MesugakiRoutineApp.swift      # @main, ModelContainer構築, 初回シード実行
  Models/                          # SwiftData @Model
    Routine.swift
    RoutineStep.swift
    RoutineSession.swift
    RoutineEvent.swift
    CharacterPreset.swift
    BlockedBehavior.swift
  Repositories/                    # SwiftDataへのCRUDをラップ
    RoutineRepository.swift
    RoutineSessionRepository.swift
    CharacterRepository.swift
    BlockedBehaviorRepository.swift
  Engines/                         # ドメインロジック本体(UI非依存)
    RoutineEngine.swift            # セッション進行・現在ステップ判定・完了/スキップ/失敗記録
    CharacterEngine.swift          # プリセットの選択と応答生成の依頼
  Services/                        # Engine間の調停・AI応答生成・音声会話・依存構築
    CharacterResponseGenerating.swift  # AI応答生成のprotocol抽象化(状況・会話履歴を含む)
    LocalCharacterResponseGenerator.swift # ローカルテンプレート実装
    OpenAIChatCompletionsClient.swift     # OpenAI Chat Completions APIを叩くネットワーククライアント
    OpenAICharacterResponseGenerator.swift # ↑を使ったCharacterResponseGenerating実装
    ForbiddenPhraseFilter.swift     # 禁止表現フィルタ(Local/OpenAI共通)
    KeychainService.swift           # APIキーなどの秘密情報をKeychainに保存する薄いラッパー
    LocalSecretsSeeder.swift         # 開発用: Secrets.local.json からKeychainへ初回のみ読み込む
    VoiceConversationEngine.swift    # 音声会話セッションのprotocol抽象化(状態遷移・イベント)
    NativeVoiceConversationEngine.swift # Apple標準音声(Speech + AVSpeechSynthesizer)によるつなぎの実装
    ConversationCoordinator.swift   # Conversation Layerの中核。RoutineEngine/CharacterEngineを束ねる
    DataSeeder.swift                # 初回起動時のサンプルデータ投入
    AppDependencies.swift           # ModelContextからRepository/Engineを組み立てるファクトリ
  ViewModels/                      # 各画面のObservableな状態管理
    HomeViewModel.swift
    RoutineListViewModel.swift
    RoutineEditViewModel.swift
    RoutineSessionViewModel.swift
    CharacterSettingsViewModel.swift
    BlockedBehaviorListViewModel.swift
    ConversationMessage.swift      # 会話ログ表示用モデル
  Views/                           # SwiftUI画面(ロジックを持たない)
    Home/HomeView.swift
    RoutineList/RoutineListView.swift
    RoutineEdit/RoutineEditView.swift
    RoutineSession/RoutineSessionView.swift
    CharacterSettings/CharacterSettingsView.swift
    BlockedBehavior/BlockedBehaviorListView.swift
  Extensions/
    Collection+Safe.swift
```

`project.yml` は [XcodeGen](https://github.com/yonaskolb/XcodeGen) 用の定義。`.xcodeproj` はこれから生成する
(リポジトリには `.xcodeproj` をコミットせず、`xcodegen generate` で都度生成する運用を推奨)。

## データモデル

- **Routine**: id, title, description, type(morning/night/custom), isActive, createdAt, updatedAt。`steps` を cascade delete で保持。
- **RoutineStep**: id, routineId(親リレーション), title, description, orderIndex, estimatedMinutes, isRequired, createdAt, updatedAt。
- **RoutineSession**: id, routineId, startedAt, completedAt, status(active/completed/abandoned), currentStepId。`events` を cascade delete で保持。
- **RoutineEvent**: id, sessionId(親リレーション), stepId(nullable), eventType(started/completed_step/skipped_step/failed_step/blocked_behavior/completed_routine/abandoned), userText, aiText, createdAt。
- **CharacterPreset**: id, name, description, basePrompt(将来AIのシステムプロンプト用), praiseStyle, scoldStyle, intensity, forbiddenPhrases, isSelected, createdAt, updatedAt。
- **BlockedBehavior**: id, title, description, triggerText(自由入力とのマッチング用), counterMessage, isActive, createdAt, updatedAt。

## Routine Engine (`Engines/RoutineEngine.swift`)

ルーティン実行の唯一の真実源。責務は以下に限定している。

- セッションの開始・再開(`startSession`)
- 現在のステップ・完了済みステップ・残りステップの算出(`progress`)
- ステップ完了/スキップ/失敗の記録と次ステップへの遷移(`recordOutcome`)。全ステップ終了時は自動的にセッションを `completed` にし `completed_routine` イベントを積む
- 途中終了の記録(`abandon`)
- 「やらないこと」検知の記録(`recordBlockedBehavior`)
- 最近のイベント取得(`recentEvents`)

UIやキャラクター応答には一切依存せず、`RoutineProgress` という不変のスナップショットを返すだけなので、
将来バックグラウンド実行や音声UIに置き換わっても再利用できる。

## Character Engine (`Engines/CharacterEngine.swift` + `Services/CharacterResponseGenerating.swift`)

キャラクターの口調・煽り強度を管理し、状況(`CharacterSituation`)に応じた応答を返す。
応答生成そのものは protocol で抽象化されている。

```swift
protocol CharacterResponseGenerating {
    func generateResponse(context: CharacterResponseContext) async -> CharacterResponse
}
```

現在は2つの実装がある。

- `LocalCharacterResponseGenerator`: AI APIを使わずローカルテンプレートで応答する
- `OpenAICharacterResponseGenerator`: OpenAI Chat Completions API(`gpt-4o-mini`)で応答を生成する。会話履歴(`ConversationHistoryItem`)を踏まえた返答ができる

`AppDependencies.swift` が Keychain に OpenAI APIキーが保存されているかどうかだけを見て、どちらを使うか自動的に切り替える(ネットワークエラー時は`OpenAICharacterResponseGenerator`内部で`LocalCharacterResponseGenerator`にフォールバックする)。APIキーはアプリの「キャラクター設定」画面から保存・削除でき、`KeychainService`経由でKeychainにのみ保存される(ソースコード・UserDefaultsには書かない)。禁止表現フィルタ(`ForbiddenPhraseFilter`)はどちらの実装の出力にも同じようにかかる。

## Conversation Layer

会話には「テキスト(ターン制)」と「音声(常時接続)」の2つの経路があり、どちらも同じ `RoutineEngine` / `CharacterEngine` を土台にしている。

### テキスト会話 (`Services/ConversationCoordinator.swift`)

ユーザー操作(完了/スキップ/失敗/次なに？/助けて/自由入力)を受け取り、RoutineEngineに進行を委ね、
CharacterEngineから返答を取得して `Turn`(進行状態 + キャラクターのセリフ)として返すだけの薄い調停役。
このセッション中の会話履歴も保持し、AI応答生成のたびに文脈として渡す。SwiftUIに一切依存しない。

### 音声会話 (`Services/VoiceConversationEngine.swift` + `NativeVoiceConversationEngine.swift`)

このアプリの本命の体験(「話しかけているうちに習慣化する」)を担う層。`CharacterResponseGenerating` が
1問1答のテキスト応答を抽象化しているのに対し、こちらは「聞く→考える→話す」を繰り返す持続的な
セッションのライフサイクルを抽象化している。

```swift
protocol VoiceConversationEngine: AnyObject {
    var delegate: VoiceConversationDelegate? { get set }
    var state: VoiceConversationState { get }  // idle / listening / thinking / speaking / error
    func start() async throws
    func stop()
    func speak(_ text: String)
}
```

現在は `NativeVoiceConversationEngine` が唯一の実装で、Apple標準の `SFSpeechRecognizer`(音声認識)と
`AVSpeechSynthesizer`(音声合成)を組み合わせ、認識したテキストを既存の `ConversationCoordinator.submitFreeText`
に渡して返答をもらい、読み上げる。声の自然さは標準ボイス相当であり、「女の子のリアルさ」という核の価値は
まだ出せていない。あくまで「聞く→考える→話す」ループの土台・動作確認用の実装と位置づけている。

`RoutineSessionView` には動作確認用の最小限のマイクボタンとして配線済み(見た目の作り込みは別途行う前提)。

## 将来追加する予定の機能

- **OpenAI Realtime API (GPT-Live)**: `VoiceConversationEngine` に準拠する `OpenAIRealtimeVoiceConversationEngine` を追加し、
  `NativeVoiceConversationEngine` と差し替えるだけで低遅延・自然な声・割り込み対応の本格的な音声会話に切り替えられる設計にしてある。
  使用量課金が発生するため、UI/UXが固まってから投入する想定。
- **音声会話画面のUI/UXデザイン**: `VoiceConversationState`(listening/thinking/speaking)を見た目に反映する画面デザイン。今は最小限のボタン+ラベルのみ。
- **Siri Shortcuts / App Intents**: 「Hey Siri、[アプリ名]を開いて」はOS標準機能で追加実装なしに動く。「〜で朝ルーティン」のように特定ルーティンへ直接ジャンプさせる場合はApp Shortcuts(App Intents)を追加実装する。
- **通知**: 朝/夜ルーティンの開始リマインドをローカル通知で実装。
- **バックエンド同期(Supabase / Firebase)**: `Repositories/` 層の実装をリモートAPI越しに差し替える、もしくは同期レイヤーを追加する。

## 次にやるべき開発タスク

1. 音声会話モード(`RoutineSessionView`のマイクボタン)の実機での一通りの動作確認(認識精度・無音検知のタイミング・割り込みなど)。
2. 音声会話画面のUI/UXデザイン(マイク状態の可視化、キャラクターの存在感、字幕表示など)。
3. 音声/ボタン操作で「できた」「スキップ」等の意図を検出してルーティン進行(`recordOutcome`)に反映する仕組み(現状、音声中の自由発話はルーティン進行と連動していない)。
4. CharacterPreset の複数プリセット化(現状はデフォルト1体のみ)。
5. RoutineEvent の一覧・詳細表示画面(現状Homeの「最近の完了ログ」のみ)。
6. `BlockedBehaviorRepository.firstMatch` の精度改善(現状は単純な部分一致)。
7. ユニットテスト整備(RoutineEngineの状態遷移、LocalCharacterResponseGeneratorのテンプレート出力)。
8. OpenAI Realtime API(GPT-Live)本体の実装。

## セットアップ

```bash
brew install xcodegen   # 未インストールの場合
xcodegen generate
open MesugakiRoutine.xcodeproj
```

`iOS 17.0` 以上のシミュレータ/実機で `MesugakiRoutine` スキームを実行する。
