import Foundation

/// Local address book mapping human-readable labels to Destination hashes.
/// Reticulum has no DNS — this is just a keyring.
public final class Resolver {
    public struct Entry: Sendable, Equatable, Codable {
        public let label: String
        public let destinationHash: Data
        public init(label: String, destinationHash: Data) {
            self.label = label
            self.destinationHash = destinationHash
        }
    }

    public private(set) var entries: [Entry]
    public init(entries: [Entry] = []) { self.entries = entries }

    public func add(_ entry: Entry) { entries.append(entry) }

    public func resolve(label: String) -> Entry? {
        entries.first { $0.label == label }
    }

    public func resolve(hash: Data) -> Entry? {
        entries.first { $0.destinationHash == hash }
    }

    public func remove(label: String) {
        entries.removeAll { $0.label == label }
    }

    public func write(toFile url: URL) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: .atomic)
    }

    public static func read(fromFile url: URL) throws -> Resolver {
        let data = try Data(contentsOf: url)
        return Resolver(entries: try JSONDecoder().decode([Entry].self, from: data))
    }
}
