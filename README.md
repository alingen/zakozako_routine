# ザコルーティン（MesugakiRoutine）

毎日の「やること」と「やらないこと」を記録し、キャラクターとの会話やストーリーを習慣の継続につなげるiOSアプリです。SwiftUIとSwiftDataで実装しており、対応OSはiOS 17以降です。

App Store向けの表示名は「小悪魔コーチ」です。`MesugakiRoutine` はXcode targetやコード上の内部名として使用しています。

## 現在の画面

ルートは4タブ構成で、各タブがそれぞれ1つの `NavigationStack` を持ちます。

| タブ | 主な機能 |
| --- | --- |
| ホーム | 現在のコーチ、今日の約束、挑戦中の「やらないこと」、自分の直近記録から作る「みんなのざこ速報」 |
| 記録 | 月間カレンダー、直近30日の達成率、全体の連続達成日数 |
| 交流 | キャラクター表示、今日の会話、メイン／サブストーリー一覧、思い出ギャラリー |
| 設定 | ユーザー名・呼び方、サボり通知、Debugビルド専用の進行値・進捗操作 |

ホームから約束の作成・編集・削除、回数の記録、完了演出を行えます。開始予定時刻を設定した約束には、未達成の場合だけローカル通知を予約できます。「今日の約束を開く」App Intentも実装されています。

## 習慣データ

### Routine

`Routine` はユーザーが実行する「約束」です。ステップや実行セッションは持たず、次の値を中心に管理します。

- 集計期間: 1日／1週間／1か月
- 期間内の目標回数
- 1回実行した時刻の配列 `progressEvents`
- 1日単位の場合の対象曜日
- 任意の開始予定時刻とSF Symbol

ホームでカードをタップするたびに実行時刻を1件追加し、期間内の件数から進捗率と達成を計算します。`RoutineStreak` は各約束の連続達成日数と、「いずれかの約束を達成した日」の全体連続日数を保存値ではなくログから算出します。

古い実行ログは現在、肥大化防止のため `RoutineRepository` が直近3か月より前を削除します。そのため、生涯累積日数を表す正確な指標やストーリー解放条件はまだありません。CMSの継続条件には現在の連続日数 `continuous_days` を使用します。

### BlockedBehavior

`BlockedBehavior` はユーザーが「やらない」と決めた行動です。同時に挑戦できるのは1件で、日／週／月ごとの上限回数と消費時刻 `usageEvents` を持ちます。上限に達した期間は失敗となり、日付が変わると未評価日を自動判定します。14日連続で守ると卒業し、次の項目を追加できます。

### 朝4時の日付境界

日、週、月の集計、対象曜日、連続達成日数、今日の会話はすべて `AppDay` を通し、午前4時をアプリ内の日付境界として扱います。たとえば午前3時59分は前日のアプリ日、午前4時から新しいアプリ日です。通知の発火時刻そのものは通常の時計時刻です。

## 永続化

アプリ起動時に1つのSwiftData `ModelContainer` を構築し、次の6モデルを登録します。

| モデル | 保存内容 |
| --- | --- |
| `Routine` | 約束の設定と実行時刻 |
| `BlockedBehavior` | やらないことの設定、消費時刻、連続日数、卒業状態 |
| `StoryEventProgress` | イベントの解放、初回閲覧、既読、完了回数 |
| `StoryPlaybackProgress` | playback keyごとの現在ノード、訪問履歴、選択履歴、閲覧CG |
| `StoryProfileValue` | 選択肢やノードが保存するプロフィール値、関係phase |
| `StoryMemoryUnlock` | 解放済みCGと解放元のイベント／シナリオ |

`StoryStateRepository` は選択履歴・プロフィール値・checkpoint、または完了・既読・CG解放・phase更新を同じ `ModelContext` 上でまとめて保存します。「最初から読む」は再生checkpointだけを初期化し、既読状態と解放済みの思い出は保持します。

ユーザー名、呼び方、通知設定、今日の会話の初回割当日は `AppSettingsStore` を介して `UserDefaults` に保存します。バックエンド同期は実装していません。

## ストーリーアーキテクチャ

### Content

`StoryContentBundle` は `scenarios`、`choiceGroups`、`events` の3配列を持つ読み取り専用データです。`StoryContentRepository` がアプリbundle内の `Resources/GeneratedScenarios/story_content.generated.json` を読み込み、scenario／choice／eventの検索、daily scenarioの整列、CGカタログの生成を担います。

`StoryScenarioGraph` はscenario内だけで遷移を解決します。次ノードの優先順位は次の通りです。

1. 選択したchoiceの `nextNodeId`
2. 現在nodeの `nextNodeId`
3. `lineOrder` の次node

`minPhase`／`maxPhase` の範囲外にあるnodeは遷移しながら読み飛ばします。参照切れや自動進行cycleはクラッシュさせず、回収可能なエラーとしてPlayerへ返します。

### Conditionと解放

`StoryProgressMetricsProvider` は既存のRoutine連続日数、ストーリープロフィール値、完了イベントIDを条件評価へ渡します。`StoryConditionEvaluator` は同じイベントの複数条件をANDで評価し、`eq`、`ne`、`gt`、`gte`、`lt`、`lte`、`exists` を扱います。未知の条件種別や演算子はfail-closedで未達成とし、診断情報を表示側へ返します。

`StoryUnlockService` は条件を満たしたイベントだけを永続化します。解放は単調増加で、一度解放したイベントは後から条件値が下がっても再ロックしません。

Premiumを表すCMS列、StoreKit entitlement、課金画面は現在いずれも未定義です。商品アクセス判定は条件評価から分離した `StoryAccessPolicy` の拡張点だけを用意しており、現在の既定実装は全イベントを許可します。Premium条件をイベントIDや日数でハードコードしないでください。

### Playerとrenderer

`StoryPlayer` はSwiftUIに依存しない `@MainActor` の進行エンジンです。graph traversal、phase filter、choiceとプロフィール保存、checkpointからの再開、restart／reread、完了処理、回収可能エラーを担当します。`StoryCommandDispatcher` はCMSの `command`／`commandArgs` を背景、CG、画面モード、typing、modal、wait、通話状態、音声などの表示効果へ変換します。未知のcommandは致命的エラーにしません。

`StoryPlayerView` は交流画面から `fullScreenCover` で表示する統合画面です。進行状態に応じて以下の純粋なrendererへ描画を委譲し、操作はcallbackでPlayerへ返します。renderer自身はシナリオ遷移や `NavigationStack` を持ちません。

- `ADVStoryRenderer`: 中・大イベントを横画面で表示し、背景、立ち絵、CG、3行固定の台詞・地の文、選択肢を描画
- `ChatStoryRenderer`: 表示済みメッセージ、typing、画像・音声メッセージ、選択肢
- `CallStoryRenderer`: 着信／発信／通話／終了などの演出。実際の通話や録音は行いません
- `StoryVariantViews`: title card、narration、dialogue、scene transition、monologue、modalなどの小部品

画像、背景、CGがbundleにない場合、`StoryAssetView` は用途別アイコンとasset IDを含むプレースホルダーを表示します。未知の画面モード／UI variantにも安全なfallbackがあります。音声メッセージはbundle内に素材がある場合だけ `AVAudioPlayer` で再生し、欠損時はasset IDと警告を表示します。

### 交流画面

交流トップには現在のキャラクター、今日の会話、ストーリー、思い出を表示します。

- 今日の会話: 初回表示日をanchorに、`scenarioId` 順のdaily scenarioをアプリ日ごとに1話選択します。未読でも翌日は次へ進み、末尾まで進むと先頭へ戻ります。playback keyは `daily:yyyy-MM-dd` です。
- ストーリー一覧: `storyCategory` の `main`／`sub` だけで分類し、chapterと `episodeOrder` 順に表示します。未解放話も隠さず、lock、NEW、既読、条件の達成状況を表示します。
- 思い出: CGカタログ全体を並べ、未解放項目は伏せて表示します。ストーリー完了時に解放されたCGだけを全画面表示できます。

## 主なディレクトリ

```text
MesugakiRoutine/
  App/                 # @main、SwiftData schema、4タブのルート
  AppIntents/          # 「今日の約束を開く」Intent／Shortcut
  DesignSystem/        # AppColor、共通テーマ、進捗円、アイコン
  Models/              # Routine、BlockedBehavior、Story content／persistence
  Repositories/        # SwiftData CRUDとStory content index
  Services/            # 日付・進捗・通知・Story graph／condition／player
  ViewModels/          # Home、記録、交流、設定の画面状態
  Views/               # タブ画面、編集画面、交流画面、Story renderer
  Resources/
    GeneratedScenarios/story_content.generated.json
MesugakiRoutineTests/  # 日次会話、graph、state、condition、実CMS Playerのtests
tools/scenario-sync/   # Google Sheets検証・単一JSON生成CLI
project.yml            # XcodeGenのプロジェクト定義
```

`AppDependencies` が1つの `ModelContext` から各RepositoryとServiceを組み立てます。ViewModelはObservationの `@Observable` と `@MainActor` を使い、Viewは `AppColor` のセマンティックカラーを参照します。現在のパレットはライト用の単一値なので、ルートでライトモードに固定しています。

## セットアップ、ビルド、テスト

必要環境:

- Xcode（iOS 17以降のSimulatorまたは実機）
- XcodeGen
- ストーリー同期を行う場合はNode.js 20以降

```bash
brew install xcodegen
xcodegen generate
open MesugakiRoutine.xcodeproj
```

コマンドラインでビルドする場合:

```bash
xcodebuild \
  -project MesugakiRoutine.xcodeproj \
  -scheme MesugakiRoutine \
  -destination 'generic/platform=iOS Simulator' \
  build
```

利用可能なSimulator名を確認してunit testsを実行します。

```bash
xcrun simctl list devices available

xcodebuild \
  -project MesugakiRoutine.xcodeproj \
  -scheme MesugakiRoutine \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```

`.xcodeproj` は `project.yml` から生成します。ファイル追加後は `xcodegen generate` を再実行し、生成済みプロジェクトを手編集しないでください。

## Google Sheetsからストーリーを同期する

ストーリーCMSは次の一方向フローです。

```text
Google Sheets（SSOT、scenario-syncはread-onlyで取得）
  ├─ scenarios: 1行 = 1 node
  ├─ choices:   1行 = 1 choice option
  └─ events:    1行 = 1 AND condition
       ↓ scenario-syncで取得・正規化・検証・安定ソート
StoryContentBundle
       ↓ atomic write
MesugakiRoutine/Resources/GeneratedScenarios/story_content.generated.json
```

Google Sheetsが唯一の正本（SSOT）です。生成JSONと `fixtures/sheets-snapshot.json` は成果物／再現用snapshotであり正本ではありません。どちらも直接編集せず、必ずGoogle Sheetsを更新して `scenario-sync` から再生成してください。ライブ取得失敗時にsnapshotへ暗黙fallbackすることもありません。

初回セットアップ:

```bash
npm --prefix tools/scenario-sync ci
npm --prefix tools/scenario-sync run typecheck
npm --prefix tools/scenario-sync test
```

リポジトリルートからの主な同期コマンド:

```bash
# ライブ取得・検証・差分表示だけ。ファイルは変更しない
npm --prefix tools/scenario-sync run sync

# ライブ正本とコミット済み生成JSONに差分があれば非ゼロ終了
npm --prefix tools/scenario-sync run sync:check

# ライブ正本から生成JSONをatomic write
npm --prefix tools/scenario-sync run sync:write

# オフラインで、明示したsnapshotを検証・比較
npm --prefix tools/scenario-sync run sync:check -- --snapshot
```

`--write` がない `sync` は常に非破壊のplanです。`--write` はライブ正本に対してだけ利用できます。認証方法、環境変数、全コマンド、schemaの詳細は [tools/scenario-sync/README.md](tools/scenario-sync/README.md) を参照してください。

### 現行シートの既知warning

現行Google Sheetsには、生成を止めない既知warningが合計5件あります。

- `daily_001` のchoice group `first_day_can_do` から参照する `daily_001_09` と `daily_001_10` が存在しない: 2件
- 上記の参照切れの影響で `daily_001_06`、`daily_001_07`、`daily_001_08` の本来の到達経路を確定できない: 3件

参照切れchoiceは特定IDの例外ではなく、全scenario共通でwarningにしてPlayerが `line_order` へ復旧します。
node自身の参照切れやscenario外へのchoice参照、その他の必須値、型、重複、metadata不一致、
終了不能cycleなどの構造破損はerrorとなります。3タブのどれかが空、または有効行が0件の場合も、
取得失敗を全削除と誤認しないよう生成物を書き換えず停止します。
