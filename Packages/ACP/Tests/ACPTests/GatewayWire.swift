import Foundation

@testable import ACP

/// Claude Code through claude-agent-acp 0.93.0 with a model gateway configured: the `configOptions`
/// of a real `session/new` result (captured 2026-10-25), unedited. The gateway's entries come with
/// the description "From gateway", repeat names ("GPT-4o" five times), and carry values that arrive
/// reversed after a "claude-fable-5-dd-" prefix ("…5.4-ukiah-edualc/tolipoc" for Claude Haiku 4.5),
/// exactly as sent: none of it holds a bidirectional control character.
enum GatewayWire {
    static let configOptions = #"""
        [
          {"id":"mode","name":"Mode","description":"Session permission mode","category":"mode","type":"select","currentValue":"auto","options":[
            {"value":"default","name":"Manual","description":"Always ask before making changes"},
            {"value":"acceptEdits","name":"Accept edits","description":"Automatically accept all file edits"},
            {"value":"plan","name":"Plan","description":"Create a plan before making changes"},
            {"value":"auto","name":"Auto","description":"Claude handles permission decisions"},
            {"value":"bypassPermissions","name":"Bypass permissions","description":"Accepts all permissions"}
          ]},
          {"id":"model","name":"Model","description":"AI model to use","category":"model","type":"select","currentValue":"opus","options":[
            {"value":"default","name":"Default (recommended)","description":"Opus"},
            {"value":"opus","name":"Opus 5.5","description":"Opus 5.5 · Best for everyday, complex tasks · $4/$20 per Mtok"},
            {"value":"claude-fable-5","name":"Claude Fable 5","description":"From gateway"},
            {"value":"claude-fable-5-1","name":"Claude Fable 5.1","description":"From gateway"},
            {"value":"claude-fable-5-dd-5.4-ukiah-edualc/tolipoc","name":"Claude Haiku 4.5","description":"From gateway"},
            {"value":"claude-fable-5-dd-weiver-otua-xedoc","name":"Codex Auto Review","description":"From gateway"},
            {"value":"claude-fable-5-dd-a-hcraes-tolipoc/tolipoc","name":"Copilot Agent A","description":"From gateway"},
            {"value":"claude-fable-5-dd-b-hcraes-tolipoc/tolipoc","name":"Copilot Search B","description":"From gateway"},
            {"value":"claude-fable-5-dd-3160-obrut-5.3-tpg/tolipoc","name":"GPT 3.5 Turbo","description":"From gateway"},
            {"value":"claude-fable-5-dd-obrut-5.3-tpg/tolipoc","name":"GPT 3.5 Turbo","description":"From gateway"},
            {"value":"claude-fable-5-dd-3160-4-tpg/tolipoc","name":"GPT 4","description":"From gateway"},
            {"value":"claude-fable-5-dd-4-tpg/tolipoc","name":"GPT 4","description":"From gateway"},
            {"value":"claude-fable-5-dd-weiverp-5210-4-tpg/tolipoc","name":"GPT 4 Turbo","description":"From gateway"},
            {"value":"claude-fable-5-dd-anul-6.5-tpg","name":"GPT 5.6 Luna","description":"From gateway"},
            {"value":"claude-fable-5-dd-los-6.5-tpg","name":"GPT 5.6 Sol","description":"From gateway"},
            {"value":"claude-fable-5-dd-arret-6.5-tpg","name":"GPT 5.6 Terra","description":"From gateway"},
            {"value":"claude-fable-5-dd-artsa-6-tpg","name":"GPT 6.0 Astra","description":"From gateway"},
            {"value":"claude-fable-5-dd-anul-6-tpg","name":"GPT 6.0 Luna","description":"From gateway"},
            {"value":"claude-fable-5-dd-los-6-tpg","name":"GPT 6.0 Sol","description":"From gateway"},
            {"value":"claude-fable-5-dd-los-1.6-tpg","name":"GPT 6.1 Sol","description":"From gateway"},
            {"value":"claude-fable-5-dd-5.1-egami-tpg","name":"GPT Image 1.5","description":"From gateway"},
            {"value":"claude-fable-5-dd-2-egami-tpg","name":"GPT Image 2","description":"From gateway"},
            {"value":"claude-fable-5-dd-5.2-egami-tpg","name":"GPT Image 2.5","description":"From gateway"},
            {"value":"claude-fable-5-dd-eralf-5.2-egami-tpg","name":"GPT Image 2.5 Flare","description":"From gateway"},
            {"value":"claude-fable-5-dd-tsrubnus-5.2-egami-tpg","name":"GPT Image 2.5 Sunburst","description":"From gateway"},
            {"value":"claude-fable-5-dd-1.4-tpg/tolipoc","name":"GPT-4.1","description":"From gateway"},
            {"value":"claude-fable-5-dd-41-40-5202-1.4-tpg/tolipoc","name":"GPT-4.1","description":"From gateway"},
            {"value":"claude-fable-5-dd-02-11-4202-o4-tpg/tolipoc","name":"GPT-4o","description":"From gateway"},
            {"value":"claude-fable-5-dd-31-50-4202-o4-tpg/tolipoc","name":"GPT-4o","description":"From gateway"},
            {"value":"claude-fable-5-dd-60-80-4202-o4-tpg/tolipoc","name":"GPT-4o","description":"From gateway"},
            {"value":"claude-fable-5-dd-o4-tpg/tolipoc","name":"GPT-4o","description":"From gateway"},
            {"value":"claude-fable-5-dd-weiverp-o-4-tpg/tolipoc","name":"GPT-4o","description":"From gateway"},
            {"value":"claude-fable-5-dd-81-70-4202-inim-o4-tpg/tolipoc","name":"GPT-4o mini","description":"From gateway"},
            {"value":"claude-fable-5-dd-inim-o4-tpg/tolipoc","name":"GPT-4o mini","description":"From gateway"},
            {"value":"claude-fable-5-dd-otua-eerf-inim-4.5-tpg/tolipoc","name":"GPT-5.4 mini","description":"From gateway"},
            {"value":"claude-fable-5-dd-onan-4.5-tpg/tolipoc","name":"GPT-5.4 nano","description":"From gateway"},
            {"value":"claude-fable-5-dd-anul-6.5-tpg/tolipoc","name":"GPT-5.6 Luna","description":"From gateway"},
            {"value":"claude-fable-5-dd-otua-eerf-anul-6.5-tpg/tolipoc","name":"GPT-5.6 Luna","description":"From gateway"},
            {"value":"claude-fable-5-dd-anul-6-tpg/tolipoc","name":"GPT-6 Luna","description":"From gateway"},
            {"value":"claude-fable-5-dd-esab-3k-imik/tolipoc","name":"Kimi K3 (GitHub)","description":"From gateway"},
            {"value":"claude-fable-5-dd-tolipoc-3k-imik/tolipoc","name":"Kimi K3 (GitHub)","description":"From gateway"},
            {"value":"claude-fable-5-dd-hsalf-1.1-edoc-iam/tolipoc","name":"MAI-Code-1.1-Flash","description":"From gateway"},
            {"value":"claude-fable-5-dd-ht4-hsalf-1-edoc-iam/tolipoc","name":"MAI-Code-1.1-Flash","description":"From gateway"},
            {"value":"claude-fable-5-dd-yradnoces-hsalf-1-edoc-iam/tolipoc","name":"MAI-Code-1.1-Flash","description":"From gateway"},
            {"value":"claude-fable-5-dd-yraitret-hsalf-1-edoc-iam/tolipoc","name":"MAI-Code-1.1-Flash","description":"From gateway"},
            {"value":"sonnet","name":"Sonnet 5.5","description":"Sonnet 5.5 · Efficient for routine tasks · $2/$10 per Mtok"},
            {"value":"haiku","name":"Haiku 5.5","description":"Haiku 5.5 · Fastest for quick answers · $0.10/$0.50 per Mtok ($0.50/$2.50 for prompts over 100k)"},
            {"value":"claude-3-5-haiku-20241022","name":"Claude 3.5 Haiku","description":"From gateway"},
            {"value":"claude-3-7-sonnet-20250219","name":"Claude 3.7 Sonnet","description":"From gateway"},
            {"value":"claude-sonnet-4-20250514","name":"Claude 4 Sonnet","description":"From gateway"},
            {"value":"claude-haiku-4-5-20251001","name":"Claude 4.5 Haiku","description":"From gateway"},
            {"value":"claude-opus-4-5-20251101","name":"Claude 4.5 Opus","description":"From gateway"},
            {"value":"claude-sonnet-4-5-20250929","name":"Claude 4.5 Sonnet","description":"From gateway"},
            {"value":"claude-opus-4-6","name":"Claude 4.6 Opus","description":"From gateway"},
            {"value":"claude-sonnet-4-6","name":"Claude 4.6 Sonnet","description":"From gateway"},
            {"value":"claude-opus-4-7","name":"Claude Opus 4.7","description":"From gateway"},
            {"value":"claude-opus-4-8","name":"Claude Opus 4.8","description":"From gateway"},
            {"value":"claude-opus-5","name":"Claude Opus 5","description":"From gateway"},
            {"value":"claude-sonnet-5","name":"Claude Sonnet 5","description":"From gateway"}
          ]},
          {"id":"effort","name":"Effort","description":"Available effort levels for this model","category":"thought_level","type":"select","currentValue":"xhigh","options":[
            {"value":"default","name":"Default"},
            {"value":"low","name":"Low"},
            {"value":"medium","name":"Medium"},
            {"value":"high","name":"High"},
            {"value":"xhigh","name":"Xhigh"},
            {"value":"max","name":"Max"}
          ]},
          {"id":"fast","name":"Fast mode","description":"Faster responses on supported models","category":"model_config","type":"select","currentValue":"off","options":[
            {"value":"on","name":"On"},
            {"value":"off","name":"Off"}
          ]}
        ]
        """#

    static func options() throws -> [ConfigOption] {
        try JSONDecoder().decode([ConfigOption].self, from: Data(configOptions.utf8))
    }
}
