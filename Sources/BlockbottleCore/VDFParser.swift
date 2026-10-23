import Foundation

/// A value in Valve's KeyValues ("VDF") text format.
public indirect enum VDFValue: Equatable, Sendable {
    case string(String)
    case object([String: VDFValue])

    /// Case-insensitive key lookup (Valve files are inconsistent about case).
    public subscript(key: String) -> VDFValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key.lowercased()]
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var objectValue: [String: VDFValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

public enum VDFError: Error, Equatable {
    case unexpectedEnd
    case unexpectedToken(String)
}

/// Parses KeyValues text such as `appmanifest_*.acf` and `libraryfolders.vdf`.
/// Keys are stored lowercased.
public enum VDFParser {
    public static func parse(_ text: String) throws -> [String: VDFValue] {
        var tokens = Tokenizer(text)
        return try parseObject(&tokens, topLevel: true)
    }

    private static func parseObject(_ tokens: inout Tokenizer, topLevel: Bool) throws -> [String: VDFValue] {
        var result: [String: VDFValue] = [:]
        while let token = try tokens.next() {
            switch token {
            case .close:
                if topLevel { throw VDFError.unexpectedToken("}") }
                return result
            case .open:
                throw VDFError.unexpectedToken("{")
            case .string(let key):
                guard let valueToken = try tokens.next() else { throw VDFError.unexpectedEnd }
                switch valueToken {
                case .string(let v): result[key.lowercased()] = .string(v)
                case .open: result[key.lowercased()] = .object(try parseObject(&tokens, topLevel: false))
                case .close: throw VDFError.unexpectedToken("}")
                }
            }
        }
        if !topLevel { throw VDFError.unexpectedEnd }
        return result
    }

    private enum Token { case string(String), open, close }

    private struct Tokenizer {
        let chars: [Character]
        var i = 0
        init(_ text: String) { chars = Array(text) }

        mutating func next() throws -> Token? {
            skipTrivia()
            guard i < chars.count else { return nil }
            let c = chars[i]
            switch c {
            case "{": i += 1; return .open
            case "}": i += 1; return .close
            case "\"": i += 1; return .string(try quoted())
            default: return .string(bare())
            }
        }

        mutating func skipTrivia() {
            while i < chars.count {
                if chars[i].isWhitespace { i += 1; continue }
                if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, !chars[i].isNewline { i += 1 }
                    continue
                }
                // Conditionals like [$WIN32] are ignored.
                if chars[i] == "[" {
                    while i < chars.count, chars[i] != "]" { i += 1 }
                    i += 1
                    continue
                }
                break
            }
        }

        mutating func quoted() throws -> String {
            var out = ""
            while i < chars.count {
                let c = chars[i]
                i += 1
                if c == "\"" { return out }
                if c == "\\", i < chars.count {
                    let e = chars[i]
                    i += 1
                    switch e {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "\\": out.append("\\")
                    case "\"": out.append("\"")
                    default: out.append("\\"); out.append(e)
                    }
                } else {
                    out.append(c)
                }
            }
            throw VDFError.unexpectedEnd
        }

        mutating func bare() -> String {
            var out = ""
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "{", chars[i] != "}", chars[i] != "\"" {
                out.append(chars[i])
                i += 1
            }
            return out
        }
    }
}
