import Foundation

/// Comment-preserving colima.yaml reader/writer.
///
/// Uses line-based navigation rather than a single mega-regex, so nested
/// sections (kubernetes.version, docker.log-opts.max-size, network.dns)
/// resolve correctly regardless of intervening sibling keys.
struct ColimaConfig {
    let path: String
    var raw: String

    init(path: String = AppPaths.colimaConfig) throws {
        self.path = path
        self.raw = try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Construct from an already-loaded raw string (no file read).
    init(path: String, raw: String) {
        self.path = path
        self.raw = raw
    }

    // MARK: - Line model

    private struct Line {
        let range: Range<String.Index>   // excluding trailing newline
        let end: String.Index            // position after this line's newline (start of next)
        let indent: Substring
        let body: Substring
    }

    private func lines(in region: Range<String.Index>) -> [Line] {
        var out: [Line] = []
        var pos = region.lowerBound
        while pos < region.upperBound {
            let slice = raw[pos..<region.upperBound]
            let nlIdx = slice.firstIndex(of: "\n")
            let lineEnd = nlIdx ?? region.upperBound
            let lineRange = pos..<lineEnd
            let next: String.Index
            if let n = nlIdx { next = raw.index(after: n) } else { next = lineEnd }
            let s = raw[lineRange]
            var sp = s.startIndex
            while sp < s.endIndex, s[sp] == " " || s[sp] == "\t" {
                sp = raw.index(after: sp)
            }
            out.append(Line(
                range: lineRange,
                end: next,
                indent: s[s.startIndex..<sp],
                body: s[sp..<s.endIndex]
            ))
            pos = next
        }
        return out
    }

    private static func depth(_ indent: Substring) -> Int { indent.count }

    // Body matches a header with no value: "key:" optionally trailing spaces.
    private func isHeader(_ body: Substring, key: String) -> Bool {
        guard body.hasPrefix("\(key):") else { return false }
        let after = body.dropFirst(key.count + 1)
        return after.allSatisfy { $0 == " " || $0 == "\t" }
    }

    // Body matches "key: value" (value non-empty). Returns trimmed value (quotes stripped).
    private func valueMatch(_ body: Substring, key: String) -> String? {
        guard body.hasPrefix("\(key):") else { return nil }
        var v = body.dropFirst(key.count + 1)
        v = v.drop(while: { $0 == " " || $0 == "\t" })
        guard !v.isEmpty else { return nil }
        var s = String(v).trimmingCharacters(in: .whitespaces)
        if s.count >= 2, s.first == "\"", s.last == "\"" { s = String(s.dropFirst().dropLast()) }
        return s
    }

    // Contiguous block of lines strictly deeper than `header`, immediately following it.
    private func blockFollowing(_ header: Line, in region: Range<String.Index>) -> Range<String.Index> {
        let hd = Self.depth(header.indent)
        var lo: String.Index? = nil
        var hi = header.end
        for ln in lines(in: region) where ln.range.lowerBound >= header.end {
            if Self.depth(ln.indent) > hd || ln.body.isEmpty {
                if lo == nil { lo = ln.range.lowerBound }
                hi = ln.end
            } else {
                break
            }
        }
        return (lo ?? hi)..<hi
    }

    // MARK: - Navigation

    // Navigate to the line holding `path.last` as a value/header within nested sections.
    private func locate(_ path: [String], headerLeaf: Bool) -> Line? {
        guard let last = path.last else { return nil }
        let full = raw.startIndex..<raw.endIndex
        var region = full
        var parentDepth = -1
        for seg in path.dropLast() {
            let hdr = lines(in: region).first { Self.depth($0.indent) > parentDepth && isHeader($0.body, key: seg) }
            guard let h = hdr else { return nil }
            parentDepth = Self.depth(h.indent)
            region = blockFollowing(h, in: region)
        }
        if headerLeaf {
            return lines(in: region).first { Self.depth($0.indent) > parentDepth && isHeader($0.body, key: last) }
        } else {
            return lines(in: region).first { Self.depth($0.indent) > parentDepth && valueMatch($0.body, key: last) != nil }
        }
    }

    // MARK: - Top-level scalars

    func scalar(_ key: String) -> String? {
        for ln in lines(in: raw.startIndex..<raw.endIndex) where Self.depth(ln.indent) == 0 {
            if let v = valueMatch(ln.body, key: key) { return v }
        }
        return nil
    }
    func boolValue(_ key: String) -> Bool { scalar(key)?.lowercased() == "true" }
    func intValue(_ key: String) -> Int? { scalar(key).flatMap(Int.init) }

    // MARK: - Nested scalars / bools (any depth)

    func nestedScalar(_ dotted: String) -> String? {
        let path = dotted.split(separator: ".").map(String.init)
        guard path.count >= 2, let ln = locate(path, headerLeaf: false) else { return nil }
        return valueMatch(ln.body, key: path.last!)
    }
    func nestedBool(_ dotted: String) -> Bool { nestedScalar(dotted)?.lowercased() == "true" }

    // MARK: - Nested list (e.g. "network.dns")

    func nestedList(_ dotted: String) -> [String] {
        let path = dotted.split(separator: ".").map(String.init)
        guard path.count >= 2, let header = locate(path, headerLeaf: true) else { return [] }
        let region = raw.startIndex..<raw.endIndex
        let block = blockFollowing(header, in: region)
        var items: [String] = []
        for ln in lines(in: block) {
            var b = ln.body
            if b.hasPrefix("- ") { b = b.dropFirst(2) }
            else if b.hasPrefix("-") { b = b.dropFirst() }
            else { continue }
            let s = String(b).trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            var v = s
            if v.count >= 2, v.first == "\"", v.last == "\"" { v = String(v.dropFirst().dropLast()) }
            items.append(v)
        }
        return items
    }

    // MARK: - Setters (manual range replacement — no regex template, safe for $ and \)

    mutating func setScalar(_ key: String, _ value: String) {
        guard let ln = locate([key], headerLeaf: false) else { return }
        let newLine = "\(ln.indent)\(key): \(value)"
        raw.replaceSubrange(ln.range, with: newLine)
    }
    mutating func setInt(_ key: String, _ value: Int) { setScalar(key, "\(value)") }
    mutating func setBool(_ key: String, _ value: Bool) { setScalar(key, "\(value)") }

    mutating func setNestedScalar(_ dotted: String, _ value: String) {
        let path = dotted.split(separator: ".").map(String.init)
        guard path.count >= 2, let ln = locate(path, headerLeaf: false) else { return }
        let key = path.last!
        // Docker log-opts expects all values as strings; quote numeric values.
        // Ref: docs.docker.com/engine/logging/configure/ — "log-opts must be
        // provided as strings. Numeric values must be enclosed in quotes."
        let needsQuotes = dotted.hasPrefix("docker.") && Double(value) != nil
        let formatted = needsQuotes ? "\"\(value)\"" : value
        let newLine = "\(ln.indent)\(key): \(formatted)"
        raw.replaceSubrange(ln.range, with: newLine)
    }
    mutating func setNestedBool(_ dotted: String, _ value: Bool) { setNestedScalar(dotted, "\(value)") }

    mutating func setNestedList(_ dotted: String, _ items: [String]) {
        let path = dotted.split(separator: ".").map(String.init)
        guard path.count >= 2, let header = locate(path, headerLeaf: true) else { return }
        let region = raw.startIndex..<raw.endIndex
        let block = blockFollowing(header, in: region)
        let hd = Self.depth(header.indent)
        let childIndent = String(repeating: " ", count: hd + 2)
        let newBlock = items.map { "\(childIndent)- \($0)\n" }.joined()
        let blockLines = lines(in: block)

        // Find contiguous dash block: first dash line through last consecutive dash.
        var dashStart: Line?
        var dashEnd: Line?
        for ln in blockLines {
            if ln.body.hasPrefix("-") {
                if dashStart == nil { dashStart = ln }
                dashEnd = ln
            } else if !ln.body.isEmpty {
                // Non-dash, non-blank line breaks the dash block.
                if dashStart != nil { break }
            }
            // Blank lines between dashes are tolerated.
        }

        if let first = dashStart, let last = dashEnd {
            let replaceRange = first.range.lowerBound..<last.end
            if newBlock.isEmpty {
                raw.replaceSubrange(replaceRange, with: "")
            } else {
                raw.replaceSubrange(replaceRange, with: newBlock)
            }
        } else if !newBlock.isEmpty {
            // No existing dash block — insert right after header.
            raw.insert(contentsOf: newBlock, at: header.end)
        }
    }

    // MARK: - Save

    func save() throws {
        try raw.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
