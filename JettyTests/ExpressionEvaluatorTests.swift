import XCTest
@testable import Jetty

final class ExpressionEvaluatorTests: XCTestCase {

    private func value(_ input: String) -> String? {
        ExpressionEvaluator.evaluate(input)?.value
    }

    // MARK: Basic arithmetic

    func testAddition() { XCTAssertEqual(value("2+2"), "4") }
    func testSubtraction() { XCTAssertEqual(value("10-3"), "7") }
    func testMultiplication() { XCTAssertEqual(value("6*7"), "42") }
    func testDivision() { XCTAssertEqual(value("9/3"), "3") }
    func testDecimalResult() { XCTAssertEqual(value("3/4"), "0.75") }

    func testWhitespaceIsIgnored() {
        XCTAssertEqual(value("  12   +   30 "), "42")
    }

    // MARK: Precedence & associativity

    func testMultiplicationBeforeAddition() {
        XCTAssertEqual(value("2+3*4"), "14")
    }

    func testParenthesesOverridePrecedence() {
        XCTAssertEqual(value("(2+3)*4"), "20")
    }

    func testPowerBindsTighterThanTimes() {
        XCTAssertEqual(value("2*3^2"), "18")   // 2 * (3^2)
    }

    func testPowerIsRightAssociative() {
        XCTAssertEqual(value("2^3^2"), "512")  // 2^(3^2) = 2^9
    }

    func testUnaryMinus() {
        XCTAssertEqual(value("-5+8"), "3")
        XCTAssertEqual(value("3*-4"), "-12")
    }

    func testUnaryMinusIsLooserThanPower() {
        // -2^2 == -(2^2) == -4, matching Spotlight/Google/Python (not Excel).
        XCTAssertEqual(value("-2^2"), "-4")
        // The exponent still parses as a factor, so a negative exponent works.
        XCTAssertEqual(value("2^-2"), "0.25")
        XCTAssertEqual(value("-2^-2"), "-0.25")
    }

    // MARK: Percent

    func testTrailingPercentIsHundredth() {
        XCTAssertEqual(value("50%"), "0.5")
    }

    func testPercentOfValue() {
        XCTAssertEqual(value("200*15%"), "30")
    }

    func testPercentAfterPlusMinusIsPercentOfLeftOperand() {   // FAB-B10
        // The desk-calculator/Spotlight/Google convention: X ± Y% == X ± (Y% of X).
        XCTAssertEqual(value("100 - 25%"), "75")
        XCTAssertEqual(value("899 - 15%"), "764.15")
        XCTAssertEqual(value("100 + 10%"), "110")
        // The percent-of applies per +/- step: (100 - 25%) = 75, then + 10 = 85.
        XCTAssertEqual(value("100-25%+10"), "85")
    }

    func testPercentTimesDivideKeepHundredthMeaning() {   // FAB-B10
        XCTAssertEqual(value("200*15%"), "30")
        XCTAssertEqual(value("100/50%"), "200")
        // A percent that went through *, /, or ^ is no longer a bare percent term.
        XCTAssertEqual(value("100+2*50%"), "101")
    }

    // MARK: Implicit multiplication (FAB-D19)

    func testImplicitMultiplicationByJuxtaposition() {
        XCTAssertEqual(value("2(3+4)"), "14")
        XCTAssertEqual(value("(1+2)(3+4)"), "21")
        XCTAssertEqual(value("2(3+4)+1"), "15")
    }

    // MARK: Glyph aliases

    func testUnicodeMultiplyAndDivide() {
        XCTAssertEqual(value("6×7"), "42")
        XCTAssertEqual(value("9÷3"), "3")
    }

    func testUnicodeMinusSign() {
        // U+2212 (typographic minus, as pasted from web pages / PDFs) aliases '-'.
        XCTAssertEqual(value("7\u{2212}2"), "5")
        XCTAssertEqual(value("\u{2212}5+8"), "3")
    }

    // MARK: Non-expressions are rejected (so app searches never show a result)

    func testPlainQueryIsNotAnExpression() {
        XCTAssertNil(ExpressionEvaluator.evaluate("Safari"))
        XCTAssertNil(ExpressionEvaluator.evaluate("System Settings"))
    }

    func testBareNumberIsNotShown() {
        XCTAssertNil(ExpressionEvaluator.evaluate("42"))
    }

    func testEmptyIsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("   "))
    }

    // MARK: Malformed input degrades gracefully (nil, never a crash/garbage)

    func testDivisionByZeroIsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("1/0"))
    }

    func testDanglingOperatorIsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("2+"))
        XCTAssertNil(ExpressionEvaluator.evaluate("*5"))
    }

    func testUnbalancedParenthesesIsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("(2+3"))
        XCTAssertNil(ExpressionEvaluator.evaluate("2+3)"))
    }

    func testGarbageWithOperatorIsNil() {
        XCTAssertNil(ExpressionEvaluator.evaluate("2 + abc"))
    }

    // MARK: Pathological input is rejected, never crashed on (FAB-B9)

    func testDeeplyNestedParenthesesReturnNil() {
        // 100 levels blows the 64-level depth cap; the parser must bail, not
        // stack-overflow. (Kept under the 256-character input cap so this
        // exercises the depth counter itself.)
        let nested = String(repeating: "(", count: 100) + "1+1" + String(repeating: ")", count: 100)
        XCTAssertNil(ExpressionEvaluator.evaluate(nested))
    }

    func testReasonableNestingStillWorks() {
        XCTAssertEqual(value("((((1+2))))*2"), "6")
    }

    func testOverlongInputReturnsNil() {
        let long = String(repeating: "1+", count: 200) + "1"   // 401 chars, valid math
        XCTAssertNil(ExpressionEvaluator.evaluate(long))
    }

    func testUnarySignWallDoesNotCrash() {
        // A pasted wall of unary minuses is rejected by the length cap…
        XCTAssertNil(ExpressionEvaluator.evaluate(String(repeating: "-", count: 10_000) + "5"))
        // …and a short chain is folded iteratively (8 minuses = even = positive).
        XCTAssertEqual(value("--------5+1"), "6")
    }

    // MARK: Formatting

    func testWholeNumberHasNoDecimalPoint() {
        XCTAssertEqual(value("4/2"), "2")
        XCTAssertFalse(value("4/2")?.contains(".") ?? true)
    }

    func testTrailingZerosTrimmed() {
        XCTAssertEqual(value("1/8"), "0.125")
        XCTAssertEqual(value("1/2"), "0.5")
    }

    func testTinyNonZeroResultIsNeverZero() {   // FAB-B8
        // Below the 10-fraction-digit budget the formatter must switch to
        // scientific notation, never print a false "0"/"-0".
        XCTAssertEqual(value("2^-40"), "9.094947018e-13")
        XCTAssertEqual(value("10^-11"), "1e-11")
        XCTAssertEqual(value("0-0.00000000001"), "-1e-11")
    }

    func testNormalMagnitudeFormattingIsUnchanged() {   // FAB-B8 guard rail
        XCTAssertEqual(value("1/3"), "0.3333333333")
        XCTAssertEqual(value("2^-10"), "0.0009765625")
    }

    func testHugeMagnitudeUsesSignificantDigits() {
        // Past the integer fast path, fixed-fraction printing would dump binary64
        // noise (~200 digits for 2^700); significant digits stay truthful.
        XCTAssertEqual(value("2^700"), "1.412874631e210")
        XCTAssertEqual(ExpressionEvaluator.format(1.5e16), "1.5e16")
        XCTAssertEqual(ExpressionEvaluator.format(-2.5e15), "-2.5e15")
    }

    func testExpressionEcho() {
        XCTAssertEqual(ExpressionEvaluator.evaluate(" 2 + 2 ")?.expression, "2 + 2")
    }
}
