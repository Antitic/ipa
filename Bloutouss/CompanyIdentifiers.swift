import Foundation

/// Sous-ensemble des identifiants de fabricants attribués par le Bluetooth SIG.
enum CompanyIdentifiers {
    private static let names: [UInt16: String] = [
        0x0000: "Ericsson",
        0x0001: "Nokia",
        0x0002: "Intel",
        0x0003: "IBM",
        0x0006: "Microsoft",
        0x000A: "Qualcomm",
        0x000D: "Texas Instruments",
        0x000F: "Broadcom",
        0x001D: "Qualcomm",
        0x004C: "Apple",
        0x0057: "Harman",
        0x0059: "Nordic Semiconductor",
        0x0065: "HP",
        0x006B: "Polar Electro",
        0x0075: "Samsung",
        0x0078: "Nike",
        0x0087: "Garmin",
        0x009E: "Bose",
        0x00D2: "Dialog Semiconductor",
        0x00E0: "Google",
        0x0131: "Cypress Semiconductor",
        0x0157: "Huami (Amazfit)",
        0x0171: "Amazon",
        0x027D: "Huawei",
        0x02E5: "Espressif",
        0x038F: "Xiaomi",
        0x0499: "Ruuvi Innovations",
        0x05A7: "Sonos",
    ]

    static func name(for id: UInt16) -> String? {
        names[id]
    }
}
