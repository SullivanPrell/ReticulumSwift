import Foundation

// MARK: - SAM reply types

public enum SAMHelloResult: Equatable {
    case ok(String)         // associated: SAM version string
    case failure(String)    // associated: RESULT= value
}

public enum SAMSessionResult: Equatable {
    case ok(String)         // associated: base64-encoded I2P destination
    case failure(String)
}

public enum SAMStreamResult: Equatable {
    case ok
    case failure(String)
}

public enum SAMNamingResult: Equatable {
    case ok(String)         // associated: base64-encoded I2P destination (VALUE=)
    case failure(String)
}

// MARK: - SAMClient (line formatting + response parsing)

/// SAM 3.1 protocol helpers.
///
/// The Simple Anonymous Messaging (SAM) protocol is a text-based protocol
/// used to create I2P tunnels through a running i2pd daemon.
///
/// Wire flow (client-side tunnel setup):
///   1. TCP connect to SAM host:port
///   2. → `HELLO VERSION MIN=3.1 MAX=3.1\n`
///   3. ← `HELLO REPLY RESULT=OK VERSION=3.1\n`
///   4. → `SESSION CREATE STYLE=STREAM ID=<id> DESTINATION=TRANSIENT\n`
///   5. ← `SESSION STATUS RESULT=OK DESTINATION=<base64-dest>\n`
///   6. (new TCP conn) → `HELLO VERSION MIN=3.1 MAX=3.1\n` + handshake
///   7. → `STREAM CONNECT ID=<id> DESTINATION=<target.b32.i2p> SILENCE=false\n`
///   8. ← `STREAM STATUS RESULT=OK\n`
///   9. TCP conn is now a raw data channel.
public enum SAMClient {

    // MARK: - Outgoing line builders

    /// SAM 3.1 hello handshake line.
    public static let helloLine = "HELLO VERSION MIN=3.1 MAX=3.1\n"

    /// Session-creation request.
    /// `TRANSIENT` destination lets i2pd generate a fresh keypair each run.
    public static func sessionCreateLine(sessionID: String) -> String {
        "SESSION CREATE STYLE=STREAM ID=\(sessionID) DESTINATION=TRANSIENT\n"
    }

    /// Outbound (client) tunnel connect request.
    /// i2plib: `STREAM CONNECT ID={} DESTINATION={} SILENT={}\n`
    public static func streamConnectLine(sessionID: String,
                                         destination: String) -> String {
        "STREAM CONNECT ID=\(sessionID) DESTINATION=\(destination) SILENT=false\n"
    }

    /// Inbound (server) accept request.
    /// i2plib: `STREAM ACCEPT ID={} SILENT={}\n`
    public static func streamAcceptLine(sessionID: String) -> String {
        "STREAM ACCEPT ID=\(sessionID) SILENT=false\n"
    }

    /// Resolve a `.i2p` / `.b32.i2p` name to a full base64 destination.
    /// i2plib: `NAMING LOOKUP NAME={}\n`
    public static func namingLookupLine(name: String) -> String {
        "NAMING LOOKUP NAME=\(name)\n"
    }

    /// Unique session nickname for `SESSION CREATE`. A fresh ID per dial
    /// attempt avoids `DUPLICATED_ID` while i2pd reaps a dead session.
    public static func randomSessionID() -> String {
        "reticulum-" + Hashes.randomHash().prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Response parsers

    /// Parse `HELLO REPLY …`
    public static func parseHelloReply(_ line: String) -> SAMHelloResult {
        guard let result = extractValue(for: "RESULT", in: line) else {
            return .failure("missing RESULT")
        }
        guard result == "OK" else {
            return .failure(result)
        }
        let version = extractValue(for: "VERSION", in: line) ?? "unknown"
        return .ok(version)
    }

    /// Parse `SESSION STATUS …`
    public static func parseSessionStatus(_ line: String) -> SAMSessionResult {
        guard let result = extractValue(for: "RESULT", in: line) else {
            return .failure("missing RESULT")
        }
        guard result == "OK" else {
            return .failure(result)
        }
        let dest = extractValue(for: "DESTINATION", in: line) ?? ""
        return .ok(dest)
    }

    /// Parse `STREAM STATUS …`
    public static func parseStreamStatus(_ line: String) -> SAMStreamResult {
        guard let result = extractValue(for: "RESULT", in: line) else {
            return .failure("missing RESULT")
        }
        return result == "OK" ? .ok : .failure(result)
    }

    /// Parse `NAMING REPLY …` — the resolved destination is in `VALUE=`.
    public static func parseNamingReply(_ line: String) -> SAMNamingResult {
        guard let result = extractValue(for: "RESULT", in: line) else {
            return .failure("missing RESULT")
        }
        guard result == "OK", let value = extractValue(for: "VALUE", in: line) else {
            return .failure(result)
        }
        return .ok(value)
    }

    // MARK: - Key=Value extractor

    /// Extract a `KEY=VALUE` pair from a SAM reply line.
    /// Handles unquoted values that end at the next space or newline.
    public static func extractValue(for key: String, in line: String) -> String? {
        let prefix = key + "="
        guard let range = line.range(of: prefix) else { return nil }
        let rest  = String(line[range.upperBound...])
        // Value ends at first space or newline
        if let spaceIdx = rest.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\r" }) {
            return String(rest[..<spaceIdx])
        }
        return rest.isEmpty ? nil : rest
    }
}
