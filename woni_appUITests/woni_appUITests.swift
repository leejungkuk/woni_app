//
//  woni_appUITests.swift
//  woni_appUITests
//
//  Created by J on 6/2/26.
//

import XCTest

/// 기기 검증이 유일한 검증 수단인 케이스(cov: dev)와 P1 사용자 흐름을 자동화한다.
/// 앱은 `-uiTest` 훅으로 in-memory DB + Fake 인증에 붙으므로 실행 간 상태가 남지 않는다.
final class WoniAppUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
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
        app = nil
    }

    // MARK: - A1 · B6 · B9 — 콜드 스타트와 합계

    @MainActor
    func testHomeShowsSeededTotalsOnColdStart() {
        app.launch()

        XCTAssertTrue(
            app.summaryAmount(.expense).waitForExistence(timeout: Timeout.launch),
            "홈이 열리지 않았다"
        )
        XCTAssertEqual(app.summaryAmount(.expense).label, Fixture.expenseText)
        XCTAssertEqual(app.summaryAmount(.income).label, Fixture.incomeText)
        XCTAssertEqual(app.summaryAmount(.total).label, Fixture.totalText)
    }

    // MARK: - B7 — 선택일 내역

    @MainActor
    func testSelectingTodayShowsOnlyThatDaysEntries() {
        app.launch()
        app.waitForHome()

        app.todayCell.tap()

        XCTAssertEqual(
            app.historyRows.count,
            2,
            "시드가 넣은 오늘 거래 2건이 그대로 보여야 한다"
        )
    }

    // MARK: - B14 · C1 — 추가 진입

    @MainActor
    func testAddButtonOpensEntryFocusedOnAmount() {
        app.launch()
        app.waitForHome()

        app.addButton.tap()

        XCTAssertTrue(app.amountField.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "키패드가 즉시 떠야 한다")
        XCTAssertTrue(app.dateRow.label.contains(Self.todayDayNumber), "기본 날짜가 오늘이어야 한다")
    }

    // MARK: - C20 — 저장 후 홈 반영

    @MainActor
    func testSavingExpenseUpdatesHomeImmediately() {
        app.launch()
        app.waitForHome()

        app.addButton.tap()
        XCTAssertTrue(app.amountField.waitForExistence(timeout: Timeout.transition))
        // 신규 진입은 금액 필드가 자동 포커스된다. 여기서 tap하면 포커스가 오히려 풀린다.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition))
        app.typeText("5000")
        app.submitButton.tap()

        XCTAssertTrue(app.addButton.waitForExistence(timeout: Timeout.transition), "저장 후 홈으로 돌아와야 한다")
        XCTAssertEqual(
            app.summaryAmount(.expense).label,
            "15,000",
            "지출 합계가 새로고침 없이 갱신돼야 한다"
        )
    }

    // MARK: - B13 · D1 — 수정 진입 프리필

    @MainActor
    func testTappingHistoryRowPrefillsEditor() {
        app.launch()
        app.waitForHome()
        app.todayCell.tap()

        app.expenseHistoryRow.tap()

        XCTAssertTrue(app.amountField.waitForExistence(timeout: Timeout.transition))
        XCTAssertEqual(app.amountField.value as? String, Fixture.expenseFieldValue)
        XCTAssertTrue(app.deleteButton.exists, "수정 화면에는 삭제 버튼이 있어야 한다")
    }

    // MARK: - D7 — 삭제 반영

    @MainActor
    func testDeletingEntryRemovesItFromTotals() {
        app.launch()
        app.waitForHome()
        app.todayCell.tap()
        app.expenseHistoryRow.tap()

        XCTAssertTrue(app.deleteButton.waitForExistence(timeout: Timeout.transition))
        app.deleteButton.tap()
        app.deleteConfirmButton.tap()

        XCTAssertTrue(app.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertEqual(app.summaryAmount(.expense).label, "0", "삭제한 지출이 합계에서 빠져야 한다")
    }

    // MARK: - D9 — 저장하지 않고 나가면 미반영

    @MainActor
    func testLeavingEditorWithoutSavingKeepsOriginalAmount() {
        app.launch()
        app.waitForHome()
        app.todayCell.tap()
        app.expenseHistoryRow.tap()

        XCTAssertTrue(app.amountField.waitForExistence(timeout: Timeout.transition))
        app.amountField.tap()
        app.amountField.typeText("7")
        app.closeButton.tap()

        XCTAssertTrue(app.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertEqual(app.summaryAmount(.expense).label, Fixture.expenseText, "저장하지 않은 변경은 반영되면 안 된다")
    }

    // MARK: - J1~J6 — 설정 진입

    @MainActor
    func testSettingsRowsAreReachable() {
        app.launch()
        app.waitForHome()

        app.settingsButton.tap()

        XCTAssertTrue(
            app.buttons["settings.row.baseCurrency"].waitForExistence(timeout: Timeout.transition)
        )
        XCTAssertTrue(app.buttons["settings.row.language"].exists)
        // 회원탈퇴·로그아웃은 로그인 상태에서만 노출된다. UI 테스트는 익명 신원이라 여기서는 대상이 아니다.
        XCTAssertFalse(app.buttons["settings.row.withdraw"].exists, "익명 상태에서는 회원탈퇴 행이 없어야 한다")
    }
}

// MARK: - 진단

extension WoniAppUITests {
    /// 요소 식별자가 기대대로 노출되는지 확인하는 진단용 테스트. 실패 시 트리를 로그로 남긴다.
    @MainActor
    func testAccessibilityTreeExposesKnownIdentifiers() {
        app.launch()
        app.waitForHome()

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
}

private extension WoniAppUITests {
    static var todayDayNumber: String {
        String(TestClock.todayDay)
    }
}

// MARK: - 화면 접근자

private extension XCUIApplication {
    var addButton: XCUIElement {
        buttons["main.add"]
    }

    var settingsButton: XCUIElement {
        buttons["main.settings"]
    }

    var monthTitle: XCUIElement {
        buttons["main.monthTitle"]
    }

    var amountField: XCUIElement {
        textFields["entry.amount"]
    }

    var memoField: XCUIElement {
        textFields["entry.memo"]
    }

    var currencyButton: XCUIElement {
        buttons["entry.currency"]
    }

    var dateRow: XCUIElement {
        buttons["entry.date"]
    }

    var submitButton: XCUIElement {
        buttons["entry.submit"]
    }

    var closeButton: XCUIElement {
        buttons["entry.close"]
    }

    var deleteButton: XCUIElement {
        buttons["entry.delete"]
    }

    var deleteConfirmButton: XCUIElement {
        buttons["entry.deleteDialog.confirm"]
    }

    /// 히스토리 행은 지출·수입으로 식별자가 갈린다. 정렬 순서에 기대지 않도록 종류로 직접 집는다.
    var historyRows: XCUIElementQuery {
        buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main.history.row"))
    }

    var expenseHistoryRow: XCUIElement {
        buttons["main.history.row.expense"].firstMatch
    }

    var incomeHistoryRow: XCUIElement {
        buttons["main.history.row.income"].firstMatch
    }

    var todayCell: XCUIElement {
        buttons["main.calendar.day.\(TestClock.todayDay)"]
    }

    func summaryAmount(_ kind: SummaryKind) -> XCUIElement {
        staticTexts["main.summary.\(kind.rawValue)"]
    }

    func waitForHome() {
        XCTAssertTrue(addButton.waitForExistence(timeout: Timeout.launch), "홈이 뜨지 않았다")
    }
}
