import MCP

/// Only the schema vocabulary used by OrchestrationTools. Unknown vocabulary is tested for drift.
public enum ToolInputValidation {
    public static func failures(_ value: JSON, schema: JSON, path: String = "arguments") -> [String] {
        var failures: [String] = []
        switch (schema["type"]?.stringValue, value) {
        case ("object", .object(let object)):
            let properties = schema["properties"]?.objectValue ?? [:]
            if case .array(let required) = schema["required"] {
                for key in required.compactMap(\.stringValue) where object[key] == nil {
                    failures.append("\(path).\(key) is required")
                }
            }
            for (key, child) in object {
                if let childSchema = properties[key] {
                    failures += self.failures(child, schema: childSchema, path: "\(path).\(key)")
                } else if schema["additionalProperties"] == .bool(false) {
                    failures.append("\(path).\(key) is not supported")
                }
            }
        case ("string", .string(let text)):
            if case .number(let maximum) = schema["maxLength"], Double(text.count) > maximum {
                failures.append("\(path) exceeds maximum length")
            }
        case ("boolean", .bool): break
        case ("integer", .number(let number)) where number.rounded() == number:
            if case .number(let minimum) = schema["minimum"], number < minimum {
                failures.append("\(path) is below minimum")
            }
            if case .number(let maximum) = schema["maximum"], number > maximum {
                failures.append("\(path) is above maximum")
            }
        default: failures.append("\(path) has wrong or unsupported type")
        }
        if case .array(let values) = schema["enum"], !values.contains(value) {
            failures.append("\(path) is not an allowed value")
        }
        return failures
    }
}
