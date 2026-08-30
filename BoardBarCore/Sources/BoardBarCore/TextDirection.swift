import Foundation

/// The base writing direction of a run of text.
///
/// Deliberately not a SwiftUI type: the rule this implements is about the text,
/// not about a view, and keeping it here means it can be tested without a
/// window. The view layer maps it to `layoutDirection`.
public enum BaseDirection: String, Sendable, Equatable {
    case leftToRight
    case rightToLeft
}

public enum TextDirection {
    /// Resolves base direction from the first strong directional character,
    /// which is what the Unicode bidirectional algorithm does for a paragraph
    /// with no explicit direction (UAX #9, rule P2).
    ///
    /// Neutrals are skipped rather than treated as left-to-right. That matters
    /// here more than it looks: the boards this renders hold titles like
    /// "#20 اضافة ختمات" and `"("`, `"["`, digits and spaces are all neutral.
    /// Taking the first character literally would call a title left-to-right
    /// because it happens to open with a bracket.
    public static func resolve(_ text: String) -> BaseDirection {
        for scalar in text.unicodeScalars {
            if isStrongRTL(scalar) { return .rightToLeft }
            if isStrongLTR(scalar) { return .leftToRight }
        }
        // No strong character anywhere — digits, punctuation, emoji. Nothing to
        // mirror, so the app's own direction is as good an answer as any.
        return .leftToRight
    }

    /// Hebrew, Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic, and the Arabic
    /// and Hebrew presentation-form blocks.
    private static func isStrongRTL(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0590...0x05FF,  // Hebrew
            0x0600...0x06FF,  // Arabic
            0x0700...0x074F,  // Syriac
            0x0750...0x077F,  // Arabic Supplement
            0x0780...0x07BF,  // Thaana
            0x07C0...0x07FF,  // N'Ko
            0x0800...0x083F,  // Samaritan
            0x0840...0x085F,  // Mandaic
            0x08A0...0x08FF,  // Arabic Extended-A
            0xFB1D...0xFB4F,  // Hebrew presentation forms
            0xFB50...0xFDFF,  // Arabic presentation forms A
            0xFE70...0xFEFF:  // Arabic presentation forms B
            return true
        default:
            return false
        }
    }

    private static func isStrongLTR(_ scalar: Unicode.Scalar) -> Bool {
        // Alphabetic covers Latin, Cyrillic, Greek, CJK and the rest. Digits are
        // not alphabetic, which is what makes "#20 اضافة" resolve right-to-left
        // rather than on its leading number.
        scalar.properties.isAlphabetic
    }
}
