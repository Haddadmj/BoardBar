import Testing

@testable import BoardBarCore

@Suite("Base direction")
struct TextDirectionTests {
    /// The real card on the target board.
    @Test("the Qurba issue title resolves right-to-left")
    func realTitle() {
        #expect(
            TextDirection.resolve("اضافة ختمات للغرفه كنوع اضافي وليس كعمل") == .rightToLeft
        )
    }

    @Test("an English title resolves left-to-right")
    func englishTitle() {
        #expect(TextDirection.resolve("Fix the poll scheduler back-off") == .leftToRight)
    }

    /// The case the whole "first *strong*" rule exists for. A title opening
    /// with a number or a bracket is not a left-to-right title.
    @Test(
        "leading neutrals are skipped, not treated as left-to-right",
        arguments: [
            "#20 اضافة ختمات",
            "  اضافة ختمات",
            "(اضافة) ختمات",
            "[2] اضافة",
            "— اضافة",
            "123 اضافة",
        ]
    )
    func leadingNeutrals(_ title: String) {
        #expect(TextDirection.resolve(title) == .rightToLeft)
    }

    @Test("a Latin word before Arabic wins, because it comes first")
    func latinFirst() {
        #expect(TextDirection.resolve("Bug: اضافة ختمات") == .leftToRight)
    }

    @Test("Hebrew resolves right-to-left too")
    func hebrew() {
        #expect(TextDirection.resolve("שלום עולם") == .rightToLeft)
    }

    @Test(
        "text with no strong character at all falls back to left-to-right",
        arguments: ["", "   ", "#20", "123 456", "!!!", "🎉 🎊"]
    )
    func noStrongCharacter(_ text: String) {
        #expect(TextDirection.resolve(text) == .leftToRight)
    }

    @Test("Arabic presentation forms are recognised as right-to-left")
    func presentationForms() {
        // U+FE8D ARABIC LETTER ALEF ISOLATED FORM
        #expect(TextDirection.resolve("\u{FE8D}") == .rightToLeft)
    }

    @Test("CJK is strong and left-to-right")
    func cjk() {
        #expect(TextDirection.resolve("修复错误") == .leftToRight)
    }
}
