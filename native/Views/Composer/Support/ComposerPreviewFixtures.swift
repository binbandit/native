#if DEBUG
import ACP
import CoreGraphics
import Foundation
import ImageIO

/// Sample composer data for previews. Session settings are the configuration options Claude Code's
/// adapter (claude-agent-acp) sends with `session/new`, decoded the way the app receives them.
enum ComposerPreviewFixtures {
    /// Model, effort, Fast mode, Agent and output style, with Full access as the permission mode.
    static let configOptions: [ConfigOption] = (decode(configJSON(mode: "bypassPermissions")) ?? []).map {
        ClaudeCodeSessionSettings.permissionMapping.presenting($0)
    }
    /// The same, while Plan Mode stands in for the permission mode.
    static let planModeOptions: [ConfigOption] = (decode(configJSON(mode: "plan")) ?? []).map {
        ClaudeCodeSessionSettings.permissionMapping.presenting($0)
    }

    static let settings = ComposerSettings(configOptions)
    static let settingsWithoutExtras = ComposerSettings(configOptions.filter { $0.category != "other" })
    static let planModeSettings = ComposerSettings(planModeOptions)

    static let plan: [PlanEntry] =
        decode(
            """
            [
              {"content": "Read ComposerView.swift and the queue model", "priority": "high", "status": "completed"},
              {"content": "Queue follow-ups while a turn runs", "priority": "high", "status": "in_progress"},
              {"content": "Show queued messages above the draft, with Send Now", "priority": "medium", "status": "pending"},
              {"content": "Run swift test in Packages/ACP", "priority": "low", "status": "pending"}
            ]
            """) ?? []

    static let commands: [ComposerSlashCommand] =
        [ComposerSlashCommand(native: "clear", description: "Start over with a fresh conversation, keeping this one")]
        + (decode(
            """
            [
              {"name": "compact", "description": "Clear conversation history but keep a summary in context"},
              {"name": "review", "description": "Review a pull request"},
              {"name": "$review", "description": "Use the review skill"},
              {"name": "init", "description": "Initialize a new AGENTS.md file with codebase documentation"},
              {"name": "security-review", "description": "Complete a security review of the pending changes on the current branch"}
            ]
            """) as [AvailableCommand]? ?? []).map { ComposerSlashCommand($0) }

    static let files = [
        "native/Views/Composer/ComposerView.swift",
        "native/Views/Composer/Sections/",
        "native/Views/Composer/Sections/QueuedPromptsSection.swift",
        "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift",
        "docs/keyboard.md",
    ]

    /// A text file, an image, and a folder, as the "+" chip or a drop attaches them.
    static let attachments: [PromptAttachment] = [
        PromptAttachment(
            url: URL(filePath: "/Users/preview/Developer/native/docs/keyboard.md"),
            content: .text("# Keyboard\n"), byteCount: 18_400),
        PromptAttachment(
            url: URL(filePath: "/Users/preview/Desktop/Composer queued state.png"),
            content: .image(screenshot, mimeType: "image/png"), byteCount: 1_240_000),
        PromptAttachment(
            url: URL(filePath: "/Users/preview/Developer/native/native/Views/Composer", directoryHint: .isDirectory),
            content: .reference, byteCount: nil),
    ]

    static let queued: [PromptQueue.Item] = [
        PromptQueue.Item("Also cover the empty queue in the tests"),
        PromptQueue.Item(
            "Then rename QueuedPromptRow to something that says it can be dragged, and update the call sites in the composer and the session view so nothing else changes"
        ),
        PromptQueue.Item("Run the iPad check when you're done", attachments: [attachments[0]]),
    ]

    static let nextSteps: [ComposerNextStep] = [
        ComposerNextStep(id: "review", title: "Review Changes", systemImage: "plus.forwardslash.minus") {},
        ComposerNextStep(id: "commit", title: "Commit", systemImage: "checkmark.circle") {},
        ComposerNextStep(id: "pull-request", title: "Open Pull Request", systemImage: "arrow.triangle.pull") {},
    ]

    /// A small drawn picture standing in for a screenshot, so image chips show a real thumbnail.
    static let screenshot: Data = {
        let width = 96, height = 64
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return Data() }
        context.setFillColor(CGColor(red: 0.93, green: 0.93, blue: 0.92, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 26, height: height))
        context.setFillColor(CGColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1))
        context.fill(CGRect(x: 34, y: 10, width: 54, height: 14))
        let data = NSMutableData()
        guard let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }()

    private static func configJSON(mode: String) -> String {
        """
        [
          {"id":"mode","name":"Mode","description":"Task permission mode","category":"mode","type":"select","currentValue":"\(mode)","options":[
            {"value":"default","name":"Manual","description":"Always ask before making changes"},
            {"value":"acceptEdits","name":"Accept edits","description":"Automatically accept all file edits"},
            {"value":"plan","name":"Plan","description":"Create a plan before making changes"},
            {"value":"auto","name":"Auto","description":"Claude handles permission decisions"},
            {"value":"bypassPermissions","name":"Bypass permissions","description":"Accepts all permissions"}
          ]},
          {"id":"model","name":"Model","description":"AI model to use","category":"model","type":"select","currentValue":"opus","options":[
            {"value":"default","name":"Default (recommended)","description":"Opus"},
            {"value":"opus","name":"Opus 5.5","description":"Opus 5.5 · Best for everyday, complex tasks · $4/$20 per Mtok"},
            {"value":"claude-fable-5","name":"Claude Fable 5","description":"From gateway"}
          ]},
          {"id":"effort","name":"Effort","description":"Available effort levels for this model","category":"thought_level","type":"select","currentValue":"high","options":[
            {"value":"default","name":"Default"},{"value":"low","name":"Low"},{"value":"medium","name":"Medium"},{"value":"high","name":"High"},{"value":"xhigh","name":"Xhigh"},{"value":"max","name":"Max"}
          ]},
          {"id":"fast","name":"Fast mode","description":"Faster responses on supported models","category":"model_config","type":"select","currentValue":"off","options":[
            {"value":"on","name":"On"},{"value":"off","name":"Off"}
          ]},
          {"id":"agent","name":"Agent","description":"Agent to use for this session","category":"other","type":"select","currentValue":"default","options":[
            {"value":"default","name":"Default"},{"value":"reviewer","name":"Reviewer"}
          ]},
          {"id":"output","name":"Output style","description":"How responses are written","category":"other","type":"select","currentValue":"default","options":[
            {"value":"default","name":"Default"},{"value":"explanatory","name":"Explanatory"},{"value":"learning","name":"Learning"}
          ]}
        ]
        """
    }

    /// Decodes wire JSON, or nil if a fixture stops matching the schema (the preview then shows less).
    static func decode<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
#endif
