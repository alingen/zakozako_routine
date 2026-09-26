# 交流リアクションの実装報告

2026-09-27。アプリ正式名称: ざこざこルーティン。

参照元: [シナリオCMS](https://docs.google.com/spreadsheets/d/1Ifkw0X4TIOxe0f9EpZpZEGIexLg-xoXG8c-ro4I5MBM/edit)。2026-09-27 00:45 JST のライブ同期で、activeな条件52件・セリフ288件・通常会話45件を生成。
シート自体は変更していない。reaction_lines_draft / reaction_reference は生成物に取り込まない。

## A. 再利用したもの

- ReactionContext / ReactionContextProvider: 現在のルーティン数、達成数、残数、全達成、currentStreak / bestStreak / totalCompletionDays、完了・失敗・来訪時刻。
- RoutineYearStatisticsCalculator.periodFacts / RoutineStreak: 実際のcompletedAt、ルール変更前のアーカイブを含む対象期間、連続記録。週・月の持ち越し達成を当日完了として二重計上しない。
- UserActionEvent / UserActionEventRepository: app_opened / interaction_screen_opened / character_tapped / prohibition_urge / prohibition_failed。
- BlockedBehaviorRepository / BlockedBehaviorHistory: 失敗記録と、同じtargetIDの前アプリ日のkept確定結果。リアクション専用の失敗履歴は追加していない。
- AppDay: 午前4時境界。時刻は端末のローカル時刻、曜日は4時境界で決める。
- StoryContentBundle / StoryContentRepository / scenario-sync: 既存CMS取得・検証・生成・読み込み。
- InteractionCommentSelector: 重み付き抽選と直前の同一セリフ回避。
- シナリオのreplacingStoryTextMarkers(): 共通ファイルへ移し、ADV・チャット・交流で使用。

## B. 新規追加

- Models/ReactionContent.swift: ReactionCondition / ReactionLine（CMS定義、SwiftDataの保存モデルではない）。
- Services/ReactionConditionEvaluator.swift: 既存の事実から条件を判定し、表示済み管理用のキーを返す。
- Services/InteractionReactionService.swift: 最高priority→同順位を均等抽選→weightでセリフ抽選。条件がない／表示済みなら日替わりの通常会話へ戻る。
- Services/ContentTextFormatter.swift: 既存マーカー処理の共通配置先。
- InteractionReactionTests.swift / scenario-sync/test/reactions.test.ts: 条件・選択・同期の検証。

新しいBooleanをDBへ保存する仕組みは追加していない。UserDefaultsに保存するのは、その日の候補3件・前回の候補3件・直前のセリフID・当日表示済みの条件/イベントキーのみ。毎日4時に更新する。

## C. 実装したcondition_id（activeな52条件）

### ルーティン

- `routine_none_completed`
- `routine_one_completed`
- `routine_today_first_completed`
- `routine_half_completed`
- `routine_remaining_two`
- `routine_remaining_one`
- `routine_all_completed`
- `routine_all_completed_early`
- `routine_all_completed_late`
- `routine_completed_just_now`
- `routine_first_completion`
- `routine_yesterday_more`
- `routine_yesterday_less`
- `routine_full_streak`

### 継続・累積

- `streak_1`
- `streak_2`
- `streak_3`
- `streak_4`
- `streak_7`
- `streak_10`
- `streak_14`
- `streak_30`
- `streak_50`
- `streak_100`
- `streak_new_best`
- `streak_one_to_best`
- `streak_broken`
- `streak_long_broken`
- `streak_return_next_day`
- `streak_return_after_days`
- `total_completion_milestone`

### やらないこと

- `prohibition_urge`
- `prohibition_failed`
- `prohibition_urge_then_kept`
- `prohibition_one_failed`
- `prohibition_multiple_failed`
- `prohibition_failed_early`

### 来訪・タップ

- `interaction_first_today`
- `interaction_before_completion`
- `interaction_after_completion`
- `interaction_after_all_completed`
- `interaction_after_prohibition_failed`
- `interaction_many_today`
- `character_many_taps`
- `app_return_after_absence`

### 時間帯・曜日

- `morning_zero`
- `noon_zero`
- `evening_zero`
- `late_night_remaining`
- `early_morning_access`
- `late_night_access`
- `monday`

### 判定と表示の細部

- 完全達成の連続条件は、ユーザー指定の **7日以上**。日ごとの対象期間が存在し、その日末までに対象がすべて完了した日を数える。週・月の1回の達成を完了前の日へ遡らせない。
- 連続日数の節目と自己ベストは、当日も実際に完了している場合だけ。前日の連続数の持ち越しだけでは出さない。
- 継続途切れは最初の未達アプリ日が終わった翌日のみ。長期は直前7日以上。翌日復帰は未達1日を挟んだ再達成、数日ぶり復帰は未達2日以上を挟んだ再達成。
- 直後条件はシート指定の0〜120秒前。未来時刻・前アプリ日の出来事は除外する。
- 朝/昼/夜の0件は既存の通常会話と同じ4〜11時、12〜16時、17〜21時。深夜は0〜3時。04:00-06:59等の時刻範囲はシート値を読む。
- prohibition_urge / prohibition_failed は、その操作で作成されたUserActionEventのIDを渡したときだけ。ホームの既存の反応表示に接続し、後から交流画面を開いても操作直後として再生しない。交流来訪時はinteraction_after_prohibition_failed等の状態条件を使う。
- 「負けそうだったが守れた」は前アプリ日の同じtargetIDについて、BlockedBehaviorHistoryがkeptを確定した後だけ。当日途中の未敗北はkeptとしない。
- 条件は原則1アプリ日1回表示。新しい完了・失敗操作には元履歴の時刻/IDを使い、同じ日でも新しい出来事に反応できる。同priorityの条件は抽選し、固定順にしない。
- 通常会話は既存の有効候補から3件を重み付きで重複なく選び、当日中と再起動後も維持。翌日は前回3件をできるだけ避ける。CMS無効化・既存のプロフィール/時間帯条件で不適格になった候補だけは補充する。
- 吹き出しの形・色・位置は既存のまま。長いセリフと明示改行が省略されないよう3行上限だけを解除した。

## D. active=TRUEで未対応の条件

なし。52条件を実装した。active=FALSEの未確定条件は評価しない。
判定は既存データに残る対象期間・履歴の範囲に従う（削除された約束の履歴は復元しない）。

## E. strong / premium_only

フィールドはCMSから保持。現状の抽選条件には使用せず、strongかつpremium_only=TRUEでも通常候補。課金・加入判定・強さ設定は追加していない。

## F. [br]

Services/ContentTextFormatter.swift の String.replacingStoryTextMarkers() で [br]→改行、[sp]→半角スペース。
StoryNode.storyDisplayText、ADVTextLayout.formatted、InteractionComment.displayTextが同じ処理を使用する。/ は通常文字のまま。

## 検証

- iPhone 13 mini / iOS 17.5: 今回の条件判定と、関連する既存ルーティン・禁止行動・会話・ADVの94テスト成功。
- scenario-sync: 65テスト成功。型チェック成功。スナップショット再生成比較は差分なし、CMS診断error/warningとも0件。
- 全達成7日、Day1〜100、自己ベスト、中断/復帰、4時境界、月曜深夜、時刻帯、操作イベントの識別、同じtargetIDのkept確定、候補3件の永続化、優先度同点、weight、strong、改行を確認。
- ライブ同期に伴い、既存イベント名もシートの最新値「3問クイズ」に一致した。

## G. 変更ファイル

アプリ:

- Models: ReactionContent.swift（新規）、StoryContent.swift
- Services: ReactionConditionEvaluator.swift / InteractionReactionService.swift / ContentTextFormatter.swift（新規）、ReactionContext.swift、AppDependencies.swift
- Repositories: StoryContentRepository.swift、BlockedBehaviorRepository.swift
- ViewModels: InteractionViewModel.swift、HomeViewModel.swift
- Views/Interaction: InteractionView.swift、InteractionPresentation.swift、InteractionComponents.swift
- Views/Home: HomeView.swift
- Views/StoryPlayer: StoryVariantViews.swift、ADVStoryRenderer.swift
- Resources/GeneratedScenarios/story_content.generated.json
- MesugakiRoutineTests/InteractionReactionTests.swift（新規）

同期・資料:

- tools/scenario-sync/src: config.ts、fetch.ts、schema.ts、types.ts、normalize.ts、validate.ts、generate.ts、cli.ts
- tools/scenario-sync/test: reactions.test.ts（新規）、helpers.ts、unit.test.ts、current-fixture.test.ts
- tools/scenario-sync/fixtures/sheets-snapshot.json
- README.md、docs/interaction-reactions.md（本書）
