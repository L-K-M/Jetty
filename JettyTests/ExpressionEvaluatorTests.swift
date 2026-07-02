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

    // MARK: Formatting

    func testWholeNumberHasNoDecimalPoint() {
        XCTAssertEqual(value("4/2"), "2")
        XCTAssertFalse(value("4/2")?.contains(".") ?? true)
    }

    func testTrailingZerosTrimmed() {
        XCTAssertEqual(value("1/8"), "0.125")
        XCTAssertEqual(value("1/2"), "0.5")
    }

    func testExpressionEcho() {
        XCTAssertEqual(ExpressionEvaluator.evaluate(" 2 + 2 ")?.expression, "2 + 2")
    }
}
