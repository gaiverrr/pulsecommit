import SwiftUI

enum Theme {
    static let bg = Color(red: 0x0a / 255, green: 0x0a / 255, blue: 0x0a / 255)
    static let surface = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255)
    static let elevated = Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1c / 255)
    static let raised = Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x24 / 255)
    static let divider = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.10)

    static let text = Color(red: 0xfa / 255, green: 0xfa / 255, blue: 0xfa / 255)
    static let muted = Color(red: 0xa3 / 255, green: 0xa3 / 255, blue: 0xa3 / 255)
    static let dim = Color(red: 0x73 / 255, green: 0x73 / 255, blue: 0x73 / 255)
    static let faint = Color(red: 0x52 / 255, green: 0x52 / 255, blue: 0x52 / 255)

    static let success = Color(red: 0x00 / 255, green: 0xD2 / 255, blue: 0x6A / 255)
    static let warn = Color(red: 0xFF / 255, green: 0xAD / 255, blue: 0x33 / 255)
    static let error = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)

    static let accent = Color(red: 0xA4 / 255, green: 0xF0 / 255, blue: 0x3A / 255)
    static let accentSoft = Color(red: 0xA4 / 255, green: 0xF0 / 255, blue: 0x3A / 255).opacity(0.16)

    enum Hex {
        static let accent: UInt32 = 0xA4F03A
        static let bg: UInt32 = 0x0a0a0a
        static let surface: UInt32 = 0x141414
        static let elevated: UInt32 = 0x1c1c1c
        static let raised: UInt32 = 0x242424
        static let text: UInt32 = 0xfafafa
        static let muted: UInt32 = 0xa3a3a3
        static let dim: UInt32 = 0x737373
        static let faint: UInt32 = 0x525252
        static let success: UInt32 = 0x00D26A
        static let warn: UInt32 = 0xFFAD33
        static let error: UInt32 = 0xFF453A
    }
}

extension Font {
    static let pcLargeTitle = Font.system(size: 32, weight: .bold).leading(.tight)
    static let pcHeroNumber = Font.system(size: 64, weight: .bold, design: .monospaced)
    static let pcStatTile = Font.system(size: 36, weight: .semibold, design: .monospaced)
    static let pcBigButton = Font.system(size: 36, weight: .bold).leading(.tight)
    static let pcTitle = Font.system(size: 18, weight: .bold)
    static let pcBodyLarge = Font.system(size: 17, weight: .medium)
    static let pcBody = Font.system(size: 15, weight: .medium)
    static let pcBodySemibold = Font.system(size: 15, weight: .semibold)
    static let pcBodySmall = Font.system(size: 14)
    static let pcCaption = Font.system(size: 13)
    static let pcMonoDetail = Font.system(size: 12, design: .monospaced)
    static let pcCaptionMono = Font.system(size: 11, design: .monospaced)
    static let pcLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
}
