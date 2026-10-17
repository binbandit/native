import Foundation

/// Renders bindings as compact TypeScript-style declarations for a model to write scripts against:
///
///     // Check a task's status and its latest reply without waiting.
///     tools.get_task(input: { task_id: string }): Promise<{ task_id: string; status: "running" | "idle" }>
///
/// A few lines per tool instead of a full JSON Schema each is most of what makes code mode cheap.
public enum ScriptReference {
    public static func declarations(for bindings: [ScriptBinding]) -> String {
        bindings.map(declaration).joined(separator: "\n")
    }

    public static func declaration(for binding: ScriptBinding) -> String {
        var lines: [String] = []
        if let summary = binding.summary.flatMap(firstSentence) {
            lines.append("// \(summary)")
        }
        let parameter = binding.inputSchema.flatMap { schema -> String? in
            guard let properties = schema["properties"], properties != [:] else { return nil }
            let optional = (schema["required"] ?? []) == [] ? "?" : ""
            return "input\(optional): \(type(of: schema, depth: 0))"
        }
        let result = binding.outputSchema.map { type(of: $0, depth: 0) } ?? "unknown"
        lines.append("\(binding.label)(\(parameter ?? "")): Promise<\(result)>")
        return lines.joined(separator: "\n")
    }

    /// Deep schemas are cut off: past a few levels a model learns more from one call's result.
    private static let maxDepth = 3

    static func type(of schema: ScriptJSON, depth: Int) -> String {
        if case .array(let values)? = schema["enum"] {
            return values.map(\.jsonText).joined(separator: " | ")
        }
        switch schema["type"] {
        case .string("string"): return "string"
        case .string("number"), .string("integer"): return "number"
        case .string("boolean"): return "boolean"
        case .string("null"): return "null"
        case .string("array"):
            let element = schema["items"].map { type(of: $0, depth: depth + 1) } ?? "unknown"
            return element.contains(" ") && !element.hasPrefix("{") ? "(\(element))[]" : "\(element)[]"
        case .string("object"):
            guard case .object(let properties)? = schema["properties"], !properties.isEmpty else {
                return "Record<string, unknown>"
            }
            guard depth < maxDepth else { return "{ … }" }
            let required: Set<String>
            if case .array(let names)? = schema["required"] {
                required = Set(names.compactMap(\.stringValue))
            } else {
                required = []
            }
            let fields = properties.keys.sorted().compactMap { name -> String? in
                guard let property = properties[name] else { return nil }
                let marker = required.contains(name) ? "" : "?"
                return "\(name)\(marker): \(type(of: property, depth: depth + 1))"
            }
            return "{ \(fields.joined(separator: "; ")) }"
        default:
            return "unknown"
        }
    }

    private static func firstSentence(_ text: String) -> String? {
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(
            in: .whitespaces)
        guard !flattened.isEmpty else { return nil }
        if let end = flattened.range(of: ". ") {
            return String(flattened[..<end.lowerBound]) + "."
        }
        return flattened
    }
}
