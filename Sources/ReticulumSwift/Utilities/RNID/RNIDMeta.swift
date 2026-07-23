import Foundation

/// The `-E`/`--embed-meta` metadata parser: a minimal, ordered ConfigObj equivalent.
///
/// Python reference: `rsg_meta_from_file(path, spec_path)` (rnid.py:566-575) and
/// `rsg_meta_from_str(meta, spec)` (rnid.py:577-586), both of which parse with RNS's
/// vendored `ConfigObj`, optionally validate against a `configspec` with `Validator()`, and
/// return `parsed.dict()`.
///
/// `ReticulumConfig.parse` cannot be reused: it returns a fixed struct
/// (`ReticulumSection` / `LoggingSection` / `[InterfaceConfig]`) and cannot represent
/// arbitrary user metadata, let alone preserve the file order that `create_rsg` depends on
/// when merging into the envelope's `meta` map.
///
/// Semantics reproduced (all confirmed against RNS's vendored ConfigObj):
/// - `key = value` → a string
/// - `key = a, b, c` → a list of strings
/// - `key =` → the empty string
/// - `[section]` / `[[subsection]]` → nested, order-preserving maps
/// - with a spec, values are coerced (`port = integer` turns `"4242"` into `4242`) while
///   unspecced siblings stay strings
///
/// Full `Validator` parity (every check type, `min`/`max` constraints) is out of scope; an
/// unrecognised check raises ``MetaError/unsupportedCheck(_:)`` rather than being silently
/// accepted.
public enum RNIDMeta {

    public enum MetaError: Error, Equatable, CustomStringConvertible {
        /// Python: `ValueError("Metadata did not pass spec validation")`.
        case specValidationFailed
        /// No Python equivalent — Python's Validator supports far more checks than this port.
        case unsupportedCheck(String)

        public var description: String {
            switch self {
            case .specValidationFailed:      return "Metadata did not pass spec validation"
            case .unsupportedCheck(let name): return "Unsupported metadata spec check: \(name)"
            }
        }
    }

    // MARK: - Parsing

    /// Parse ConfigObj-shaped text into ordered entries, with every scalar left as a string.
    public static func parse(_ text: String) -> [(String, MsgPack.Value)] {
        let root = Node()
        // `stack[level]` is the node new keys at that nesting depth are inserted into.
        var stack: [Node] = [root]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                let depth = line.prefix(while: { $0 == "[" }).count
                let name = line
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    .trimmingCharacters(in: .whitespaces)
                // A [[sub]] under nothing is malformed; ConfigObj errors, we clamp.
                let parentIndex = min(depth - 1, stack.count - 1)
                stack = Array(stack.prefix(parentIndex + 1))
                let child = Node()
                stack[parentIndex].append(key: name, node: child)
                stack.append(child)
                continue
            }

            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[line.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            stack[stack.count - 1].append(key: key, value: scalar(rawValue))
        }

        return root.entries()
    }

    /// Parse with an optional ConfigObj spec, coercing values the way `Validator` does.
    /// Python: `parsed.validate(Validator())` must return exactly `True`.
    public static func parse(_ text: String, spec: String?) throws -> [(String, MsgPack.Value)] {
        let parsed = parse(text)
        guard let spec else { return parsed }
        return try coerce(parsed, spec: parse(spec))
    }

    // MARK: - Scalar handling

    /// ConfigObj: an unquoted comma-separated value becomes a list; quotes are stripped.
    private static func scalar(_ raw: String) -> MsgPack.Value {
        if raw.contains(",") {
            let items = raw.split(separator: ",", omittingEmptySubsequences: false)
                .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
            return .array(items.map { MsgPack.Value.string($0) })
        }
        return .string(unquote(raw))
    }

    private static func unquote(_ value: String) -> String {
        if value.count >= 2 {
            if value.hasPrefix("\"") && value.hasSuffix("\"") { return String(value.dropFirst().dropLast()) }
            if value.hasPrefix("'") && value.hasSuffix("'") { return String(value.dropFirst().dropLast()) }
        }
        return value
    }

    // MARK: - Spec coercion

    private static func coerce(
        _ entries: [(String, MsgPack.Value)],
        spec: [(String, MsgPack.Value)]
    ) throws -> [(String, MsgPack.Value)] {
        var result: [(String, MsgPack.Value)] = []
        for (key, value) in entries {
            guard let rule = spec.first(where: { $0.0 == key })?.1 else {
                result.append((key, value))
                continue
            }
            switch (value, rule) {
            case (.map(let childPairs), .map(let specPairs)):
                let childEntries = childPairs.compactMap { pair -> (String, MsgPack.Value)? in
                    guard case .string(let name) = pair.0 else { return nil }
                    return (name, pair.1)
                }
                let specEntries = specPairs.compactMap { pair -> (String, MsgPack.Value)? in
                    guard case .string(let name) = pair.0 else { return nil }
                    return (name, pair.1)
                }
                let coerced = try coerce(childEntries, spec: specEntries)
                result.append((key, .map(coerced.map { (MsgPack.Value.string($0.0), $0.1) })))
            default:
                // The rule text is itself a ConfigObj scalar, e.g. `integer` or
                // `integer(default=4242)`; a list-valued rule cannot be a check.
                guard let ruleText = rule.asString else { throw MetaError.specValidationFailed }
                result.append((key, try apply(check: ruleText, to: value)))
            }
        }
        return result
    }

    private static func apply(check rawCheck: String, to value: MsgPack.Value) throws -> MsgPack.Value {
        // Strip any argument list: `integer(default=4242)` → `integer`.
        let name = String(rawCheck.prefix(while: { $0 != "(" })).trimmingCharacters(in: .whitespaces)

        switch name {
        case "string", "":
            return value
        case "integer":
            guard let text = value.asString, let number = Int64(text) else {
                throw MetaError.specValidationFailed
            }
            return .int(number)
        case "float":
            guard let text = value.asString, let number = Double(text) else {
                throw MetaError.specValidationFailed
            }
            return .double(number)
        case "boolean", "bool":
            guard let text = value.asString?.lowercased() else { throw MetaError.specValidationFailed }
            switch text {
            case "yes", "true", "1", "on":  return .bool(true)
            case "no", "false", "0", "off": return .bool(false)
            default: throw MetaError.specValidationFailed
            }
        case "list", "string_list":
            switch value {
            case .array:            return value
            case .string(let text): return .array([.string(text)])
            default:                throw MetaError.specValidationFailed
            }
        case "int_list":
            let items: [String]
            switch value {
            case .array(let values): items = values.compactMap { $0.asString }
            case .string(let text):  items = [text]
            default: throw MetaError.specValidationFailed
            }
            var converted: [MsgPack.Value] = []
            for item in items {
                guard let number = Int64(item) else { throw MetaError.specValidationFailed }
                converted.append(.int(number))
            }
            return .array(converted)
        case "option":
            // `option("a", "b")` — the raw value must be one of the listed alternatives.
            guard let text = value.asString else { throw MetaError.specValidationFailed }
            let inside = rawCheck.drop(while: { $0 != "(" }).dropFirst().dropLast()
            let allowed = inside.split(separator: ",").map {
                unquote($0.trimmingCharacters(in: .whitespaces))
            }
            guard allowed.contains(text) else { throw MetaError.specValidationFailed }
            return value
        default:
            throw MetaError.unsupportedCheck(name)
        }
    }

    // MARK: - Ordered tree

    /// A mutable, insertion-ordered node used while parsing.
    private final class Node {
        private enum Slot {
            case value(MsgPack.Value)
            case node(Node)
        }
        private var slots: [(String, Slot)] = []

        func append(key: String, value: MsgPack.Value) { slots.append((key, .value(value))) }
        func append(key: String, node: Node) { slots.append((key, .node(node))) }

        func entries() -> [(String, MsgPack.Value)] {
            slots.map { key, slot in
                switch slot {
                case .value(let value): return (key, value)
                case .node(let node):
                    return (key, .map(node.entries().map { (MsgPack.Value.string($0.0), $0.1) }))
                }
            }
        }
    }
}
