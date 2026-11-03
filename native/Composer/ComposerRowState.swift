import SwiftUI

/// Presentation values only. The adapter routes choices through the existing task models.
struct ComposerRowState {
    struct Choice: Identifiable, Equatable {
        let id: String
        let title: String
        var detail: String = ""
        var isSelected = false
        var unavailable: String?
    }

    struct Agent: Identifiable, Equatable {
        let id: String
        let name: String
        var models: [Choice]
        var settings: [SelectSetting] = []
    }

    var agentLabel = "Choose agent and model"
    var agents: [Agent] = []
    var effort: [Choice] = []
    var modes: [Choice] = []
    var modeLabel = "Full access"
    var isDefaultMode = true
    var defaultModeID: String?
    /// Empty for an existing task. A reserved slot keeps the other controls in place.
    var locations: [Choice] = []
    var locationLabel = "In my folder"
    var contextFraction: Double?
    var isWorking = false
    var isStopping = false
    var disabledReason: String?
    var selectionNotice: String?
    var canChoose = true
}

struct ComposerRowActions {
    var chooseModel: (String) -> Void = { _ in }
    var chooseEffort: (String) -> Void = { _ in }
    var chooseSetting: (String, String) -> Void = { _, _ in }
    var chooseMode: (String) -> Void = { _ in }
    var chooseLocation: (String) -> Void = { _ in }
    var attach: () -> Void = {}
    var context: () -> Void = {}
    var send: () -> Void = {}
    var stop: () -> Void = {}
}
