import Foundation

/// Detects when a terminal agent is waiting for human input by scanning
/// the last few lines of terminal output for known prompt patterns.
struct PromptDetector {

    /// Known prompt patterns that indicate a tool is waiting for user input.
    /// Each pattern is matched against the last few non-empty lines of the
    /// terminal content. Matched line-by-line against the tail.
    private static let patterns: [(toolID: String?, regex: NSRegularExpression)] = {
        let defs: [(String?, String)] = [
            // ── Claude Code ────────────────────────────────────────────
            // Permission / approval prompt (e.g. "Allow tool_name? (y/n)")
            ("claude", #"(?i)\ballow\b.*\?\s*$"#),
            // "Do you want to proceed?" style
            ("claude", #"(?i)do you want to (proceed|continue)\??\s*$"#),
            // Tool use approval: "Allow" / "Deny" buttons rendered as text
            ("claude", #"(?i)^\s*\[?(allow|deny)\s+(this|all|once)"#),
            // Explicit "Yes / No" choice line
            ("claude", #"(?i)^\s*\(?\s*[Yy]es\s*/\s*[Nn]o\s*\)?"#),
            // "Type a message" or "Enter your message" idle prompt
            ("claude", #"(?i)(type|enter)\s+(a |your )?message"#),

            // ── Codex ──────────────────────────────────────────────────
            ("codex", #"(?i)\b(approve|deny|allow|reject)\b.*[\?\>:]\s*$"#),

            // ── OpenCode ───────────────────────────────────────────────
            ("opencode", #"(?i)\b(confirm|approve|allow|deny)\b.*[\?\>:]\s*$"#),

            // ── Generic patterns (any tool) ────────────────────────────
            // [y/n] or (y/n) prompts
            (nil, #"(?i)\[y/?n\]\s*:?\s*$"#),
            (nil, #"(?i)\(y/?n\)\s*:?\s*$"#),
            // "Press enter to continue"
            (nil, #"(?i)press enter to continue"#),
            // Explicit "waiting for input"
            (nil, #"(?i)waiting for (?:user |human )?input"#),
            // "Do you want to" generic
            (nil, #"(?i)do you want to\b.*\?\s*$"#),
        ]

        return defs.compactMap { toolID, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (toolID, regex)
        }
    }()

    /// Check whether the given terminal content indicates the tool is waiting
    /// for user input. Only the last few non-empty lines are scanned.
    ///
    /// - Parameters:
    ///   - content: The terminal text (last N lines from the session).
    ///   - toolID: The tool running in this session (for tool-specific patterns).
    /// - Returns: `true` if a prompt pattern was detected.
    static func detectsPrompt(in content: String, toolID: String) -> Bool {
        // Only look at the last 10 non-empty lines — prompts appear at the bottom.
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(10)

        // Check each line individually for better pattern matching.
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            for (patternToolID, regex) in patterns {
                if let patternToolID, patternToolID != toolID { continue }
                if regex.firstMatch(in: line, range: range) != nil {
                    return true
                }
            }
        }

        return false
    }
}
