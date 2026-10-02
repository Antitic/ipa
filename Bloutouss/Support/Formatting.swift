import Foundation

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Accepte « 01FF », « 01 ff », « 0x01 0xFF » ou « 01:FF ».
    init?(hexString: String) {
        let hex = hexString.lowercased()
            .replacingOccurrences(of: "0x", with: "")
            .filter { !$0.isWhitespace && $0 != ":" && $0 != "-" }
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

extension Double {
    var formattedDistance: String {
        if self < 1 {
            return String(format: "~%.0f cm", self * 100)
        }
        if self < 10 {
            return String(format: "~%.1f m", self)
        }
        return String(format: "~%.0f m", self)
    }
}

extension TimeInterval {
    /// « 45 s », « 12 min », « 1 h 05 ».
    var shortDuration: String {
        let seconds = Int(self)
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
    }
}
