import Foundation

public enum MarkdownV2Escaper {
    private static let specials: Set<Character> = [
        "_", "*", "[", "]", "(", ")", "~", "`", ">", "#",
        "+", "-", "=", "|", "{", "}", ".", "!", "\\"
    ]

    public static func escape(_ input: String) -> String {
        var out = String()
        out.reserveCapacity(input.count)
        for ch in input {
            if specials.contains(ch) {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    /// Escaping for text placed inside a fenced/inline code entity. Per the
    /// Telegram docs, inside `pre`/`code` only `` ` `` and `\` are special; the
    /// rest of the reserved set is literal, so numbers and punctuation pass
    /// through unescaped.
    public static func escapeCodeContent(_ input: String) -> String {
        var out = String()
        out.reserveCapacity(input.count)
        for ch in input {
            if ch == "`" || ch == "\\" {
                out.append("\\")
            }
            out.append(ch)
        }
        return out
    }

    private static let fenceMarker = "```"

    public static func chunk(_ input: String, limit: Int) -> [String] {
        guard !input.isEmpty else { return [] }
        let effectiveLimit = max(2, limit)
        if input.count <= effectiveLimit { return [input] }
        if input.contains(fenceMarker) {
            return chunkFenceAware(input, limit: effectiveLimit)
        }
        return chunkPlain(input, limit: effectiveLimit)
    }

    private static func chunkPlain(_ input: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var remaining = Substring(input)

        while remaining.count > limit {
            let window = remaining.prefix(limit)
            let splitIndex = ensuringProgress(findSplitIndex(in: window, insideFence: false), in: remaining)
            chunks.append(String(remaining[..<splitIndex]))
            remaining = remaining[splitIndex...]
        }

        if !remaining.isEmpty {
            chunks.append(String(remaining))
        }
        return chunks
    }

    /// Splitting a message that contains fenced code blocks must keep every
    /// chunk independently parseable: an unbalanced ``` makes Telegram reject
    /// the chunk with 400 "can't parse entities". A chunk that ends inside a
    /// fence gets a synthetic closing fence, and the next chunk re-opens it so
    /// the continuation still renders monospace. The synthetic fence characters
    /// are budgeted inside `limit`.
    private static func chunkFenceAware(_ input: String, limit: Int) -> [String] {
        let reopen = fenceMarker + "\n"
        let closeReserve = fenceMarker.count + 1

        var chunks: [String] = []
        var remaining = Substring(input)
        var insideFence = false

        while !remaining.isEmpty {
            let prefix = insideFence ? reopen : ""
            let endsInsideIfWhole = fenceState(after: remaining, startingInside: insideFence)
            let wholeCost = prefix.count + remaining.count + (endsInsideIfWhole ? closeReserve : 0)
            if wholeCost <= limit {
                var piece = prefix + remaining
                if endsInsideIfWhole { piece = appendingFenceClose(to: piece) }
                chunks.append(piece)
                break
            }

            let budget = max(1, limit - prefix.count - closeReserve)
            let window = remaining.prefix(budget)
            let splitIndex = ensuringProgress(findSplitIndex(in: window, insideFence: insideFence), in: remaining)
            let head = remaining[..<splitIndex]
            let headEndsInside = fenceState(after: head, startingInside: insideFence)

            var piece = prefix + head
            if headEndsInside { piece = appendingFenceClose(to: piece) }
            chunks.append(piece)

            insideFence = headEndsInside
            remaining = remaining[splitIndex...]
        }
        return chunks
    }

    private static func ensuringProgress(_ index: Substring.Index, in remaining: Substring) -> Substring.Index {
        index == remaining.startIndex ? remaining.index(after: remaining.startIndex) : index
    }

    private static func appendingFenceClose(to piece: String) -> String {
        piece.hasSuffix("\n") ? piece + fenceMarker : piece + "\n" + fenceMarker
    }

    private static func fenceState(after text: Substring, startingInside: Bool) -> Bool {
        var inside = startingInside
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix(fenceMarker) {
            inside.toggle()
        }
        return inside
    }

    private static func findSplitIndex(in window: Substring, insideFence: Bool) -> Substring.Index {
        if let r = window.range(of: "\n\n", options: .backwards) {
            return avoidingEscapeBoundary(in: window, at: r.upperBound)
        }
        if let r = window.range(of: "\n", options: .backwards) {
            return avoidingEscapeBoundary(in: window, at: r.upperBound)
        }
        let hardCut = avoidingEscapeBoundary(in: window, at: window.endIndex)
        return avoidingInlineEntities(in: window, at: hardCut, insideFence: insideFence)
    }

    /// A hard cut mid-line can land inside a `*bold*`/`_italic_`/`` `code` ``
    /// span, leaving an unclosed entity Telegram rejects. Back the cut off to
    /// just before the earliest unmatched opener on the current line. Inside a
    /// fence every character is literal, so no backoff applies there.
    private static func avoidingInlineEntities(
        in window: Substring,
        at index: Substring.Index,
        insideFence: Bool
    ) -> Substring.Index {
        guard !insideFence else { return index }
        let entityCharacters: Set<Character> = ["*", "_", "`"]
        let line = window[..<index]
        let lineStart = line.range(of: "\n", options: .backwards)?.upperBound ?? window.startIndex

        var lastUnmatchedOpener: [Character: Substring.Index] = [:]
        var counts: [Character: Int] = [:]
        var cursor = lineStart
        var escaped = false
        while cursor < index {
            let ch = window[cursor]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if entityCharacters.contains(ch) {
                counts[ch, default: 0] += 1
                lastUnmatchedOpener[ch] = cursor
            }
            cursor = window.index(after: cursor)
        }

        let unmatched = counts
            .filter { !$0.value.isMultiple(of: 2) }
            .compactMap { lastUnmatchedOpener[$0.key] }
        guard let earliest = unmatched.min(), earliest > window.startIndex else { return index }
        return earliest
    }

    private static func avoidingEscapeBoundary(in window: Substring, at index: Substring.Index) -> Substring.Index {
        var trailingBackslashes = 0
        var cursor = index
        while cursor > window.startIndex {
            let prev = window.index(before: cursor)
            if window[prev] == "\\" {
                trailingBackslashes += 1
                cursor = prev
            } else {
                break
            }
        }
        if trailingBackslashes.isMultiple(of: 2) {
            return index
        }
        return window.index(before: index)
    }
}
