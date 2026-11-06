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

        let indicator = app.descendants(matching: .any)["reader.pageIndicator"]
        if !indicator.waitForExistence(timeout: 5) {
            app.buttons["reader.settings"].tap()
            let pagedMode = app.buttons["分页阅读"].firstMatch
            XCTAssertTrue(pagedMode.waitForExistence(timeout: 10), "阅读设置中没有分页阅读模式")
            pagedMode.tap()
        }
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
        let detailedInfo = app.buttons["详细"].firstMatch
        XCTAssertTrue(detailedInfo.waitForExistence(timeout: 10), "阅读信息菜单没有详细模式")
        detailedInfo.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "第"), evaluatedWith: indicator)
        waitForExpectations(timeout: 10)

        app.buttons["reader.settings"].tap()
        let hiddenInfo = app.buttons["关闭"].firstMatch
        XCTAssertTrue(hiddenInfo.waitForExistence(timeout: 10), "阅读信息菜单没有关闭模式")
        hiddenInfo.tap()
        XCTAssertTrue(indicator.waitForNonExistence(timeout: 10), "关闭阅读信息后页脚仍显示")

        app.buttons["reader.settings"].tap()
        let compactInfo = app.buttons["简洁"].firstMatch
        XCTAssertTrue(compactInfo.waitForExistence(timeout: 10), "阅读信息菜单没有简洁模式")
        compactInfo.tap()
        XCTAssertTrue(indicator.waitForExistence(timeout: 10), "简洁模式没有恢复页码")

        app.buttons["reader.settings"].tap()
        let autoTurn = app.descendants(matching: .any)["reader.autoTurn"]
        XCTAssertTrue(autoTurn.waitForExistence(timeout: 10), "阅读设置中没有自动翻页开关")
        let pageBeforeAutoTurn = pageSurface.label
        autoTurn.tap()
        expectation(for: NSPredicate(format: "label != %@", pageBeforeAutoTurn), evaluatedWith: pageSurface)
        waitForExpectations(timeout: 8)

        app.buttons["reader.settings"].tap()
        let scrollMode = app.buttons["滚动阅读"].firstMatch
        XCTAssertTrue(scrollMode.waitForExistence(timeout: 10), "阅读设置中没有滚动阅读模式")
        scrollMode.tap()
        XCTAssertTrue(app.buttons["reader.previousChapter"].waitForExistence(timeout: 10), "滚动正文末尾没有上一章入口")
        XCTAssertTrue(app.buttons["reader.nextChapter"].exists, "滚动正文没有下一章入口")

        let speechMenu = app.buttons["reader.systemSpeech"]
        XCTAssertTrue(speechMenu.waitForExistence(timeout: 10), "阅读页没有系统朗读入口")
        speechMenu.tap()
        let startSpeech = app.buttons["reader.systemSpeech.toggle"]
        XCTAssertTrue(startSpeech.waitForExistence(timeout: 10), "系统朗读菜单没有开始按钮")
        startSpeech.tap()
        speechMenu.tap()
        let pauseSpeech = app.buttons["reader.systemSpeech.toggle"]
        XCTAssertTrue(pauseSpeech.waitForExistence(timeout: 10), "开始朗读后没有暂停状态")
        XCTAssertEqual(pauseSpeech.label, "暂停朗读")
        app.buttons["reader.systemSpeech.stop"].tap()
        speechMenu.tap()
        let startAgain = app.buttons["reader.systemSpeech.toggle"]
        XCTAssertTrue(startAgain.waitForExistence(timeout: 10), "停止朗读后没有恢复待播放状态")
        XCTAssertEqual(startAgain.label, "开始系统朗读")
    }

    func testLocalServiceHealthFromSettings() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["什锦铺"].waitForExistence(timeout: 30))
        let mineTab = app.buttons["tab.我的"]
        XCTAssertTrue(mineTab.waitForExistence(timeout: 10), "底部导航没有“我的”入口")
        mineTab.tap()

        let serviceEntry = app.buttons["settings.entry.本地接口"]
        XCTAssertTrue(serviceEntry.waitForExistence(timeout: 10), "设置页没有本地接口入口")
        if !serviceEntry.isHittable { app.swipeUp() }
        serviceEntry.tap()

        let status = app.staticTexts["settings.service.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "本地服务状态没有显示")
        expectation(for: NSPredicate(format: "label == %@", "运行中"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.staticTexts["设备池"].exists || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "个设备")).firstMatch.exists)
    }
}
