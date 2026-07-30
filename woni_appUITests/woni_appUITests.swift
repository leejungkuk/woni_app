//
//  woni_appUITests.swift
//  woni_appUITests
//
//  Created by J on 6/2/26.
//

import XCTest

class WoniAppUITestCase: XCTestCase {
    var app: XCUIApplication!
    private var isCollectingDiagnostics = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    override func record(_ issue: XCTIssue) {
        super.record(issue)
        // 첨부 수집 자체가 실패해 issue를 다시 기록하면 재진입한다. 앱이 살아 있을 때 한 번만 모은다.
        guard !isCollectingDiagnostics, let app, app.state == .runningForeground else {
            return
        }
        isCollectingDiagnostics = true
        defer { isCollectingDiagnostics = false }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Failure Screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let accessibilityTree = XCTAttachment(string: app.debugDescription)
        accessibilityTree.name = "Accessibility Tree"
        accessibilityTree.lifetime = .keepAlways
        add(accessibilityTree)
    }

    func runCase(_ name: String, _ block: () -> Void) {
        XCTContext.runActivity(named: name) { _ in
            block()
        }
    }
}

/// 기기 검증이 유일한 검증 수단인 케이스(cov: dev)와 P1 사용자 흐름을 자동화한다.
/// 앱은 `-uiTest` 훅으로 in-memory DB + Fake 인증에 붙으므로 실행 간 상태가 남지 않는다.
final class WoniAppUITests: WoniAppUITestCase {
    private var home: HomeScreen!
    private var entry: EntryScreen!
    private var settings: SettingsScreen!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = HomeScreen(app: app)
        entry = EntryScreen(app: app)
        settings = SettingsScreen(app: app)
        app.launchArguments = [
            UITestFlags.enable,
            UITestFlags.seedLedger,
            // 이전 실행이 남긴 UserDefaults가 기대값을 흔들지 않도록 기준 상태를 인자로 고정한다.
            "-woni.app.baseCurrency", "KRW",
            "-woni.app.language.override", "ko",
            "-woni.app.lastUsedCurrency", "KRW"
        ]
    }

    override func tearDownWithError() throws {
        settings = nil
        entry = nil
        home = nil
        try super.tearDownWithError()
    }

    // MARK: - A1 · B9 — 콜드 스타트와 합계

    @MainActor
    func testHomeShowsSeededTotalsOnColdStart() {
        app.launch()

        runCase("A1 cold-start-home") {
            XCTAssertTrue(
                home.summaryAmount(.expense).waitForExistence(timeout: Timeout.launch),
                "홈이 열리지 않았다"
            )
        }
        runCase("B9 seeded-totals") {
            XCTAssertTrue(
                home.summaryAmount(.expense).waitForLabel(Fixture.expenseText),
                "지출 합계가 \(Fixture.expenseText)여야 한다 (실제: \(home.summaryAmount(.expense).label))"
            )
            XCTAssertTrue(
                home.summaryAmount(.income).waitForLabel(Fixture.incomeText),
                "수입 합계가 \(Fixture.incomeText)여야 한다 (실제: \(home.summaryAmount(.income).label))"
            )
            XCTAssertTrue(
                home.summaryAmount(.total).waitForLabel(Fixture.totalText),
                "합계가 \(Fixture.totalText)여야 한다 (실제: \(home.summaryAmount(.total).label))"
            )
        }
    }

    // MARK: - B7 — 선택일 내역

    @MainActor
    func testSelectingTodayShowsOnlyThatDaysEntries() {
        app.launch()
        home.waitForReady()

        home.todayCell.tap()

        XCTAssertTrue(home.todayCell.waitForSelected(), "탭한 오늘 날짜 셀이 선택 상태로 바뀌어야 한다")
        XCTAssertTrue(
            home.historyRows.waitForCount(2),
            "시드가 넣은 오늘 거래 2건이 그대로 보여야 한다"
        )
    }

    // MARK: - B14 · C1 — 추가 진입

    @MainActor
    func testAddButtonOpensEntryFocusedOnAmount() {
        app.launch()
        home.waitForReady()

        home.addButton.tap()

        runCase("C1 amount-field-focus") {
            XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "키패드가 즉시 떠야 한다")
        }
        runCase("B14 selected-date-default") {
            XCTAssertTrue(entry.dateRow.label.contains(TestClock.todayDayNumber), "기본 날짜가 오늘이어야 한다")
        }
    }

    // MARK: - 사용자 제보 결함 — 연월 피커로 고른 연·월이 좌우 화살표에 반영되지 않는다

    /// 재현: 입력 화면에서 날짜 행 → 인라인 달력 → 연월 피커로 연·월을 고르고 저장한 뒤
    /// 오른쪽 화살표를 누르면 하루 뒤가 아니라 **한 달 뒤**로 건너뛴다.
    /// 원인은 피커 저장 후에도 `isCalendarExpanded`가 true로 남아 `DateRow.move(by:)`가
    /// `.day`가 아닌 `.month` 단위를 쓰는 것이다.
    ///
    /// 수정은 보류다(`.claude/docs/defect-backlog.md` D-001). 이 테스트가 실행 가능한 메모 역할을 하며,
    /// 고칠 때 `XCTExpectFailure`를 지우면 그대로 실제 통과 검증이 된다.
    @MainActor
    func testDateArrowMovesOneDayAfterYearMonthPicker() {
        app.launch()
        home.waitForReady()
        home.addButton.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))

        entry.dateRow.tap()
        XCTAssertTrue(
            entry.calendarDay(TestClock.todayDay).waitForExistence(timeout: Timeout.transition),
            "날짜 행 첫 탭으로 인라인 달력이 펼쳐져야 한다"
        )

        entry.dateRow.tap()
        XCTAssertTrue(
            entry.yearMonthPickerSave.waitForExistence(timeout: Timeout.transition),
            "날짜 행 두 번째 탭으로 연월 피커가 열려야 한다"
        )

        let pickedYear = TestClock.currentYear - 1
        entry.yearWheelRow(TestClock.currentYear).dragVertically(by: TestClock.wheelRowHeight)
        XCTAssertTrue(
            entry.pickerTitle(year: pickedYear, month: TestClock.currentMonth)
                .waitForExistence(timeout: Timeout.transition),
            "연도 휠을 한 칸 내려 이전 연도가 선택돼야 한다"
        )

        entry.yearMonthPickerSave.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForNonExistence(), "저장 후 연월 피커가 닫혀야 한다")

        // 화살표를 누르기 전에 저장이 고른 연·월을 실제로 반영했는지 못박는다.
        // 이 전제가 없으면 저장 자체가 어긋난 실패까지 아래 expected failure가 삼킨다.
        let pickedTitle = "\(pickedYear)년 \(TestClock.currentMonth)월"
        XCTAssertTrue(
            entry.dateRow.waitForLabel(pickedTitle),
            "피커 저장이 \(pickedTitle)을 반영해야 한다 (실제: \(entry.dateRow.label))"
        )

        // 앱의 day clamp 규칙을 테스트가 재구현하지 않도록, 실제 선택된 날짜를 달력에서 읽는다.
        guard let pickedDay = entry.selectedCalendarDay() else {
            return XCTFail("피커 저장 후 인라인 달력에 선택된 날짜가 있어야 한다")
        }
        guard let expectedDay = TestClock.dayAfter(year: pickedYear, month: TestClock.currentMonth, day: pickedDay)
        else {
            return XCTFail("기대 날짜를 계산하지 못했다")
        }

        entry.nextDateButton.tap()

        XCTExpectFailure("결함 D-001 — 피커 후에도 화살표가 월 단위로 동작한다. 수정 보류(defect-backlog.md)")
        XCTAssertTrue(
            entry.calendarDay(expectedDay).waitForSelected(),
            "화살표를 누르면 피커로 고른 \(pickedYear)년 \(TestClock.currentMonth)월 \(pickedDay)일에서 "
                + "하루 뒤인 \(expectedDay)일이 선택돼야 한다"
        )
    }

    // MARK: - C20 — 저장 후 홈 반영

    @MainActor
    func testSavingExpenseUpdatesHomeImmediately() {
        app.launch()
        home.waitForReady()

        home.addButton.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        // 신규 진입은 금액 필드가 자동 포커스된다. 여기서 tap하면 포커스가 오히려 풀린다.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition))
        app.typeText("5000")
        entry.submitButton.tap()

        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition), "저장 후 홈으로 돌아와야 한다")
        XCTAssertTrue(
            home.summaryAmount(.expense).waitForLabel("15,000"),
            "지출 합계가 새로고침 없이 갱신돼야 한다"
        )
    }

    // MARK: - B13 · D1 — 수정 진입 프리필

    @MainActor
    func testTappingHistoryRowPrefillsEditor() {
        app.launch()
        home.waitForReady()
        home.todayCell.tap()

        runCase("B13 history-row-opens-editor") {
            home.expenseHistoryRow.tap()
            XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        }
        runCase("D1 editor-prefill") {
            XCTAssertEqual(entry.amountField.value as? String, Fixture.expenseFieldValue)
            XCTAssertTrue(entry.deleteButton.exists, "수정 화면에는 삭제 버튼이 있어야 한다")
        }
    }

    // MARK: - D7 — 삭제 반영

    @MainActor
    func testDeletingEntryRemovesItFromTotals() {
        app.launch()
        home.waitForReady()
        home.todayCell.tap()
        home.expenseHistoryRow.tap()

        XCTAssertTrue(entry.deleteButton.waitForExistence(timeout: Timeout.transition))
        entry.deleteButton.tap()
        entry.deleteConfirmButton.tap()

        XCTAssertTrue(entry.deleteConfirmButton.waitForNonExistence(), "삭제 확인 overlay가 닫혀야 한다")
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(
            home.summaryAmount(.expense).waitForLabel("0"),
            "삭제한 지출이 합계에서 빠져야 한다"
        )
    }

    // MARK: - D9 — 저장하지 않고 나가면 미반영

    @MainActor
    func testLeavingEditorWithoutSavingKeepsOriginalAmount() {
        app.launch()
        home.waitForReady()
        home.todayCell.tap()
        home.expenseHistoryRow.tap()

        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        entry.amountField.tap()
        entry.amountField.typeText("7")
        entry.closeButton.tap()

        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(
            home.summaryAmount(.expense).waitForLabel(Fixture.expenseText),
            "저장하지 않은 변경은 반영되면 안 된다"
        )
    }

    // MARK: - 설정 진입 기반

    @MainActor
    func testSettingsRowsAreReachable() {
        app.launch()
        home.waitForReady()

        home.settingsButton.tap()

        XCTAssertTrue(settings.baseCurrencyRow.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(settings.languageRow.exists)
        // 회원탈퇴·로그아웃은 로그인 상태에서만 노출된다. UI 테스트는 익명 신원이라 여기서는 대상이 아니다.
        XCTAssertFalse(settings.withdrawRow.exists, "익명 상태에서는 회원탈퇴 행이 없어야 한다")
    }
}

// MARK: - 진단

extension WoniAppUITests {
    /// 이 step이 접근성에 노출한 선택 상태를 실제로 읽는다.
    /// 노출만 하고 아무도 읽지 않으면 나중에 조용히 사라져도 알 수 없다.
    @MainActor
    func testSelectionStatesAreExposedToAccessibility() {
        app.launch()
        home.waitForReady()

        runCase("today-cell-exposes-today-value") {
            XCTAssertTrue(home.todayCell.waitForExistence(timeout: Timeout.launch), "달력이 그려져야 한다")
            XCTAssertEqual(
                home.todayCell.value as? String,
                Fixture.todayAccessibilityValue,
                "오늘 셀은 원 배경 말고 접근성 값으로도 오늘임을 알려야 한다"
            )
        }

        home.todayCell.tap()
        home.expenseHistoryRow.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition), "수정 화면이 열려야 한다")

        runCase("chips-expose-saved-selection") {
            assertOnlySelectedChip(prefix: "entry.category.", expectedID: Fixture.expenseCategoryID)
            assertOnlySelectedChip(prefix: "entry.asset.", expectedID: Fixture.expenseAssetID)
        }

        runCase("tab-selection-moves") {
            XCTAssertTrue(entry.tab(.expense).isSelected, "지출 거래를 여는 중이므로 지출 탭이 선택돼 있어야 한다")
            XCTAssertFalse(entry.tab(.income).isSelected, "수입 탭은 선택돼 있으면 안 된다")

            entry.tab(.income).tap()

            XCTAssertTrue(entry.tab(.income).waitForSelected(), "탭한 수입 탭으로 선택이 옮겨져야 한다")
            XCTAssertFalse(entry.tab(.expense).isSelected, "이전 탭의 선택이 풀려야 한다")
        }

        runCase("inline-calendar-exposes-selected-day") {
            entry.dateRow.tap()

            let selectedDay = entry.calendarDay(TestClock.todayDay)
            XCTAssertTrue(selectedDay.waitForExistence(timeout: Timeout.transition), "인라인 달력이 펼쳐져야 한다")
            XCTAssertTrue(selectedDay.waitForSelected(), "인라인 달력에서 현재 날짜가 선택 상태로 노출돼야 한다")
        }
    }

    /// 같은 묶음에서 정확히 하나만 선택 상태여야 하고, 그것이 저장된 값이어야 한다.
    private func assertOnlySelectedChip(prefix: String, expectedID: Int) {
        let selected = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", prefix)
        )
        XCTAssertTrue(selected.waitForCount(1), "\(prefix) 칩은 하나만 선택 상태여야 한다")
        XCTAssertEqual(
            selected.element.identifier,
            "\(prefix)\(expectedID)",
            "저장된 값에 해당하는 칩이 선택돼 있어야 한다"
        )
    }

    /// 요소 식별자가 기대대로 노출되는지 확인하는 진단용 테스트. 실패 시 트리를 로그로 남긴다.
    @MainActor
    func testAccessibilityTreeExposesKnownIdentifiers() {
        app.launch()
        home.waitForReady()

        let tree = app.debugDescription
        for identifier in ["main.add", "main.settings", "main.monthTitle", "main.summary.expense"] {
            XCTAssertTrue(tree.contains(identifier), "식별자 \(identifier)가 트리에 없다\n\(tree)")
        }
    }
}

// MARK: - 고정값

private enum UITestFlags {
    static let enable = "-uiTest"
    static let seedLedger = "-uiTestSeedLedger"
}

private enum Timeout {
    static let launch: TimeInterval = 20
    static let transition: TimeInterval = 8
}

/// 앱의 `UITestSupport.Fixture`와 짝을 이루는 기대값. 한쪽만 바뀌면 테스트가 먼저 깨진다.
private enum Fixture {
    static let expenseText = "10,000"
    static let incomeText = "30,000"
    static let totalText = "20,000"
    /// 입력 필드는 표시용 콤마 없이 원시 숫자를 담는다.
    static let expenseFieldValue = "10000"
    /// 시드 지출이 쓰는 카테고리·자산. 수정 화면 진입 시 이 칩만 선택 상태여야 한다.
    static let expenseCategoryID = 1
    static let expenseAssetID = 1
    /// 언어를 `ko`로 고정해 실행하므로 오늘 셀의 접근성 값은 한국어다.
    static let todayAccessibilityValue = "오늘"
}

private enum SummaryKind: String {
    case expense
    case income
    case total
}

/// 앱은 거래 날짜를 Asia/Seoul 기준으로 다룬다(시드도 `ServerDateFormatter`로 같은 기준).
/// 테스트가 러너 로컬 타임존으로 "오늘"을 계산하면 KST 자정 전후 구간에서 하루가 어긋나므로 기준을 맞춘다.
private enum TestClock {
    static let seoulCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        if let seoul = TimeZone(identifier: "Asia/Seoul") {
            calendar.timeZone = seoul
        }
        return calendar
    }()

    static var todayDay: Int {
        seoulCalendar.component(.day, from: Date())
    }

    static var todayDayNumber: String {
        String(TestClock.todayDay)
    }

    /// 휠 픽커 한 칸 높이. 아래로 이 만큼 끌면 이전 항목이 선택된다.
    static let wheelRowHeight: CGFloat = 44

    static var currentYear: Int {
        seoulCalendar.component(.year, from: Date())
    }

    static var currentMonth: Int {
        seoulCalendar.component(.month, from: Date())
    }

    /// 주어진 날짜의 하루 뒤 "일". 월말이면 다음 달 1일이 된다.
    static func dayAfter(year: Int, month: Int, day: Int) -> Int? {
        let components = DateComponents(
            calendar: seoulCalendar,
            timeZone: seoulCalendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = seoulCalendar.date(from: components),
              let next = seoulCalendar.date(byAdding: .day, value: 1, to: date)
        else {
            return nil
        }
        return seoulCalendar.component(.day, from: next)
    }
}

// MARK: - Page Objects

private struct HomeScreen {
    let app: XCUIApplication

    var addButton: XCUIElement {
        app.buttons["main.add"]
    }

    var settingsButton: XCUIElement {
        app.buttons["main.settings"]
    }

    var monthTitle: XCUIElement {
        app.buttons["main.monthTitle"]
    }

    /// 히스토리 행은 지출·수입으로 식별자가 갈린다. 정렬 순서에 기대지 않도록 종류로 직접 집는다.
    var historyRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main.history.row"))
    }

    var expenseHistoryRow: XCUIElement {
        app.buttons["main.history.row.expense"].firstMatch
    }

    var incomeHistoryRow: XCUIElement {
        app.buttons["main.history.row.income"].firstMatch
    }

    var todayCell: XCUIElement {
        calendarDay(TestClock.todayDay)
    }

    func calendarDay(_ day: Int) -> XCUIElement {
        app.buttons["main.calendar.day.\(day)"]
    }

    func summaryAmount(_ kind: SummaryKind) -> XCUIElement {
        app.staticTexts["main.summary.\(kind.rawValue)"]
    }

    func waitForReady() {
        XCTAssertTrue(addButton.waitForExistence(timeout: Timeout.launch), "홈이 뜨지 않았다")
    }
}

private struct EntryScreen {
    let app: XCUIApplication

    var amountField: XCUIElement {
        app.textFields["entry.amount"]
    }

    var memoField: XCUIElement {
        app.textFields["entry.memo"]
    }

    var currencyButton: XCUIElement {
        app.buttons["entry.currency"]
    }

    var dateRow: XCUIElement {
        app.buttons["entry.date"]
    }

    var submitButton: XCUIElement {
        app.buttons["entry.submit"]
    }

    var closeButton: XCUIElement {
        app.buttons["entry.close"]
    }

    var deleteButton: XCUIElement {
        app.buttons["entry.delete"]
    }

    var deleteConfirmButton: XCUIElement {
        app.buttons["entry.deleteDialog.confirm"]
    }

    var nextDateButton: XCUIElement {
        app.buttons["entry.date.next"]
    }

    var yearMonthPickerSave: XCUIElement {
        app.buttons["yearMonthPicker.save"]
    }

    /// 휠 항목은 값 텍스트로만 잡을 수 있다. 언어는 `ko`로 고정해 실행한다.
    func yearWheelRow(_ year: Int) -> XCUIElement {
        app.staticTexts["\(year)년"]
    }

    /// 피커 상단 타이틀. 휠을 돌린 결과가 반영됐는지 확인하는 용도다.
    func pickerTitle(year: Int, month: Int) -> XCUIElement {
        app.staticTexts["\(year)년 \(month)월"]
    }

    /// 인라인 달력에서 현재 선택된 날짜. 없으면 nil.
    func selectedCalendarDay() -> Int? {
        let selected = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "entry.calendar.day.")
        ).firstMatch
        guard selected.waitForExistence(timeout: Timeout.transition) else {
            return nil
        }
        return Int(selected.identifier.replacingOccurrences(of: "entry.calendar.day.", with: ""))
    }

    func tab(_ kind: EntryTabKind) -> XCUIElement {
        app.buttons["entry.tab.\(kind.rawValue)"]
    }

    func categoryChip(_ id: Int) -> XCUIElement {
        app.buttons["entry.category.\(id)"]
    }

    func assetChip(_ id: Int) -> XCUIElement {
        app.buttons["entry.asset.\(id)"]
    }

    /// 인라인 달력은 `entry.date` 행을 탭해야 펼쳐진다.
    func calendarDay(_ day: Int) -> XCUIElement {
        app.buttons["entry.calendar.day.\(day)"]
    }
}

private enum EntryTabKind: String {
    case expense
    case income
}

private struct SettingsScreen {
    let app: XCUIApplication

    var baseCurrencyRow: XCUIElement {
        app.buttons["settings.row.baseCurrency"]
    }

    var languageRow: XCUIElement {
        app.buttons["settings.row.language"]
    }

    var withdrawRow: XCUIElement {
        app.buttons["settings.row.withdraw"]
    }
}

// MARK: - 대기 및 진단

private extension XCUIElement {
    func dragVertically(by offset: CGFloat) {
        let center = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(
            forDuration: 0.1,
            thenDragTo: center.withOffset(CGVector(dx: 0, dy: offset)),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    func waitForLabel(_ expectedLabel: String, timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "label == %@", expectedLabel), timeout: timeout)
    }

    func waitForNonExistence(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "exists == false"), timeout: timeout)
    }

    func waitForSelected(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "selected == true"), timeout: timeout)
    }

    func wait(for predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

private extension XCUIElementQuery {
    func waitForCount(_ expectedCount: Int, timeout: TimeInterval = Timeout.transition) -> Bool {
        let predicate = NSPredicate(format: "count == %d", expectedCount)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
