import Foundation

enum StoryCallPresentationState: String, Equatable {
    case starting
    case connected
    case ended
}

/// A small, UI-independent vocabulary of effects produced by CMS commands.
/// Unknown command strings never become fatal errors.
enum StoryCommandEffect: Equatable {
    case setBackground(String)
    case setScreenMode(StoryScreenMode)
    case showCG(String)
    case hideCG
    case setTyping(Bool)
    case presentModal
    case wait(milliseconds: UInt64)
    case setCallState(StoryCallPresentationState)
    case playAudio(String?)
    case recordAudio(String?)
}

struct StoryCommandDispatchResult: Equatable {
    let effects: [StoryCommandEffect]
    let diagnostic: String?

    static let none = StoryCommandDispatchResult(effects: [], diagnostic: nil)

    init(effect: StoryCommandEffect, diagnostic: String? = nil) {
        effects = [effect]
        self.diagnostic = diagnostic
    }

    init(effects: [StoryCommandEffect], diagnostic: String? = nil) {
        self.effects = effects
        self.diagnostic = diagnostic
    }
}

/// Converts the open-ended `command` / `command_args` CMS fields into the
/// finite set of effects understood by the current player.
struct StoryCommandDispatcher {
    static let maximumWaitMilliseconds: UInt64 = 5_000

    func dispatch(node: StoryNode) -> StoryCommandDispatchResult {
        guard let rawCommand = normalized(node.command) else { return .none }
        let command = rawCommand.lowercased()

        switch command {
        case "scene_change":
            let background = firstString(
                in: node.commandArgs,
                keys: ["background", "background_asset_id", "asset_id"]
            ) ?? normalized(node.background)
            let screenMode = firstString(in: node.commandArgs, keys: ["screen_mode"])
                .map(StoryScreenMode.init(rawValue:))
            var effects: [StoryCommandEffect] = []
            if let background { effects.append(.setBackground(background)) }
            if let screenMode { effects.append(.setScreenMode(screenMode)) }
            guard !effects.isEmpty else {
                return missingArgument(command: command, argument: "background / screen_mode")
            }
            return StoryCommandDispatchResult(effects: effects)

        case "show_cg":
            guard let assetID = firstString(
                in: node.commandArgs,
                keys: ["asset_id", "cg", "cg_asset_id"]
            ) ?? normalized(node.cg) ?? normalized(node.assetId) else {
                return missingArgument(command: command, argument: "asset_id")
            }
            return StoryCommandDispatchResult(effect: .showCG(assetID))

        case "hide_cg":
            return StoryCommandDispatchResult(effect: .hideCG)

        case "typing_show":
            return StoryCommandDispatchResult(effect: .setTyping(true))

        case "typing_hide":
            return StoryCommandDispatchResult(effect: .setTyping(false))

        case "show_modal":
            return StoryCommandDispatchResult(effect: .presentModal)

        case "wait":
            return waitResult(command: command, arguments: node.commandArgs)

        case "call_start":
            return StoryCommandDispatchResult(
                effect: .setCallState(.starting)
            )

        case "call_connected":
            return StoryCommandDispatchResult(
                effect: .setCallState(.connected)
            )

        case "call_end":
            return StoryCommandDispatchResult(
                effect: .setCallState(.ended)
            )

        case "play_audio":
            return StoryCommandDispatchResult(
                effect: .playAudio(
                    firstString(in: node.commandArgs, keys: ["asset_id", "audio", "audio_asset_id"])
                        ?? normalized(node.assetId)
                )
            )

        case "record_audio":
            return StoryCommandDispatchResult(
                effect: .recordAudio(
                    firstString(in: node.commandArgs, keys: ["asset_id", "audio", "audio_asset_id"])
                        ?? normalized(node.assetId)
                )
            )

        default:
            return StoryCommandDispatchResult(
                effects: [],
                diagnostic: "未対応のストーリーcommand: \(rawCommand)"
            )
        }
    }
}

private extension StoryCommandDispatcher {
    func waitResult(
        command: String,
        arguments: JSONValue?
    ) -> StoryCommandDispatchResult {
        guard let rawDuration = arguments?["duration_ms"],
              let duration = number(from: rawDuration),
              duration.isFinite else {
            return StoryCommandDispatchResult(
                effect: .wait(milliseconds: 0),
                diagnostic: "command \(command) のduration_msを解釈できません"
            )
        }

        let nonnegative = max(0, duration)
        let capped = min(nonnegative, Double(Self.maximumWaitMilliseconds))
        let diagnostic: String? = nonnegative > Double(Self.maximumWaitMilliseconds)
            ? "command wait のduration_msを5000msに制限しました"
            : nil
        return StoryCommandDispatchResult(
            effect: .wait(milliseconds: UInt64(capped.rounded())),
            diagnostic: diagnostic
        )
    }

    func firstString(in arguments: JSONValue?, keys: [String]) -> String? {
        for key in keys {
            if let value = normalized(arguments?[key]?.stringValue) { return value }
        }
        return nil
    }

    func number(from value: JSONValue) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .string(let string):
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func missingArgument(command: String, argument: String) -> StoryCommandDispatchResult {
        StoryCommandDispatchResult(
            effects: [],
            diagnostic: "command \(command) に\(argument)がありません"
        )
    }
}
