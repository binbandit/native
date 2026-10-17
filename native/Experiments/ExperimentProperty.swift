import Experiments
import SwiftUI

/// Reads a gate or a parameter in a view. The view updates when Labs changes the value, unless the
/// experiment needs a relaunch.
///
///     @Experiment(.unfoldExploration) private var unfoldsExploration
///     @Experiment(.transcriptWidth) private var width: TranscriptWidth
@propertyWrapper
struct Experiment<Value>: DynamicProperty {
    @Environment(\.experimentStore) private var store
    private let read: @MainActor (ExperimentStore) -> Value

    init(_ gate: Gate) where Value == Bool {
        read = { $0.value(of: gate) }
    }

    init(_ parameter: Parameter<Value>) where Value: ParameterValue {
        read = { $0.value(of: parameter) }
    }

    var wrappedValue: Value {
        read(store ?? .shared)
    }
}

/// Resolves an extension point in a view: the default implementation, or the one an experiment
/// that's on contributes.
///
///     @Resolved(.transcriptStyle) private var style: any TranscriptStyle
@propertyWrapper
struct Resolved<Contract: Sendable>: DynamicProperty {
    @Environment(\.experimentStore) private var store
    private let point: ExtensionPoint<Contract>

    init(_ point: ExtensionPoint<Contract>) {
        self.point = point
    }

    var wrappedValue: Contract {
        (store ?? .shared).implementation(of: point)
    }
}

extension EnvironmentValues {
    /// Replaces the app's experiment store below this point, for previews. Nil uses `.shared`.
    @Entry var experimentStore: ExperimentStore?
}
