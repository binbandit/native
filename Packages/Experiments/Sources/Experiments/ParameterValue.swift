/// A type a `Parameter` can hold: it round-trips through a `StoredValue`.
public protocol ParameterValue: Sendable, Hashable {
    /// Nil when the stored value isn't one of this type's.
    init?(stored: StoredValue)
    var stored: StoredValue { get }
}

/// A parameter that's one of a fixed set of named choices, like a transcript width.
public protocol ParameterChoice: ParameterValue, CaseIterable, RawRepresentable<String> {
    /// How Labs names the choice.
    var title: String { get }
}

extension ParameterChoice {
    public init?(stored: StoredValue) {
        guard case .string(let rawValue) = stored else { return nil }
        self.init(rawValue: rawValue)
    }

    public var stored: StoredValue { .string(rawValue) }
}

extension Bool: ParameterValue {
    public init?(stored: StoredValue) {
        guard case .bool(let value) = stored else { return nil }
        self = value
    }

    public var stored: StoredValue { .bool(self) }
}

extension Int: ParameterValue {
    public init?(stored: StoredValue) {
        guard case .int(let value) = stored else { return nil }
        self = value
    }

    public var stored: StoredValue { .int(self) }
}

extension Double: ParameterValue {
    public init?(stored: StoredValue) {
        guard case .double(let value) = stored else { return nil }
        self = value
    }

    public var stored: StoredValue { .double(self) }
}

extension String: ParameterValue {
    public init?(stored: StoredValue) {
        guard case .string(let value) = stored else { return nil }
        self = value
    }

    public var stored: StoredValue { .string(self) }
}
