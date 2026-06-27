import Foundation

extension String {
    func nilIfBlank() -> String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

extension String.Encoding {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
}

func decodeEntities(_ text: String) -> String {
    var result = text
    let replacements = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&#39;": "'",
        "&nbsp;": " "
    ]
    for (key, value) in replacements {
        result = result.replacingOccurrences(of: key, with: value)
    }
    return result
}

func readText(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return readText(from: data)
}

func readText(from data: Data) -> String? {
    if let encoding = detectEncodingByBOM(data),
       let text = decodeIgnoringBOM(data: data, encoding: encoding) {
        return text
    }

    if let encoding = extractMetaCharset(data),
       let text = String(data: data, encoding: encoding)?.nilIfBlank() {
        return text
    }

    let fallbacks: [String.Encoding] = [
        .utf8,
        .shiftJIS,
        .big5,
        .gb18030,
        .windowsCP1252,
        .isoLatin1,
    ]
    for encoding in fallbacks {
        if let text = String(data: data, encoding: encoding)?.nilIfBlank() {
            return text
        }
    }

    return nil
}

private func detectEncodingByBOM(_ data: Data) -> String.Encoding? {
    if data.count >= 4 && data[..<4] == Data([0x00, 0x00, 0xFE, 0xFF]) { return .utf32BigEndian }
    if data.count >= 4 && data[..<4] == Data([0xFF, 0xFE, 0x00, 0x00]) { return .utf32LittleEndian }
    if data.count >= 2 && data[..<2] == Data([0xFE, 0xFF]) { return .utf16BigEndian }
    if data.count >= 2 && data[..<2] == Data([0xFF, 0xFE]) { return .utf16LittleEndian }
    if data.count >= 3 && data[..<3] == Data([0xEF, 0xBB, 0xBF]) { return .utf8 }
    return nil
}

private func decodeIgnoringBOM(data: Data, encoding: String.Encoding) -> String? {
    switch encoding {
    case .utf16LittleEndian, .utf16BigEndian:
        return String(data: data, encoding: .utf16)
    case .utf32BigEndian:
        return data.count > 4 ? String(data: data[4...], encoding: .utf32BigEndian) : nil
    case .utf32LittleEndian:
        return data.count > 4 ? String(data: data[4...], encoding: .utf32LittleEndian) : nil
    case .utf8:
        return data.count > 3 ? String(data: data[3...], encoding: .utf8) : nil
    default:
        return String(data: data, encoding: encoding)
    }
}

private func extractMetaCharset(_ data: Data) -> String.Encoding? {
    let prefix = data.prefix(4096)
    guard let ascii = String(data: prefix, encoding: .ascii) ?? String(data: prefix, encoding: .isoLatin1) else {
        return nil
    }

    let pattern = try? NSRegularExpression(
        pattern: #"charset\s*=\s*["'\s]*([^"';\s>]+)"#,
        options: [.caseInsensitive]
    )
    guard let match = pattern?.firstMatch(in: ascii, range: NSRange(ascii.startIndex..., in: ascii)),
          let range = Range(match.range(at: 1), in: ascii)
    else { return nil }

    let charset = String(ascii[range]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch charset {
    case "utf-8", "utf8": return .utf8
    case "utf-16", "utf16": return .utf16
    case "utf-16le", "utf16le": return .utf16LittleEndian
    case "utf-16be", "utf16be": return .utf16BigEndian
    case "gb2312", "gbk", "gb18030": return String.Encoding.gb18030
    case "big5", "big5-hkscs": return String.Encoding.big5
    case "shift_jis", "shift-jis", "shiftjis", "sjis": return .shiftJIS
    case "euc-jp": return .japaneseEUC
    case "iso-8859-1", "latin1": return .isoLatin1
    case "windows-1252": return .windowsCP1252
    default: return nil
    }
}
