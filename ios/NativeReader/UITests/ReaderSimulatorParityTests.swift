import XCTest

final class ReaderSimulatorParityTests: XCTestCase {
    func testOpenBookAndUseReaderTapZones() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-xiaoman.reader.autoTurnSeconds", "3"]
        app.launch()

        XCTAssertTrue(app.staticTexts["什锦铺"].waitForExistence(timeout: 30))

        let bookPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "home.book.")
        let book = app.buttons.matching(bookPredicate).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30), "首页没有可打开的小说卡片")
        if !book.isHittable { app.swipeUp() }
        book.tap()

        let startReading = app.buttons["bookDetail.startReading"]
        XCTAssertTrue(startReading.waitForExistence(timeout: 30), "作品详情页没有显示开始阅读入口")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: startReading)
        waitForExpectations(timeout: 60)
        startReading.tap()

        let indicator = app.staticTexts["reader.pageIndicator"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 30), "阅读页分页指示器没有出现")
        let pageSurface = app.staticTexts["reader.pageSurface"]
        XCTAssertTrue(pageSurface.waitForExistence(timeout: 10), "阅读正文没有呈现")

        let firstPageText = pageSurface.label
        pageSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "点击翻页区域后阅读页消失")
        expectation(for: NSPredicate(format: "label != %@", firstPageText), evaluatedWith: pageSurface)
        waitForExpectations(timeout: 10)

        pageSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(indicator.waitForNonExistence(timeout: 10), "中间点击区没有隐藏阅读控件")
        pageSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "中间点击区没有恢复阅读控件")

        app.buttons["reader.settings"].tap()
        let autoTurn = app.descendants(matching: .any)["reader.autoTurn"]
        XCTAssertTrue(autoTurn.waitForExistence(timeout: 10), "阅读设置中没有自动翻页开关")
        let pageBeforeAutoTurn = pageSurface.label
        autoTurn.tap()
        expectation(for: NSPredicate(format: "label != %@", pageBeforeAutoTurn), evaluatedWith: pageSurface)
        waitForExpectations(timeout: 8)
    }
}
