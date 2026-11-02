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

    /// A text file, an image, and a folder, as the "+" chip or a drop attaches them.
    static let attachments: [PromptAttachment] = [
        PromptAttachment(
            url: URL(filePath: "/Users/preview/Developer/native/docs/keyboard.md"),
            content: .text("# Keyboard\n"), byteCount: 18_400),
        PromptAttachment(
            url: URL(filePath: "/Users/preview/Desktop/Composer queued state.png"),
            content: .image(screenshot, mimeType: "image/png"), byteCount: 1_240_000),
        PromptAttachment(
            url: URL(filePath: "/Users/preview/Developer/native/native/Composer", directoryHint: .isDirectory),
            content: .reference, byteCount: nil),
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
