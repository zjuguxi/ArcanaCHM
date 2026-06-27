import Foundation

extension String {
    func nilIfBlank() -> String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
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
    let encodings: [String.Encoding] = [
        .utf8,
        .gb18030,
        .windowsCP1252,
        .isoLatin1
    ]
    for encoding in encodings {
        if let text = try? String(contentsOf: url, encoding: encoding),
           text.nilIfBlank() != nil {
            return text
        }
    }
    return nil
}

extension String.Encoding {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
}
