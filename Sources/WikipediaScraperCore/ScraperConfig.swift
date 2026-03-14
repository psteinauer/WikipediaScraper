// ScraperConfig.swift — Load custom field mappings from .wikipediascraperrc

import Foundation

/// User-defined mappings loaded from a .wikipediascraperrc file.
///
/// Search order (first file found wins):
///   1. Path passed via --config
///   2. ./.wikipediascraperrc  (current working directory)
///   3. ~/.wikipediascraperrc  (home directory)
public struct ScraperConfig {

    /// infobox field name → FACT TYPE display name
    public var factMappings:  [String: String] = [:]

    /// infobox field name → EVEN TYPE display name
    public var eventMappings: [String: String] = [:]

    public static let empty = ScraperConfig()

    // MARK: - Loading

    /// Load config from an explicit path, or search default locations.
    /// Returns `.empty` if no file is found.
    public static func load(path: String? = nil, verbose: Bool = false) -> ScraperConfig {
        let candidates: [String]
        if let p = path {
            candidates = [p]
        } else {
#if os(macOS)
            let cwd  = FileManager.default.currentDirectoryPath
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            candidates = [
                (cwd  as NSString).appendingPathComponent(".wikipediascraperrc"),
                (home as NSString).appendingPathComponent(".wikipediascraperrc"),
            ]
#else
            // Config files are a CLI / macOS concept; iOS has no accessible home directory.
            candidates = []
#endif
        }

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate) else { continue }
            do {
                let config = try parseFile(at: candidate)
                if verbose {
                    let nF = config.factMappings.count
                    let nE = config.eventMappings.count
                    fputs("Config: \(candidate) (\(nF) fact, \(nE) event mapping(s))\n", stderr)
                }
                return config
            } catch {
                fputs("Warning: Could not read config \(candidate): \(error.localizedDescription)\n", stderr)
            }
        }
        return .empty
    }

    // MARK: - Parsing

    private static func parseFile(at path: String) throws -> ScraperConfig {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        var config  = ScraperConfig()
        var section: String? = nil

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // Skip blank lines and comments
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }

            // Section header: [facts] or [events]
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                continue
            }

            // key = value
            guard let eq = line.range(of: "=") else { continue }
            let key = String(line[line.startIndex..<eq.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            let value = String(line[eq.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            switch section {
            case "facts":  config.factMappings[key]  = value
            case "events": config.eventMappings[key] = value
            default: break   // unknown sections are silently ignored
            }
        }
        return config
    }
}
