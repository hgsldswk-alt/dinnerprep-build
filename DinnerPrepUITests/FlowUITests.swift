import XCTest

final class FlowUITests: XCTestCase {
    private enum StoreLanguage: String, CaseIterable {
        case english = "en"
        case simplifiedChinese = "zh-Hans"
        case traditionalChinese = "zh-Hant"

        var locale: String {
            switch self {
            case .english: "en_US"
            case .simplifiedChinese: "zh_CN"
            case .traditionalChinese: "zh_TW"
            }
        }

        var reminderSet: String {
            switch self {
            case .english: "Reminder set"
            case .simplifiedChinese: "提醒已设"
            case .traditionalChinese: "提醒已設定"
            }
        }
    }

    @MainActor private lazy var app = XCUIApplication()
    private let importJSON = """
        [{"name":"Slice onions","minutes":8},
         {"name":"Cook beans","minutes":25}]
        """

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ flags: [String] = [], language: StoreLanguage = .english, locale: String? = nil,
                        reset: Bool = true, code: String? = nil, prepFile: String? = nil) {
        if app.state != .notRunning { app.terminate() }
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))",
                               "-AppleLocale", locale ?? language.locale] + (reset ? ["-reset"] : []) + flags
        var environment: [String: String] = [:]
        environment["DINNER_TEST_PREP_CODE"] = code
        environment["DINNER_TEST_PREP_FILE"] = prepFile
        app.launchEnvironment = environment
        app.launch()
        if flags.contains("-paywall") {
            XCTAssertTrue(app.buttons["paywall.close"].waitForExistence(timeout: 20))
        } else {
            let recipe = app.buttons["home.recipe"]
            let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"),
                                                    object: recipe)
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
        }
    }

    @MainActor
    private func button(_ id: String) -> XCUIElement {
        let matches = app.buttons.matching(identifier: id)
        return matches.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? matches.firstMatch
    }

    @MainActor
    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        for step in 0..<10 {
            let candidate = button(id)
            if candidate.exists && candidate.isHittable {
                candidate.tap()
                return
            }
            if step < 5 { app.swipeUp() } else { app.swipeDown() }
        }
        let candidate = button(id)
        XCTAssertTrue(candidate.waitForExistence(timeout: 5) && candidate.isHittable, id, file: file, line: line)
        candidate.tap()
    }

    @MainActor
    private func replace(_ field: XCUIElement, with text: String, alreadyFocused: Bool = false) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let old = field.value as? String ?? ""
        let count = field.placeholderValue == old ? 0 : old.count
        if alreadyFocused {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        } else {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        }
        if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count + 2)) }
        field.typeText(text)
    }

    @MainActor
    private func assertLabel(_ element: XCUIElement, contains text: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), text, file: file, line: line)
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 6), .completed, file: file, line: line)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func storeShot(_ language: StoreLanguage, _ scene: String) {
        capture("store-\(language.rawValue)-\(scene)")
    }

    private func code(for json: String) -> String {
        "DP1:" + Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    @MainActor
    func testFreshPlanInputsAndReuseAfterRelaunch() {
        launch(["-assert-reminders"])
        XCTAssertFalse(app.buttons["reminder.enable"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        tap("home.recipe")
        XCTAssertFalse(app.buttons["recipe.remind"].isEnabled)
        replace(app.textFields["recipe.minutes"], with: "35", alreadyFocused: true)
        assertLabel(app.staticTexts["recipe.preview"], contains: "6:25")
        tap("recipe.remind")
        assertLabel(app.staticTexts["home.startTime"], contains: "6:25")
        assertLabel(app.staticTexts["reminder.status"], contains: "Reminder set")
        assertLabel(app.staticTexts["reminder.time"], contains: "6:25")
        assertLabel(app.staticTexts["test.reminderCount"], contains: "1")

        tap("home.dinner")
        let minute = app.datePickers["dinner.time"].pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minute.waitForExistence(timeout: 5))
        minute.adjust(toPickerWheelValue: "30")
        assertLabel(app.staticTexts["dinner.preview"], contains: "6:55")
        tap("dinner.done")
        assertLabel(app.staticTexts["home.startTime"], contains: "6:55")
        assertLabel(app.staticTexts["reminder.time"], contains: "6:55")
        tap("home.toggle.meat")
        assertLabel(app.staticTexts["home.startTime"], contains: "6:40")

        launch(reset: false)
        assertLabel(app.staticTexts["home.startTime"], contains: "6:40")
    }

    @MainActor
    func testOneReminderUpdatesAndCancels() {
        launch(["-sample", "-assert-reminders"])
        assertLabel(app.staticTexts["home.startTime"], contains: "6:05")
        tap("reminder.enable")
        assertLabel(app.staticTexts["reminder.status"], contains: "Reminder set")
        assertLabel(app.staticTexts["reminder.time"], contains: "6:05")
        assertLabel(app.staticTexts["test.reminderCount"], contains: "1")
        tap("home.toggle.meat")
        assertLabel(app.staticTexts["reminder.time"], contains: "6:20")
        assertLabel(app.staticTexts["test.reminderCount"], contains: "1")
        tap("reminder.cancel")
        XCTAssertTrue(app.buttons["reminder.enable"].waitForExistence(timeout: 5))
        assertLabel(app.staticTexts["test.reminderCount"], contains: "0")
        tap("home.toggle.meat")
        XCTAssertTrue(app.buttons["reminder.enable"].waitForExistence(timeout: 5))
        assertLabel(app.staticTexts["test.reminderCount"], contains: "0")
    }

    @MainActor
    func testDeniedThenAuthorizedAndFailedRequestFeedback() {
        launch(["-sample", "-denied"])
        tap("reminder.enable")
        XCTAssertTrue(app.staticTexts["reminder.notice"].waitForExistence(timeout: 5))
        tap("reminder.settings")
        XCTAssertFalse(app.buttons["reminder.cancel"].exists)
        tap("reminder.enable")
        assertLabel(app.staticTexts["reminder.status"], contains: "Reminder set")

        launch(["-sample", "-reminder-failure"])
        tap("reminder.enable")
        assertLabel(app.staticTexts["reminder.notice"], contains: "Couldn’t set the reminder")
        XCTAssertFalse(app.buttons["reminder.cancel"].exists)
    }

    @MainActor
    func testLateSuggestionAndSeventhCookingDay() {
        launch(["-late", "-demo-milestone"])
        assertLabel(app.staticTexts["home.late"], contains: "13 min")
        assertLabel(app.staticTexts["home.earliestTime"], contains: "7:13")
        tap("home.suggest")
        XCTAssertFalse(app.buttons["home.suggest"].exists)
        tap("home.started")
        XCTAssertTrue(app.staticTexts["home.cookingRecorded"].waitForExistence(timeout: 5))
        tap("home.milestone")
        XCTAssertTrue(app.images["share.card"].waitForExistence(timeout: 15))
        tap("share.image")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 15))
        tap("share.close")
        tap("home.hideMilestone")
        tap("home.settings")
        tap("settings.milestone")
        XCTAssertTrue(app.images["share.card"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testShareAndPreviewImportDoNotChangeCurrentMeal() {
        launch(["-sample"], code: "\n" + code(for: importJSON) + "\n")
        tap("home.planCard")
        assertLabel(app.images["share.card"], contains: "55 min")
        let toggle = app.switches["share.showTimes"].firstMatch
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        assertLabel(app.images["share.card"], contains: "Start")
        tap("share.image")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 15))
        tap("share.copyCode")
        XCTAssertTrue(app.staticTexts["share.copied"].waitForExistence(timeout: 5))
        tap("share.close")
        tap("home.library")
        tap("library.paste")
        XCTAssertTrue(app.staticTexts["Slice onions"].waitForExistence(timeout: 15))
        tap("import.confirm")
        assertLabel(app.staticTexts["library.notice"], contains: "Imported 2")
        XCTAssertTrue(app.staticTexts["Cook beans"].exists)
        tap("library.export")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 15))
        tap("library.done")
        assertLabel(app.staticTexts["home.startTime"], contains: "6:05")
    }

    @MainActor
    func testInvalidCodeAndExpiredLibraryStillUsable() {
        launch(["-demo-library", "-expired"], code: "DP2:AA")
        tap("home.library")
        tap("library.paste")
        XCTAssertTrue(app.staticTexts["library.notice"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["import.confirm"].exists)
        tap("library.toggle.demo.tray")
        tap("library.add")
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        tap("paywall.close")
        tap("library.done")
        assertLabel(app.staticTexts["home.startTime"], contains: "5:58")
        tap("home.settings")
        tap("settings.savedPlans")
        XCTAssertTrue(app.staticTexts["Weeknight dinner"].waitForExistence(timeout: 5))
        tap("presets.share.sample")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 15))
        tap("share.close")
        tap("presets.use.sample")
        XCTAssertTrue(app.staticTexts["paywall.status"].exists)
    }

    @MainActor
    func testFileImportFromHomePreviewsBeforeWriting() {
        launch(["-sample"], prepFile: code(for: importJSON))
        tap("home.importFile")
        XCTAssertTrue(app.staticTexts["Slice onions"].waitForExistence(timeout: 15))
        tap("import.cancel")
        tap("home.library")
        XCTAssertTrue(app.buttons["library.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Slice onions"].exists)
        tap("library.done")

        tap("home.importFile")
        XCTAssertTrue(app.buttons["import.confirm"].waitForExistence(timeout: 15))
        tap("import.confirm")
        assertLabel(app.staticTexts["library.notice"], contains: "Imported 2")
        XCTAssertTrue(app.staticTexts["Cook beans"].exists)
    }

    @MainActor
    func testManualCodePreviewsAsSoonAsValid() {
        launch(["-sample"])
        tap("home.library")
        tap("library.enterCode")
        let field = app.textViews["manual.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(code(for: importJSON))
        XCTAssertTrue(app.buttons["import.confirm"].waitForExistence(timeout: 5))
        tap("import.confirm")
        assertLabel(app.staticTexts["library.notice"], contains: "Imported 2")
    }

    @MainActor
    func testFileImportShowsPartialPreviewAfterTrial() {
        let first = code(for: importJSON)
        let second = code(for: #"[{"name":"Basil","minutes":3},{"name":"Garlic","minutes":4}]"#)
        launch(["-sample", "-expired"], prepFile: first + "\n" + second)
        tap("home.importFile")
        assertLabel(app.staticTexts["import.limited"], contains: "can add 3")
        XCTAssertFalse(app.buttons["library.done"].exists)
        tap("import.confirm")
        assertLabel(app.staticTexts["library.notice"], contains: "Imported 3")
        XCTAssertTrue(app.staticTexts["Basil"].exists)
        XCTAssertFalse(app.staticTexts["Garlic"].exists)
    }

    @MainActor
    func testEditExistingLibraryMinutesInThreeTaps() {
        launch(["-sample"])
        tap("home.library")
        tap("library.edit.meat")
        replace(app.textFields["prepEdit.minutes"], with: "18", alreadyFocused: true)
        tap("prepEdit.save")
        assertLabel(app.buttons["library.edit.meat"], contains: "18 min")

        tap("library.done")
        assertLabel(app.staticTexts["home.startTime"], contains: "6:05")
    }

    @MainActor
    func testCreatePersonalPrepUseSnapshotAndSavePreset() {
        launch(["-sample", "-purchased"])
        tap("home.library")
        tap("library.add")
        replace(app.textFields["prepEdit.name"], with: "Chop carrots")
        replace(app.textFields["prepEdit.minutes"], with: "8")
        let pin = app.switches["prepEdit.pin"].firstMatch
        XCTAssertTrue(pin.isHittable)
        pin.tap()
        tap("prepEdit.save")
        XCTAssertTrue(app.staticTexts["Chop carrots"].exists)
        tap("library.done")
        let toggle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "home.toggle.", "Chop carrots")).firstMatch
        XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        assertLabel(app.staticTexts["home.startTime"], contains: "5:57")
        tap("home.settings")
        tap("settings.savedPlans")
        tap("presets.save")
        replace(app.textFields["presetEdit.name"], with: "Weeknight plan")
        tap("presetEdit.save")
        XCTAssertTrue(app.staticTexts["Weeknight plan"].exists)
        XCTAssertTrue(app.staticTexts["Chop carrots · 8 min"].exists)
    }

    @MainActor
    func testTwentyFourHourLocaleAndAccessibilityText() {
        launch(["-sample", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"],
               locale: "en_GB")
        assertLabel(app.staticTexts["home.startTime"], contains: "18:05")
        tap("home.toggle.meat")
        assertLabel(app.staticTexts["home.startTime"], contains: "18:20")
    }

    @MainActor
    func testStoreScreenshots() {
        for language in StoreLanguage.allCases {
            launch(["-store-basic"], language: language)
            XCTAssertTrue(app.staticTexts["home.startTime"].waitForExistence(timeout: 15))
            storeShot(language, "01-start")
            launch(["-sample"], language: language)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.breakdown").firstMatch.exists)
            storeShot(language, "02-prep")
            tap("reminder.enable")
            assertLabel(app.staticTexts["reminder.status"], contains: language.reminderSet)
            storeShot(language, "03-reminder")
            launch(["-demo-library"], language: language)
            tap("home.library")
            XCTAssertTrue(app.buttons["library.edit.demo.onions"].waitForExistence(timeout: 15))
            storeShot(language, "04-library")
            tap("library.done")
            tap("home.planCard")
            XCTAssertTrue(app.images["share.card"].waitForExistence(timeout: 15))
            storeShot(language, "05-share")
        }
    }

    @MainActor
    func testPaidReviewScreenshot() {
        launch(["-paywall"], language: .simplifiedChinese)
        XCTAssertTrue(app.staticTexts["paywall.status"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["paywall.buy"].exists)
        XCTAssertTrue(app.buttons["paywall.trial"].exists)
        XCTAssertTrue(app.buttons["paywall.restore"].exists)
        capture("paid-01-paywall")
    }
}
