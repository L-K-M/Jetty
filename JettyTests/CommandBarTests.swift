import XCTest
@testable import Jetty

final class CommandBarTests: XCTestCase {

    // MARK: Unit conversion

    func testLengthConversion() {
        let result = UnitConverter.convert("10 km in miles")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.value.hasSuffix("mi"), result!.value)
        XCTAssertTrue(result!.value.hasPrefix("6.2"), result!.value)
    }

    func testTemperatureConversionExact() {
        XCTAssertEqual(UnitConverter.convert("0 c to f")?.value, "32 °F")
    }

    func testTemperatureFahrenheitToCelsius() {
        let result = UnitConverter.convert("100 f to c")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.value.hasSuffix("°C"), result!.value)
        XCTAssertTrue(result!.value.hasPrefix("37"), result!.value)
    }

    func testMassConversion() {
        let result = UnitConverter.convert("1 kg to lb")
        XCTAssertTrue(result?.value.hasSuffix("lb") ?? false)
        XCTAssertTrue(result?.value.hasPrefix("2.2") ?? false)
    }

    func testCrossDimensionAndNonsenseReturnNil() {
        XCTAssertNil(UnitConverter.convert("10 km in kg"))
        XCTAssertNil(UnitConverter.convert("safari"))
        XCTAssertNil(UnitConverter.convert("hello world"))
        XCTAssertNil(UnitConverter.convert("2+2"))
    }

    // MARK: Currency

    func testCurrencyRateParsing() {
        let json = Data(#"{"base":"USD","rates":{"EUR":0.9,"GBP":0.8}}"#.utf8)
        let rates = CurrencyService.parseRates(json)
        XCTAssertEqual(rates?["USD"], 1.0)
        XCTAssertEqual(rates?["EUR"], 0.9)
        XCTAssertEqual(rates?["GBP"], 0.8)
    }

    func testCurrencyRateParsingRejectsGarbage() {
        XCTAssertNil(CurrencyService.parseRates(nil))
        XCTAssertNil(CurrencyService.parseRates(Data("nope".utf8)))
        XCTAssertNil(CurrencyService.parseRates(Data("{}".utf8)))
    }

    func testCurrencyQueryParsing() {
        let parsed = CurrencyService.parseQuery("100 usd to eur")
        XCTAssertEqual(parsed?.amount, 100)
        XCTAssertEqual(parsed?.from, "USD")
        XCTAssertEqual(parsed?.to, "EUR")
        XCTAssertEqual(CurrencyService.parseQuery("50 gbp in usd")?.to, "USD")
        XCTAssertNil(CurrencyService.parseQuery("10 km in mi"))   // 2-letter tokens → not currency
    }

    func testCurrencyConversionMath() {
        let rates = ["USD": 1.0, "EUR": 0.9]
        XCTAssertEqual(CurrencyService.convert(amount: 100, from: "USD", to: "EUR", rates: rates)!, 90, accuracy: 0.001)
        XCTAssertEqual(CurrencyService.convert(amount: 90, from: "EUR", to: "USD", rates: rates)!, 100, accuracy: 0.001)
        XCTAssertNil(CurrencyService.convert(amount: 1, from: "USD", to: "XXX", rates: rates))
    }

    // MARK: Commands

    func testCommandMatching() {
        XCTAssertEqual(MenuCommand.match("dark"), .toggleDarkMode)
        XCTAssertEqual(MenuCommand.match("appearance"), .toggleDarkMode)
        XCTAssertNil(MenuCommand.match("xy"))        // too short
        XCTAssertNil(MenuCommand.match("safari"))    // unrelated
    }

    func testReturnRunsMatchedCommandBeforeLaunchingSelection() {
        let model = JettyMenuModel(appIndex: AppIndex())
        var launched = false
        var ranCommand: MenuCommand?
        model.onLaunch = { _ in launched = true }
        model.onRunCommand = { ranCommand = $0 }

        model.query = "dark"
        model.activateSelection()

        XCTAssertEqual(ranCommand, .toggleDarkMode)
        XCTAssertFalse(launched)
    }
}
