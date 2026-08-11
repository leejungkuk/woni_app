//
//  woni_appUITests.swift
//  woni_appUITests
//
//  Created by J on 6/2/26.
//

import UIKit
import XCTest

// Step별 UI 테스트를 한 타깃 파일에 유지해 pbxproj 변경을 피한다.

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
                home.summaryAmount(.income).waitForLabel(Fixture.monthlyIncomeText),
                "수입 합계가 \(Fixture.monthlyIncomeText)여야 한다 (실제: \(home.summaryAmount(.income).label))"
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

    // MARK: - 설정 진입 기반

    @MainActor
    func testSettingsRowsAreReachable() {
        app.launch()
        home.waitForReady()

        home.settingsButton.tap()

        XCTAssertTrue(settings.baseCurrencyRow.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(settings.languageRow.exists)
        // 삭제 진입점은 회원·비회원 공통이고 제목만 갈린다. UI 테스트는 익명 신원이라 비회원 제목이어야 한다.
        XCTAssertTrue(settings.withdrawRow.exists, "익명 상태에도 삭제 행이 있어야 한다")
        XCTAssertEqual(settings.withdrawRow.label, WithdrawalFixture.guestRowTitle)
    }
}

// MARK: - 입력 화면 공통

class EntryUITestCase: WoniAppUITestCase {
    fileprivate var home: HomeScreen {
        HomeScreen(app: app)
    }

    fileprivate var entry: EntryScreen {
        EntryScreen(app: app)
    }

    func launch(
        seedLedger: Bool = false,
        baseCurrency: String = "KRW",
        language: String = "ko",
        extraArguments: [String] = []
    ) {
        app.launchArguments = [
            UITestFlags.enable,
            "-woni.app.baseCurrency", baseCurrency,
            "-woni.app.language.override", language,
            "-woni.app.lastUsedCurrency", "KRW"
        ] + extraArguments
        if seedLedger {
            app.launchArguments.append(UITestFlags.seedLedger)
        }
        app.launch()
        home.waitForReady()
    }

    func openNewEntry() {
        home.addButton.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition), "신규 입력 화면이 열려야 한다")
    }

    func openSeededExpense() {
        home.todayCell.tap()
        XCTAssertTrue(home.todayCell.waitForSelected(), "오늘 날짜가 선택돼야 한다")
        XCTAssertTrue(home.expenseHistoryRow.waitForExistence(timeout: Timeout.transition), "시드 지출 행이 보여야 한다")
        home.expenseHistoryRow.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition), "수정 화면이 열려야 한다")
    }

    func typeAmount(_ text: String) {
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        if !app.keyboards.element.exists {
            entry.amountField.tap()
        }
        app.typeText(text)
    }

    func replaceAmount(with text: String) {
        entry.amountField.tap()
        entry.amountField.typeKey("a", modifierFlags: .command)
        entry.amountField.typeText(XCUIKeyboardKey.delete.rawValue)
        if !text.isEmpty {
            entry.amountField.typeText(text)
        }
    }

    func selectCurrency(label: String, code: String) {
        let currencyOrder = [
            "KRW", "JPY", "THB", "CNY", "HKD", "SGD", "IDR",
            "MYR", "USD", "EUR", "AUD", "NZD", "GBP"
        ]
        let currentCode = entry.currencyButton.label
        // 목록에서 현재 통화보다 위에 있으면 아래로 끌어 내리고, 그 외에는 위로 끌어 올린다.
        // 다중행 조건을 대입문에 붙이면 SwiftFormat(중괄호 내림)과 SwiftLint(중괄호 올림)가 충돌한다.
        let currentIndex = currencyOrder.firstIndex(of: currentCode) ?? currencyOrder.count
        let targetIndex = currencyOrder.firstIndex(of: code) ?? currencyOrder.count
        let dragOffset: CGFloat = targetIndex < currentIndex ? 220 : -220
        entry.currencyButton.tap()
        let option = entry.currencyOption(label)
        XCTAssertTrue(option.waitForExistence(timeout: Timeout.transition), "통화 옵션 \(label)이 보여야 한다")
        for _ in 0 ..< 4 where !option.isHittable {
            let scroll = entry.currencyPickerScroll
            let startY = dragOffset > 0 ? 0.25 : 0.75
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            start.press(
                forDuration: 0.05,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: dragOffset)),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
        }
        XCTAssertTrue(option.waitForHittable(), "통화 옵션 \(label)을 시트 안에서 스크롤해 탭할 수 있어야 한다")
        option.tap()
        XCTAssertTrue(entry.currencyButton.waitForLabel(code), "선택 통화가 \(code)로 바뀌어야 한다")
    }

    /// 환율 라벨에 **양수 숫자**가 실제로 붙었는지 확인한다.
    ///
    /// 접두(`KRW 1.00 = USD `)만 보면 뒤가 비어도 통과하고, 정규식으로 숫자만 확인하면
    /// `0`도 통과한다. 환율 0은 환산액을 전부 0으로 만드는 실패이므로 값까지 판정한다.
    func assertRateLabelHasPositiveNumber(
        _ element: XCUIElement,
        prefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let label = element.label
        let digits = label
            .replacingOccurrences(of: prefix, with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(digits) else {
            return XCTFail("환율 라벨에 숫자가 붙어야 한다 (실제: \(label))", file: file, line: line)
        }
        XCTAssertGreaterThan(value, 0, "환율이 0이면 안 된다 (실제: \(label))", file: file, line: line)
    }

    /// 입력 폼을 위로 끌어 올린다.
    ///
    /// `swipeUp()` 편의 API는 쓸 수 없다. 계측 결과 키보드가 떠 있는 동안 이 화면에서는
    /// 스크롤 오프셋을 전혀 움직이지 못한다(메모 y좌표가 3회 연속 그대로였다).
    /// 같은 상황에서 명시적 press-drag는 250pt를 정상 스크롤하므로 앱이 아니라 편의 API 쪽 문제다.
    func dragFormUp() {
        let start = entry.formScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: 0, dy: -260)),
            withVelocity: .slow,
            thenHoldForDuration: 0.2
        )
    }

    func revealMemoField() {
        for _ in 0 ..< 3 where !entry.memoField.isHittable {
            dragFormUp()
        }
        XCTAssertTrue(entry.memoField.waitForHittable(), "메모 필드를 화면 안으로 스크롤할 수 있어야 한다")
    }

    /// 카테고리·자산은 자동 선택되지 않으므로, 저장까지 가는 흐름은 두 칩을 직접 고른다.
    ///
    /// `openNewEntry()`에 넣지 않는다 — 저장까지 가지 않는 다수의 케이스(즉시 포커스·키보드 전제·
    /// 초기 미선택 검증)가 오염된다.
    /// `revealMemoField()`와 같이 **폼을 아래로 끌어 올린 뒤에는 호출하지 않는다**. 칩이 위로 밀려나
    /// `dragFormUp`으로 되찾을 수 없다(메모 조작보다 **먼저** 부른다).
    func selectRequiredEntryFields(categoryId: Int = 1, assetId: Int = 1) {
        selectChip(entry.categoryChip(categoryId), name: "카테고리 \(categoryId)")
        selectChip(entry.assetChip(assetId), name: "자산 \(assetId)")
    }

    private func selectChip(_ chip: XCUIElement, name: String) {
        XCTAssertTrue(chip.waitForExistence(timeout: Timeout.transition), "\(name) 칩이 있어야 한다")
        for _ in 0 ..< 3 where !chip.isHittable {
            dragFormUp()
        }
        XCTAssertTrue(chip.waitForHittable(), "\(name) 칩을 화면 안으로 스크롤할 수 있어야 한다")
        chip.tap()
        XCTAssertTrue(chip.waitForSelected(), "\(name) 칩이 선택돼야 한다")
    }

    func replaceMemo(with text: String) {
        revealMemoField()
        entry.memoField.tap()
        entry.memoField.typeKey("a", modifierFlags: .command)
        entry.memoField.typeText(XCUIKeyboardKey.delete.rawValue)
        if !text.isEmpty {
            entry.memoField.typeText(text)
        }
    }

    /// 연월 피커에서 목표 연·월까지 휠을 **한 칸씩** 옮긴다.
    ///
    /// 여러 칸을 한 번에 끌면 관성으로 어긋나므로, 매 칸마다 피커 타이틀로 착지를 확인한다.
    /// 실패해도 어느 칸에서 어긋났는지 메시지에 남는다.
    fileprivate func pickYearMonth(from current: YearMonth, to target: YearMonth) {
        var cursor = current
        var steps = 0
        while cursor != target, steps < 36 {
            steps += 1
            let next = cursor.stepped(toward: target)
            if next.year != cursor.year {
                entry.yearWheelRow(cursor.year)
                    .dragVertically(by: next.year < cursor.year ? TestClock.wheelRowHeight : -TestClock.wheelRowHeight)
            } else {
                entry.monthWheelRow(cursor.month)
                    .dragVertically(by: next.month < cursor.month ? TestClock.wheelRowHeight : -TestClock
                        .wheelRowHeight)
            }
            cursor = next
            XCTAssertTrue(
                entry.pickerTitle(year: cursor.year, month: cursor.month).waitForExistence(timeout: Timeout.transition),
                "휠을 한 칸 옮기면 \(cursor.year)년 \(cursor.month)월이 돼야 한다"
            )
        }
        XCTAssertEqual(cursor, target, "목표 연·월까지 휠을 옮기지 못했다")
    }

    /// 홈 달력을 목표 연·월로 옮긴다. 스와이프는 거리·속도를 보장하지 않아 월 이동 판정이 흔들리므로 피커를 쓴다.
    fileprivate func setHomeMonth(to target: YearMonth) {
        setHomeMonth(from: YearMonth(date: TestClock.today), to: target)
    }

    fileprivate func setHomeMonth(from current: YearMonth, to target: YearMonth) {
        guard current != target else {
            return
        }
        home.monthTitle.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForExistence(timeout: Timeout.transition), "홈 연월 피커가 열려야 한다")
        pickYearMonth(from: current, to: target)
        entry.yearMonthPickerSave.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForNonExistence(), "저장 후 피커가 닫혀야 한다")
    }

    /// 입력 화면의 날짜를 목표 날짜로 옮긴다. 인라인 달력 → 연월 피커 → 날짜 선택 순서다.
    /// 피커 저장 후 좌우 화살표를 누르지 않으므로 결함 D-001 경로를 타지 않는다.
    fileprivate func setEntryDate(to target: Date) {
        entry.dateRow.tap()
        XCTAssertTrue(entry.calendarDay(TestClock.todayDay).waitForExistence(timeout: Timeout.transition))
        entry.dateRow.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForExistence(timeout: Timeout.transition))
        pickYearMonth(from: YearMonth(date: TestClock.today), to: YearMonth(date: target))
        entry.yearMonthPickerSave.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForNonExistence())

        let day = TestClock.seoulCalendar.component(.day, from: target)
        XCTAssertTrue(entry.calendarDay(day).waitForExistence(timeout: Timeout.transition))
        entry.calendarDay(day).tap()
        XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.fullDate(for: target)))
    }

    func assertSavedEntryVisible(on date: Date, expectedRows: Int = 1) {
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition), "저장 후 홈으로 돌아와야 한다")
        setHomeMonth(to: YearMonth(date: date))
        XCTAssertTrue(
            home.monthTitle.waitForLabel(TestClock.monthTitle(for: date)),
            "저장 날짜가 속한 달로 이동해야 한다 (실제: \(home.monthTitle.label))"
        )
        let day = TestClock.seoulCalendar.component(.day, from: date)
        XCTAssertTrue(home.calendarDay(day).waitForExistence(timeout: Timeout.transition), "저장 날짜 셀이 그려져야 한다")
        home.calendarDay(day).tap()
        XCTAssertTrue(home.calendarDay(day).waitForSelected(), "저장 날짜가 선택돼야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(expectedRows), "저장된 거래가 해당 날짜 내역에 보여야 한다")
    }
}

// MARK: - Step 4 · EntryFlowUITests

final class EntryFlowUITests: EntryUITestCase {
    @MainActor
    func testC1NewEntryFocusesAmountImmediately() {
        launch()
        openNewEntry()

        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "추가 탭 없이 키패드가 떠야 한다")
        XCTAssertTrue(entry.amountField.waitForKeyboardFocus(), "금액 필드가 즉시 포커스를 가져야 한다")
    }

    /// 원장 B14의 전제는 **당월이 아닌 날짜**다. 당월 안에서만 고르면 "오늘로 되돌아간다"는 결함을 놓친다.
    @MainActor
    func testB14AddUsesSelectedDateFromAnotherMonth() {
        launch()
        let selectedDate = TestClock.dayInMonthsAgo(2)
        let day = TestClock.seoulCalendar.component(.day, from: selectedDate)

        setHomeMonth(to: YearMonth(date: selectedDate))
        XCTAssertTrue(
            home.monthTitle.waitForLabel(TestClock.monthTitle(for: selectedDate)),
            "두 달 전으로 이동해야 한다 (실제: \(home.monthTitle.label))"
        )
        home.calendarDay(day).tap()
        XCTAssertTrue(home.calendarDay(day).waitForSelected(), "추가할 날짜를 먼저 선택해야 한다")

        openNewEntry()

        XCTAssertEqual(
            entry.dateRow.label,
            TestClock.fullDate(for: selectedDate),
            "추가 화면은 홈의 선택일을 그대로 써야 한다. 오늘로 되돌아가면 안 된다"
        )
    }

    @MainActor
    func testNewEntryDraftIsDiscardedAfterClosing() {
        launch()
        openNewEntry()
        typeAmount("4321")
        replaceMemo(with: "미저장 초안")

        entry.closeButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        openNewEntry()

        XCTAssertEqual(entry.amountField.value as? String, "", "미저장 금액 초안이 남으면 안 된다")
        revealMemoField()
        // `!=` 로는 초안 일부가 남은 경우를 잡지 못한다. 빈 TextField가 노출하는 placeholder와 정확히 같아야 한다.
        XCTAssertEqual(entry.memoField.value as? String, Fixture.memoPlaceholder, "미저장 메모 초안이 남으면 안 된다")
    }

    @MainActor
    func testC20SavingNewExpenseUpdatesHomeImmediately() {
        launch()
        openNewEntry()
        typeAmount("5000")
        selectRequiredEntryFields()
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("5,000"), "지출 합계가 즉시 5,000으로 갱신돼야 한다")
        XCTAssertTrue(home.expenseHistoryRow.label.contains("5,000"), "내역 행에 저장 금액이 보여야 한다")
        XCTAssertTrue(home.todayCell.label.contains("5,000"), "달력 셀에 저장 금액 표식이 보여야 한다")
    }

    @MainActor
    func testC21RapidSaveTapsCreateOnlyOneEntry() {
        launch()
        openNewEntry()
        typeAmount("7000")
        selectRequiredEntryFields()

        entry.submitButton.doubleTap()

        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("7,000"), "중복 탭이어도 한 건만 합산돼야 한다")
        XCTAssertEqual(home.historyRows.count, 1, "저장 연타로 거래가 중복 생성되면 안 된다")
    }

    @MainActor
    func testB13AndD1HistoryRowOpensFullyPrefilledEditor() {
        launch(seedLedger: true)

        runCase("B13 history-row-opens-editor") {
            openSeededExpense()
        }
        runCase("D1 editor-prefills-all-values") {
            XCTAssertEqual(entry.amountField.value as? String, "10000")
            XCTAssertEqual(entry.currencyButton.label, "KRW")
            XCTAssertEqual(entry.dateRow.label, TestClock.fullDate(for: TestClock.today))
            XCTAssertTrue(entry.categoryChip(1).waitForSelected(), "저장된 식비가 선택돼야 한다")
            XCTAssertTrue(entry.assetChip(1).waitForSelected(), "저장된 신용카드가 선택돼야 한다")
            revealMemoField()
            XCTAssertEqual(entry.memoField.value as? String, "UITestExpense")
            XCTAssertTrue(entry.deleteButton.exists, "수정 화면에는 삭제 버튼이 있어야 한다")
        }
    }

    @MainActor
    func testD2EditingAmountUpdatesExistingEntry() {
        launch(seedLedger: true)
        openSeededExpense()
        replaceAmount(with: "12500")

        entry.submitButton.tap()

        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("12,500"), "수정 금액으로 합계가 갱신돼야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(2), "수정이 신규 거래를 만들면 안 된다")
        XCTAssertTrue(home.expenseHistoryRow.label.contains("12,500"), "내역에 수정 금액이 보여야 한다")
    }

    @MainActor
    func testD3EditingCurrencyUpdatesRateAndConvertedAmount() {
        launch(seedLedger: true)
        openSeededExpense()
        selectCurrency(label: "미국, USD", code: "USD")

        // 접두만 보면 환율 숫자가 비어도 통과한다. 실제 양수 숫자가 붙었는지까지 확인한다.
        let rateElement = entry.rateLabel(prefix: "KRW 1.00 = USD ")
        XCTAssertTrue(rateElement.waitForExistence(timeout: Timeout.transition), "USD 환율이 표시돼야 한다")
        assertRateLabelHasPositiveNumber(rateElement, prefix: "KRW 1.00 = USD ")

        // 환산액을 상수로 박으면 시드 환율이 정상 갱신되기만 해도 앱 회귀 없이 깨진다.
        // 대신 편집기가 보여준 환산액과 홈 합계가 일치하는지 **서로 다른 두 화면**으로 교차 확인한다.
        // 다만 두 값이 같은 `currentQuote.tts`에서 나오므로 이 테스트가 검증하는 것은
        // "환율 값의 정확성"이 아니라 **전파의 일관성**이다. 값 고정 검증은 환율 fixture를 다루는 step 6 몫이다.
        guard let convertedAmount = entry.convertedAmountText() else {
            return XCTFail("통화를 바꾸면 환산액이 표시돼야 한다")
        }
        XCTAssertNotEqual(convertedAmount, Fixture.expenseText, "USD로 바꿨으면 환산액이 원래 KRW 금액과 달라야 한다")

        entry.submitButton.tap()

        XCTAssertTrue(
            home.summaryAmount(.expense).waitForLabel(convertedAmount),
            "저장 후 홈 합계가 편집기 환산액(\(convertedAmount))과 같아야 한다"
        )
        XCTAssertTrue(home.expenseHistoryRow.label.contains("USD 10,000.00"), "내역에 수정한 원 통화 금액이 보여야 한다")
    }

    @MainActor
    func testD5EditingCategoryAndAssetUpdatesHistory() {
        launch(seedLedger: true)
        openSeededExpense()
        entry.categoryChip(2).tap()
        XCTAssertTrue(entry.categoryChip(2).waitForSelected())
        entry.assetChip(2).tap()
        XCTAssertTrue(entry.assetChip(2).waitForSelected())

        entry.submitButton.tap()

        XCTAssertTrue(home.expenseHistoryRow.waitForLabelContaining("카페/음료"), "새 카테고리가 내역에 보여야 한다")
        XCTAssertTrue(home.expenseHistoryRow.label.contains("체크카드"), "새 자산이 내역에 보여야 한다")
    }

    @MainActor
    func testD6EditingThenClearingMemoPersistsBothChanges() {
        launch(seedLedger: true)
        openSeededExpense()
        replaceMemo(with: "수정 메모")
        entry.submitButton.tap()

        XCTAssertTrue(home.expenseHistoryRow.waitForLabelContaining("수정 메모"), "수정한 메모가 내역에 보여야 한다")
        home.expenseHistoryRow.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        replaceMemo(with: "")
        XCTAssertTrue(entry.memoField.waitForValueNotEqual(to: "수정 메모"), "메모 입력값이 실제로 비워져야 한다")
        entry.submitButton.tap()

        XCTAssertTrue(home.expenseHistoryRow.waitForLabelPrefix("메모,"), "빈 메모는 fallback 제목으로 보여야 한다")
        XCTAssertFalse(home.expenseHistoryRow.label.contains("수정 메모"), "비운 메모가 되살아나면 안 된다")
    }

    @MainActor
    func testD7DeletingEntryUpdatesListTotalAndCalendar() {
        launch(seedLedger: true)
        openSeededExpense()
        entry.deleteButton.tap()
        XCTAssertTrue(entry.deleteConfirmButton.waitForExistence(timeout: Timeout.transition), "삭제 확인이 떠야 한다")
        entry.deleteConfirmButton.tap()

        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "삭제 거래가 합계에서 빠져야 한다")
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "main.history.row.expense.")
            ).waitForCount(0),
            "삭제 거래가 내역에서 사라져야 한다"
        )
        // 셀이 아직 안 그려졌으면 label이 빈 문자열이라 `contains`가 그냥 거짓이 된다.
        // "표식이 사라졌다"와 "달력이 없다"를 구분하려면 셀 존재부터 못박아야 한다.
        XCTAssertTrue(home.todayCell.waitForExistence(timeout: Timeout.transition), "삭제 후에도 오늘 셀은 남아야 한다")
        XCTAssertTrue(
            home.todayCell.waitForLabelNotContaining(Fixture.expenseText),
            "삭제 거래의 달력 표식이 사라져야 한다 (실제: \(home.todayCell.label))"
        )
    }

    /// 원장 D8은 "한 번만 처리"를 기대하지만, 삭제는 멱등이라(`DELETE` + `INSERT OR IGNORE`)
    /// 두 번 호출돼도 결과가 같다 — **블랙박스로는 요청 횟수를 구분할 수 없다.**
    /// 그래서 이 테스트가 검증하는 것은 횟수가 아니라 **연타 후 결과 상태의 일관성**이다.
    /// 횟수 보장은 `AddExpenseViewModelTests`의 `isDeleting` 가드 테스트가 담당한다(원장 「자동화 커버리지 한계」 참조).
    @MainActor
    func testD8RapidDeleteTapsKeepStateConsistent() {
        launch(seedLedger: true)
        openSeededExpense()
        entry.deleteButton.tap()
        XCTAssertTrue(entry.deleteConfirmButton.waitForExistence(timeout: Timeout.transition))

        entry.deleteConfirmButton.doubleTap()

        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition), "삭제 연타 뒤에도 홈으로 돌아와야 한다")
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "삭제는 한 번만 반영돼야 한다")

        // 삭제 실패 안내는 **입력 화면** 소속이다. 홈으로 돌아온 이 시점에서 alert 부재 단언은 절대 실패하지 않는다.
        // 대신 "지출만 지워지고 수입은 남았다"는 관측 가능한 상태로 두 번째 삭제가 없었음을 확인한다.
        XCTAssertTrue(home.historyRows.waitForCount(1), "지출 1건만 지워지고 수입 1건은 남아야 한다")
        XCTAssertTrue(home.incomeHistoryRow.exists, "남은 행은 시드 수입이어야 한다")
        XCTAssertTrue(home.summaryAmount(.income).waitForLabel(Fixture.monthlyIncomeText), "수입 합계는 그대로여야 한다")
    }

    @MainActor
    func testD9LeavingEditorRestoresOriginalValueOnReentry() {
        launch(seedLedger: true)
        openSeededExpense()
        replaceAmount(with: "17777")
        replaceMemo(with: "미저장 수정")
        entry.closeButton.tap()

        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("10,000"), "미저장 변경이 홈 합계에 반영되면 안 된다")
        home.expenseHistoryRow.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        XCTAssertEqual(entry.amountField.value as? String, "10000", "재진입한 편집기 금액은 원본이어야 한다")
        revealMemoField()
        XCTAssertEqual(entry.memoField.value as? String, "UITestExpense", "재진입한 편집기 메모는 원본이어야 한다")
    }
}

// MARK: - Step 4 · EntryValidationUITests

final class EntryValidationUITests: EntryUITestCase {
    /// 원장 C7: "1000.5 입력 시도 → 저장 / 소수 입력이 차단되거나 저장이 거부된다. 반올림해서 몰래 저장되지 않는다."
    /// 입력 값과 저장 결과로 판정한다 — 키패드 구성으로는 통화별 자릿수 정책을 가릴 수 없다(아래 주석 참조).
    @MainActor
    func testC7ZeroDecimalCurrencyRejectsFractionInput() {
        launch()
        openNewEntry()

        XCTAssertEqual(entry.currencyButton.label, "KRW")
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "금액 키패드가 떠야 한다")

        // 키패드에 소수점 키가 없는지 보는 단언은 쓸 수 없다 — `AmountInputSection`이 통화와 무관하게
        // 항상 `.numberPad`를 쓰므로 2자리 통화에서도 똑같이 통과해 **0자리 통화를 구분하지 못한다.**
        // 대신 같은 키스트로크가 통화에 따라 다르게 해석되는지로 자릿수 정책을 가른다.
        typeAmount("1000.5")

        // 소수 입력이 차단되므로 소수점은 버려지고 숫자만 남는다.
        XCTAssertEqual(entry.amountField.value as? String, "10005", "0자리 통화에서 소수 입력은 차단돼야 한다")
        selectRequiredEntryFields()
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.today)
        // 1,000 이나 1,001 이면 소수를 몰래 반올림·절삭해 저장했다는 뜻이다.
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("10,005"), "입력한 숫자 그대로 저장돼야 한다")
    }

    /// C7의 대비군. 같은 키스트로크가 2자리 통화에서는 소수로 해석되는지 확인해
    /// "0자리 통화라서 소수가 안 들어간다"가 실제로 통화별 정책임을 증명한다.
    ///
    /// 한 글자씩 넣고 매번 값을 확인한다. 한 번에 몰아 넣으면 결함 D-003(아래 재현 테스트)에 걸려
    /// 통화 정책이 아니라 입력 경합을 측정하게 된다.
    @MainActor
    func testC7SameKeystrokesBecomeFractionOnTwoDecimalCurrency() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")

        typeAmount("1")
        XCTAssertTrue(entry.amountField.waitForValue("0.01"))
        app.typeText("0")
        XCTAssertTrue(entry.amountField.waitForValue("0.10"))
        app.typeText("0")
        XCTAssertTrue(entry.amountField.waitForValue("1.00"))
        app.typeText("0")
        XCTAssertTrue(entry.amountField.waitForValue("10.00"))
        app.typeText("5")

        XCTAssertTrue(
            entry.amountField.waitForValue("100.05"),
            "2자리 통화에서는 같은 키스트로크가 소수로 해석돼야 한다 (실제: \(entry.amountField.value as? String ?? "nil"))"
        )
    }

    /// 결함 D-003 재현 — 2자리 통화에서 숫자를 연속으로 빠르게 넣으면 소수부가 2자리를 넘는다.
    ///
    /// 관측: `10005`를 몰아 넣으면 `100.05`가 아니라 `1.0005`·`10.005`가 된다(5회 중 4회).
    /// 소수점 위치가 고정된 채 뒤 문자가 그대로 붙는 형태로, cents-first 재동기화가 입력 속도를 못 따라간다.
    /// **금액이 100배 어긋날 수 있어** 백로그에 기록했다(`.claude/docs/defect-backlog.md` D-003). 수정은 보류다.
    ///
    /// 재현율이 100%가 아니라 `isStrict = false`로 둔다. 통과하는 회차를 실패로 잡지 않되,
    /// 결함이 살아 있는 동안 이 테스트가 실행 가능한 메모 역할을 한다.
    @MainActor
    func testD003FastInputOnTwoDecimalCurrencyBreaksFractionDigits() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")

        typeAmount("10005")

        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("결함 D-003 — 빠른 연속 입력에서 소수부가 2자리를 넘는다. 수정 보류(defect-backlog.md)", options: options)
        XCTAssertEqual(
            entry.amountField.value as? String,
            "100.05",
            "연속 입력이어도 2자리 통화의 소수부는 2자리여야 한다"
        )
    }

    /// 원장 C8 전반부: 12.34는 저장된다.
    @MainActor
    func testC8TwoDecimalCurrencySavesExactlyTwoFractionDigits() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")

        // cents-first 입력: 숫자를 누를수록 오른쪽에서 자리가 채워진다.
        typeAmount("1")
        XCTAssertTrue(entry.amountField.waitForValue("0.01"))
        app.typeText("2")
        XCTAssertTrue(entry.amountField.waitForValue("0.12"))
        app.typeText("3")
        XCTAssertTrue(entry.amountField.waitForValue("1.23"))
        app.typeText("4")
        XCTAssertEqual(entry.amountField.value as? String, "12.34", "USD는 소수 둘째 자리까지 입력돼야 한다")

        selectRequiredEntryFields()
        entry.submitButton.tap()
        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.expenseHistoryRow.label.contains("USD 12.34"), "12.34 USD가 그대로 저장돼야 한다")
    }

    /// 원장 C8 후반부는 "12.345 저장 시도 → 거부"다.
    ///
    /// 앱은 cents-first 입력이라 소수점 자체가 무시되고 **12.345라는 값이 애초에 만들어지지 않는다**(입력 단계 차단).
    /// 그래서 "거부 화면"이 아니라 **소수 3자리 값이 생성·저장되지 않는다는 불변식**을 단언한다.
    /// 이 차이는 원장 「자동화 커버리지 한계」에 사유와 함께 적어 두었다 — 기대를 낮춘 것이 아니라 도달 경로가 다른 것이다.
    /// 앞 케이스의 DB·통화 상태를 물려받지 않도록 자체 launch로 시작한다.
    @MainActor
    func testC8ThirdFractionDigitNeverExists() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")

        typeAmount("12.345")

        // `hasAtMostTwoFractionDigits`가 "12.345"를 이미 배제하므로 별도 부등 단언은 자동 참이라 두지 않는다.
        let typedValue = entry.amountField.value as? String
        XCTAssertTrue(
            hasAtMostTwoFractionDigits(typedValue),
            "입력 값의 소수부는 2자리를 넘을 수 없다 (실제: \(typedValue ?? "nil"))"
        )

        selectRequiredEntryFields()
        entry.submitButton.tap()
        assertSavedEntryVisible(on: TestClock.today)

        let savedLabel = home.expenseHistoryRow.label
        XCTAssertFalse(
            savedLabel.contains("12.345"),
            "소수 3자리 금액이 저장되면 안 된다 (실제: \(savedLabel))"
        )
        XCTAssertTrue(
            savedLabel.range(of: "USD [0-9,]+\\.[0-9]{2}(?![0-9])", options: .regularExpression) != nil,
            "저장된 USD 금액의 소수부는 정확히 2자리여야 한다 (실제: \(savedLabel))"
        )
    }

    /// 소수부가 2자리 이하인지. 셋째 자리가 생기는 회귀를 값 형식만으로 잡는다.
    private func hasAtMostTwoFractionDigits(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        guard let dot = value.firstIndex(of: ".") else {
            return true
        }
        return value.distance(from: value.index(after: dot), to: value.endIndex) <= 2
    }

    /// 원장 C9 전반부: 99,999,999는 저장된다.
    @MainActor
    func testC9MaximumAmountSaves() {
        launch()
        openNewEntry()
        typeAmount("99999999")
        selectRequiredEntryFields()
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("99,999,999"), "최대 금액은 저장돼야 한다")
    }

    /// 원장 C9 후반부: 100,000,000은 거부된다. 앞 케이스가 남긴 DB 상태와 섞이지 않게 자체 launch로 시작한다.
    @MainActor
    func testC9OverMaximumAmountIsRejected() {
        launch()
        openNewEntry()
        typeAmount("100000000")
        // 카테고리·자산을 먼저 채워, 저장 버튼 비활성의 원인이 금액 조건임을 격리한다.
        selectRequiredEntryFields()

        XCTAssertFalse(entry.submitButton.isEnabled, "최대 금액을 넘으면 저장 버튼이 비활성이어야 한다")
        entry.submitButton.tap()

        XCTAssertTrue(entry.amountField.exists, "초과 금액은 저장되지 않고 입력 화면에 남아야 한다")
        entry.closeButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "거부된 금액이 합계에 반영되면 안 된다")
    }

    @MainActor
    func testC10ZeroAmountCannotSave() {
        launch()
        openNewEntry()
        // 카테고리·자산을 먼저 채워, 저장 버튼 비활성의 원인이 금액 조건임을 격리한다.
        selectRequiredEntryFields()

        XCTAssertEqual(entry.amountField.value as? String, "")
        XCTAssertFalse(entry.submitButton.isEnabled, "금액 0에서는 저장 버튼이 비활성이어야 한다")
        entry.submitButton.tap()
        XCTAssertTrue(entry.amountField.exists, "금액 0은 저장되면 안 된다")
    }

    /// 원장 C12의 절차는 "**몇 달 전** 날짜 선택 → 저장"이다. 하루 전만 쓰면 대부분의 날에 당월 저장만 검사하게 돼
    /// 월을 넘는 저장·조회 경로를 전혀 지나가지 않는다.
    @MainActor
    func testC12DateMonthsAgoSavesAndAppearsInThatMonth() {
        let targetDate = TestClock.dayInMonthsAgo(2)
        launch()
        openNewEntry()
        typeAmount("100")

        // 인라인 달력이 펼쳐진 동안 화살표는 월 단위로 움직인다(`DateRow.move(by:)`).
        entry.dateRow.tap()
        XCTAssertTrue(
            entry.calendarDay(TestClock.todayDay).waitForExistence(timeout: Timeout.transition),
            "날짜 행 탭으로 인라인 달력이 펼쳐져야 한다"
        )
        entry.previousDateButton.tap()
        entry.previousDateButton.tap()
        XCTAssertTrue(
            entry.dateRow.waitForLabel(TestClock.monthTitle(for: targetDate)),
            "화살표 두 번으로 두 달 전으로 가야 한다 (실제: \(entry.dateRow.label))"
        )

        let day = TestClock.seoulCalendar.component(.day, from: targetDate)
        entry.calendarDay(day).tap()
        XCTAssertTrue(
            entry.dateRow.waitForLabel(TestClock.fullDate(for: targetDate)),
            "달력에서 고른 날짜가 날짜 행에 반영돼야 한다 (실제: \(entry.dateRow.label))"
        )

        selectRequiredEntryFields()
        entry.submitButton.tap()

        assertSavedEntryVisible(on: targetDate)
        XCTAssertTrue(home.expenseHistoryRow.label.contains("100"), "과거 날짜 내역에 저장 금액이 보여야 한다")
    }

    @MainActor
    func testC13FutureKRWDateSaves() {
        launch()
        openNewEntry()
        typeAmount("520")
        entry.nextDateButton.tap()
        XCTAssertTrue(
            entry.dateRow.waitForLabel(TestClock.fullDate(for: TestClock.tomorrow)),
            "화살표로 내일로 이동해야 한다 (실제: \(entry.dateRow.label))"
        )
        selectRequiredEntryFields()
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.tomorrow)
        XCTAssertTrue(home.expenseHistoryRow.label.contains("520"), "미래 KRW 거래가 저장돼야 한다")
    }

    @MainActor
    func testC14FutureForeignDateIsRejected() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")
        typeAmount("10000")
        entry.nextDateButton.tap()
        XCTAssertTrue(
            entry.dateRow.waitForLabel(TestClock.fullDate(for: TestClock.tomorrow)),
            "화살표로 내일로 이동해야 한다 (실제: \(entry.dateRow.label))"
        )
        selectRequiredEntryFields()
        entry.submitButton.tap()

        XCTAssertTrue(entry.errorText("외화 거래는 미래 날짜를 사용할 수 없습니다.").waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(entry.amountField.exists, "거부 후 입력 화면에 남아야 한다")
        XCTAssertFalse(home.addButton.exists, "거부된 거래는 홈으로 복귀하면 안 된다")

        // 오류를 띄우고도 거래를 넣어버린 구현이라면 위 세 단언은 그대로 통과한다. 저장 부재까지 확인한다.
        //
        // 이때 **거부된 날짜가 속한 달**을 봐야 한다. 홈 합계는 보고 있는 달 범위이고 내역은 선택일 전용이라,
        // 오늘 달에 머문 채로 확인하면 오늘이 말일일 때(내일 = 다음 달) 잘못 저장된 거래를 놓친다.
        entry.closeButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))

        let rejectedDate = TestClock.tomorrow
        setHomeMonth(to: YearMonth(date: rejectedDate))
        XCTAssertTrue(
            home.monthTitle.waitForLabel(TestClock.monthTitle(for: rejectedDate)),
            "거부된 날짜가 속한 달로 이동해야 한다 (실제: \(home.monthTitle.label))"
        )
        let rejectedDay = TestClock.seoulCalendar.component(.day, from: rejectedDate)
        XCTAssertTrue(home.calendarDay(rejectedDay).waitForExistence(timeout: Timeout.transition))
        home.calendarDay(rejectedDay).tap()
        XCTAssertTrue(home.calendarDay(rejectedDay).waitForSelected())

        XCTAssertTrue(home.historyRows.waitForCount(0), "거부된 거래가 그 날짜 내역에 남으면 안 된다")
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "거부된 거래가 그 달 합계에 반영되면 안 된다")
    }

    @MainActor
    func testC17MemoWith255CharactersSavesUnchanged() {
        let memo = String(repeating: "a", count: 255)
        launch()
        openNewEntry()
        typeAmount("100")
        selectRequiredEntryFields()
        replaceMemo(with: memo)
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.expenseHistoryRow.label.contains(memo), "255자 메모가 내역에 온전히 보여야 한다")
        home.expenseHistoryRow.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        revealMemoField()
        XCTAssertEqual(entry.memoField.value as? String, memo, "255자 메모가 편집기에 온전히 저장돼야 한다")
    }

    @MainActor
    func testC18MemoWith256CharactersIsRejected() {
        let memo = String(repeating: "b", count: 256)
        launch()
        openNewEntry()
        typeAmount("100")
        selectRequiredEntryFields()
        replaceMemo(with: memo)
        entry.submitButton.tap()

        XCTAssertTrue(entry.errorText("메모는 255자 이하여야 합니다.").waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(entry.memoField.exists, "거부 후 입력값을 수정할 수 있어야 한다")
        entry.closeButton.tap()
        XCTAssertTrue(home.historyRows.waitForCount(0), "256자 메모 거래가 저장되면 안 된다")
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "거부된 거래가 합계에 반영되면 안 된다")
    }

    @MainActor
    func testC19WhitespaceMemoSavesAsEmpty() {
        launch()
        openNewEntry()
        typeAmount("100")
        selectRequiredEntryFields()
        replaceMemo(with: "   ")
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.expenseHistoryRow.waitForLabelPrefix("메모,"), "공백 메모는 빈 메모 fallback으로 보여야 한다")
        home.expenseHistoryRow.tap()
        XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition))
        revealMemoField()
        // `!=` 로는 공백이 한두 칸으로 변형돼 저장된 경우를 놓친다. 빈 필드가 노출하는 placeholder와 정확히 같아야 한다.
        XCTAssertEqual(entry.memoField.value as? String, Fixture.memoPlaceholder, "공백 메모는 빈 값으로 저장돼야 한다")
    }
}

// MARK: - Step 4 · EntrySelectionUITests

final class EntrySelectionUITests: EntryUITestCase {
    @MainActor
    func testEntrySelectionsAndKeyboardScrolling() {
        launch()
        openNewEntry()

        runCase("C2 new-entry-starts-with-no-selection") {
            XCTAssertTrue(entry.categoryChip(1).waitForExistence(timeout: Timeout.transition), "지출 카테고리가 보여야 한다")
            XCTAssertTrue(entry.selectedChips(prefix: "entry.category.").waitForCount(0), "신규 진입은 카테고리 미선택이어야 한다")
            XCTAssertTrue(entry.selectedChips(prefix: "entry.asset.").waitForCount(0), "신규 진입은 자산 미선택이어야 한다")
            XCTAssertFalse(entry.submitButton.isEnabled, "미선택 상태에서는 저장 버튼이 비활성이어야 한다")
        }

        runCase("C2 tab-switch-replaces-categories") {
            XCTAssertFalse(entry.categoryChip(14).exists, "수입 카테고리가 지출 탭에 보이면 안 된다")

            entry.tab(.income).tap()
            XCTAssertTrue(entry.tab(.income).waitForSelected())
            XCTAssertTrue(entry.categoryChip(14).waitForExistence(timeout: Timeout.transition), "수입 카테고리로 교체돼야 한다")
            XCTAssertFalse(entry.categoryChip(1).exists, "이전 지출 카테고리가 사라져야 한다")

            entry.tab(.expense).tap()
            XCTAssertTrue(entry.categoryChip(1).waitForExistence(timeout: Timeout.transition), "지출 카테고리로 되돌아와야 한다")
            XCTAssertFalse(entry.categoryChip(14).exists)
        }

        // 탭 전환은 카테고리뿐 아니라 **자산까지** 비운다(목록이 공통이라 유지하면 잘못된 값이 딸려간다).
        // 둘 다 골라 둔 상태에서 왕복해야 "비움"과 "이전 선택 보존"이 갈린다.
        runCase("C2 tab-switch-clears-both-selections") {
            selectRequiredEntryFields(categoryId: 2, assetId: 2)

            entry.tab(.income).tap()
            XCTAssertTrue(entry.tab(.income).waitForSelected())
            XCTAssertTrue(entry.selectedChips(prefix: "entry.category.").waitForCount(0), "탭을 바꾸면 카테고리가 비어야 한다")
            XCTAssertTrue(entry.selectedChips(prefix: "entry.asset.").waitForCount(0), "탭을 바꾸면 자산도 비어야 한다")
            XCTAssertFalse(entry.submitButton.isEnabled, "선택이 비면 저장 버튼이 다시 비활성이어야 한다")

            entry.tab(.expense).tap()
            XCTAssertTrue(entry.categoryChip(2).waitForExistence(timeout: Timeout.transition))
            XCTAssertTrue(entry.selectedChips(prefix: "entry.category.").waitForCount(0), "되돌아와도 이전 선택이 되살아나면 안 된다")
            XCTAssertTrue(entry.selectedChips(prefix: "entry.asset.").waitForCount(0), "되돌아와도 이전 자산이 되살아나면 안 된다")
        }

        // 원장 C15·C16의 전제는 "선택 해제 상태로 저장 시도"다. 진입 시 미선택은 이제 정상 상태지만,
        // `ChipSection`의 `onSelect`는 토글이 아니라 항상 선택으로 바꾼다 — **한 번 고른 뒤에는**
        // UI로 미선택으로 되돌릴 수 없다. 그래서 거부 경로 대신 그 사실 자체를 단언한다.
        // 미선택 상태의 저장 거부는 저장 버튼 비활성(위 케이스)과 ViewModel 유닛 테스트가 담당한다.
        runCase("C15 category-selection-cannot-be-cleared") {
            selectRequiredEntryFields()
            assertSelectionCannotBeCleared(prefix: "entry.category.", chip: entry.categoryChip(1))
        }

        runCase("C16 asset-selection-cannot-be-cleared") {
            assertSelectionCannotBeCleared(prefix: "entry.asset.", chip: entry.assetChip(1))
        }

        runCase("keyboard-open-lower-fields-stay-operable") {
            // 앞 케이스에서 칩을 탭했으면 앱의 tap-to-dismiss로 키보드가 내려가 있다.
            // 전제를 앞 케이스의 잔여 상태에 맡기지 않고 여기서 직접 세운다.
            entry.amountField.tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "금액 키보드가 열려야 한다")
            revealMemoField()

            // 아래 두 단언은 키보드가 실제로 떠 있을 때만 "가려지지 않는다"의 증명이 된다.
            // 드래그가 키보드를 내려버렸다면 전제가 무너진 것이므로 먼저 못박는다.
            XCTAssertTrue(app.keyboards.element.exists, "위로 끄는 동안 키보드는 유지돼야 한다")
            XCTAssertTrue(entry.memoField.isHittable, "키보드가 열려 있어도 메모 필드에 도달할 수 있어야 한다")
            XCTAssertTrue(entry.assetChip(2).isHittable, "키보드가 열려 있어도 자산 칩을 조작할 수 있어야 한다")

            entry.assetChip(2).tap()
            XCTAssertTrue(entry.assetChip(2).waitForSelected(), "가려지지 않은 칩은 실제로 선택까지 돼야 한다")
        }

        // 키보드 해제는 탭 경로만 단언한다. 드래그 해제(`.scrollDismissesKeyboard(.interactively)`)는
        // 제스처 기하에 따라 재현이 갈려(계측 O-001) 게이트에 넣으면 플레이크가 된다. 원장에 미검증으로 남긴다.
        runCase("form-tap-dismisses-keyboard") {
            entry.memoField.tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "메모 탭으로 키보드가 떠야 한다")

            // 폼 안의 비인터랙티브 영역 탭 — `AddEntryView`가 VStack에 건 simultaneousGesture 경로다.
            app.staticTexts["메모"].tap()
            XCTAssertTrue(app.keyboards.element.waitForNonExistence(), "폼 빈 영역 탭으로 키보드가 해제돼야 한다")
        }
    }

    /// 이미 선택된 칩을 다시 탭해도 선택이 풀리지 않는다 — 한 번 고르고 나면 미선택으로 되돌릴 수 없다.
    /// 자동선택이 없으므로 호출자가 먼저 칩을 골라 전제를 세워야 한다.
    private func assertSelectionCannotBeCleared(prefix: String, chip: XCUIElement) {
        XCTAssertTrue(entry.selectedChips(prefix: prefix).waitForCount(1), "\(prefix) 는 정확히 하나 선택돼 있어야 한다")
        XCTAssertTrue(chip.isSelected, "앞서 고른 칩을 대상으로 해야 한다")

        chip.tap()

        XCTAssertTrue(chip.waitForSelected(), "선택된 칩을 다시 탭해도 선택이 유지돼야 한다")
        XCTAssertTrue(entry.selectedChips(prefix: prefix).waitForCount(1), "재탭 후에도 선택은 정확히 하나여야 한다")
    }
}

// MARK: - Step 5 · 홈/달력 공통

class HomeCalendarUITestCase: EntryUITestCase {
    func launchSeeded(baseCurrency: String = "KRW", language: String = "ko") {
        launch(seedLedger: true, baseCurrency: baseCurrency, language: language)
        XCTAssertTrue(home.calendar.waitForExistence(timeout: Timeout.launch), "달력이 그려져야 한다")
        XCTAssertTrue(home.historyContainer.waitForExistence(timeout: Timeout.launch), "내역 영역이 그려져야 한다")
    }

    func waitForMonth(_ date: Date) {
        XCTAssertTrue(
            home.monthTitle.waitForLabel(TestClock.monthTitle(for: date)),
            "월 헤더가 \(TestClock.monthTitle(for: date))이어야 한다 (실제: \(home.monthTitle.label))"
        )
        XCTAssertTrue(home.calendar.waitForExistence(timeout: Timeout.transition), "월 로드 후 달력이 다시 나타나야 한다")
        // 헤더 라벨과 달력 존재를 서로 다른 접근성 스냅샷에서 볼 수 있다. 대상 월의 날짜 수까지 맞아야
        // 새 달 골격으로 재렌더가 끝난 것이다. 전환 중 나가는 그리드는 접근성에서 숨겨지므로 이 조건은
        // 들어오는 대상 월 그리드만 센다.
        XCTAssertTrue(
            home.calendarDays.waitForCount(TestClock.dayCount(in: date)),
            "이동한 달의 날짜 셀이 모두 그려져야 한다"
        )
    }

    func dragCalendar(horizontal: CGFloat, vertical: CGFloat) {
        XCTAssertTrue(home.calendar.waitForExistence(timeout: Timeout.transition), "드래그할 달력이 있어야 한다")
        XCTAssertTrue(home.calendarDay(1).waitForExistence(timeout: Timeout.transition), "1일 셀로 격자 위치를 잡는다")

        // 시작점을 날짜 버튼 위에 두지 않는다. 드래그가 셀 선택까지 함께 발동해 관측이 섞일 수 있다
        // (step 2의 N-001 조사에서 셀 위 드래그가 선택을 발동시키는 것을 확인했다).
        // 달력 상단과 1일 셀 사이의 요일 헤더 띠는 버튼이 없는 영역이다.
        let calendarFrame = home.calendar.frame
        let startY = (calendarFrame.minY + home.calendarDay(1).frame.minY) / 2
        let start = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: calendarFrame.midX, dy: startY))
        start.press(
            forDuration: 0.1,
            thenDragTo: start.withOffset(CGVector(dx: horizontal, dy: vertical)),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
    }

    func assertHistoryIsEmpty(_ message: String) {
        XCTAssertTrue(home.historyContainer.waitForExistence(timeout: Timeout.transition), "내역 영역은 남아 있어야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(0), message)
    }
}

// MARK: - Step 6 · CurrencyRateUITests

final class CurrencyRateUITests: HomeCalendarUITestCase {
    private let currencies = [
        ("대한민국, KRW", "KRW"),
        ("일본, JPY", "JPY"),
        ("태국, THB", "THB"),
        ("중국, CNY", "CNY"),
        ("홍콩, HKD", "HKD"),
        ("싱가포르, SGD", "SGD"),
        ("인도네시아, IDR", "IDR"),
        ("말레이시아, MYR", "MYR"),
        ("미국, USD", "USD"),
        ("유럽, EUR", "EUR"),
        ("호주, AUD", "AUD"),
        ("뉴질랜드, NZD", "NZD"),
        ("영국, GBP", "GBP")
    ]

    @MainActor
    func testC3CurrencyPickerShowsAndSelectsAllThirteenCurrencies() {
        launch()
        openNewEntry()

        runCase("C3 currency-picker-13") {
            // 13종을 순회만 하면 빠진 통화는 잡히지만 14번째가 늘어나도 통과한다. 개수로 상한을 못 박는다.
            // 시트는 LazyVStack이 아니라 VStack이라 스크롤 위치와 무관하게 13행이 모두 트리에 있다.
            entry.currencyButton.tap()
            XCTAssertTrue(
                entry.currencyOption(currencies[0].0).waitForExistence(timeout: Timeout.transition),
                "통화 시트가 열려야 한다"
            )
            let listed = entry.currencyOptions
            XCTAssertEqual(
                listed.count,
                currencies.count,
                "통화 목록은 \(currencies.count)종이어야 한다 (실제: \(listed.allElementsBoundByIndex.map(\.label)))"
            )
            entry.currencyOption(currencies[0].0).tap()

            for (label, code) in currencies {
                selectCurrency(label: label, code: code)
            }
        }
    }

    @MainActor
    func testC22C23CurrencyAndDateChangesRefreshSeedRate() {
        guard let fixedDate = TestClock.date(year: 2025, month: 7, day: 15) else {
            return XCTFail("고정 환율 날짜를 만들 수 없다")
        }
        launch()
        openNewEntry()
        setEntryDate(to: fixedDate)

        runCase("C22 currency-change-refetches-rate") {
            selectCurrency(label: "미국, USD", code: "USD")
            XCTAssertTrue(entry.rateLabel(prefix: "KRW 1.00 = USD ").waitForLabel("KRW 1.00 = USD 0.0007182"))

            selectCurrency(label: "일본, JPY", code: "JPY")
            XCTAssertTrue(entry.rateLabel(prefix: "KRW 1.00 = JPY ").waitForLabel("KRW 1.00 = JPY 0.1061"))
            XCTAssertFalse(entry.rateLabel(prefix: "KRW 1.00 = USD ").exists, "이전 USD 환율이 남으면 안 된다")
        }

        runCase("C23 date-change-refetches-rate") {
            selectCurrency(label: "미국, USD", code: "USD")
            XCTAssertTrue(entry.rateLabel(prefix: "KRW 1.00 = USD ").waitForLabel("KRW 1.00 = USD 0.0007182"))

            entry.previousDateButton.tap()
            guard let previousDate = TestClock.date(year: 2025, month: 7, day: 14) else {
                return XCTFail("이전 날짜를 만들 수 없다")
            }
            XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.fullDate(for: previousDate)))
            XCTAssertTrue(entry.rateLabel(prefix: "KRW 1.00 = USD ").waitForLabel("KRW 1.00 = USD 0.0007202"))
        }
    }

    /// E2 **부분 커버**. 이 테스트가 실제로 지키는 것은
    /// "요청일이 시드 상한(스냅샷 최대 baseDate)을 넘어도 환율을 찾아 **양수로** 표시한다"이다.
    /// `RateProvider.quote`의 `first(where: baseDate <= localDate)`가 nil을 돌려주면 라벨이 없어 실패한다.
    ///
    /// **추정 라벨 단언은 판별력이 없다.** `-uiTest` 하네스는 `addExpenseRateProvider`를
    /// `SeedRateProviderAdapter`로 고정하므로(`woni_appApp.swift`) `currentQuote.source`가 항상 `.seed`이고,
    /// `isCurrentRateEstimated`는 비-KRW 통화면 무조건 참이다. 즉 원장 E2의 전제인 "오프라인 전환"은
    /// 이 하네스에서 탈 수 없다 — 라벨이 **렌더된다**는 것만 확인한다. 트리거 판정은 유닛 테스트 몫이다.
    /// (원장 「자동화 커버리지 한계」의 E2 행)
    @MainActor
    func testE2SeedFallbackShowsEstimatedRateLabel() {
        launch()
        openNewEntry()

        runCase("E2 seed-fallback-estimated-label") {
            selectCurrency(label: "미국, USD", code: "USD")
            // 접두만 보면 숫자가 비거나 0이어도 통과하므로 실제 숫자가 붙었는지까지 본다.
            let rateElement = entry.rateLabel(prefix: "KRW 1.00 = USD ")
            XCTAssertTrue(
                rateElement.waitForExistence(timeout: Timeout.transition),
                "시드 상한을 넘은 날짜에도 환율 숫자가 표시돼야 한다"
            )
            assertRateLabelHasPositiveNumber(rateElement, prefix: "KRW 1.00 = USD ")
            XCTAssertTrue(entry.estimatedRateLabel.waitForExistence(timeout: Timeout.transition), "추정 환율 라벨이 렌더돼야 한다")
        }
    }

    /// D3 **값 정확성**. 시드 환율이 걸린 날짜에서 금액을 직접 입력해 **앱이 환산을 계산하게** 하고,
    /// 테스트가 소유한 고정 기대값과 대조한다.
    ///
    /// 미리 계산해둔 `krwAmount`를 시드에 넣고 표시만 확인하면 환산식이 틀려도 통과한다
    /// (아래 `testSeededForeignTransactionPinsRateAndConvertedValue`가 그 표시 경로를 본다).
    /// 2025-07-15 USD tts는 시드 스냅샷에서 1392.28이고 `25.00 × 1392.28 = 34,807.00`으로
    /// 나누어떨어져 반올림 규칙에 기대지 않는다. 금액은 D-003을 피해 한 글자씩 넣는다.
    @MainActor
    func testD3ConvertedAmountIsComputedFromSeededRate() {
        guard let rateDate = TestClock.date(year: 2025, month: 7, day: 15) else {
            return XCTFail("환율 fixture 날짜를 만들 수 없다")
        }
        // 시드 원장 없이 시작해 그 달 합계가 이 거래만 반영하도록 한다.
        launch()
        openNewEntry()
        setEntryDate(to: rateDate)
        selectCurrency(label: "미국, USD", code: "USD")

        typeAmount("2")
        XCTAssertTrue(entry.amountField.waitForValue("0.02"))
        app.typeText("5")
        XCTAssertTrue(entry.amountField.waitForValue("0.25"))
        app.typeText("0")
        XCTAssertTrue(entry.amountField.waitForValue("2.50"))
        app.typeText("0")
        XCTAssertTrue(entry.amountField.waitForValue("25.00"))

        XCTAssertEqual(
            entry.convertedAmountText(),
            Fixture.computedConversionText,
            "25.00 USD × 1392.28 = 34,807 이어야 한다"
        )

        selectRequiredEntryFields()
        entry.submitButton.tap()
        assertSavedEntryVisible(on: rateDate)
        XCTAssertTrue(
            home.summaryAmount(.expense).waitForLabel(Fixture.computedConversionText),
            "저장된 환산액이 월 합계에 그대로 반영돼야 한다"
        )
    }

    /// 저장된 `krwAmount`·`appliedRate`가 히스토리와 합계에 **표시**되는 경로를 본다.
    /// 값 자체가 맞는지는 위 `testD3ConvertedAmountIsComputedFromSeededRate`가 계산 경로로 검증한다.
    @MainActor
    func testSeededForeignTransactionPinsRateAndConvertedValue() {
        launchSeeded()
        let fixtureMonth = YearMonth(year: 2025, month: 7)
        guard let fixtureDate = TestClock.date(year: 2025, month: 7, day: 15) else {
            return XCTFail("환산 완료 fixture 날짜를 만들 수 없다")
        }

        runCase("D3 fixed-rate-value") {
            setHomeMonth(to: fixtureMonth)
            waitForMonth(fixtureDate)
            home.calendarDay(15).tap()
            XCTAssertTrue(home.calendarDay(15).waitForSelected())

            let row = home.historyRow(id: Fixture.convertedUSDID)
            XCTAssertTrue(row.waitForExistence(timeout: Timeout.transition), "환산 완료 USD 행이 보여야 한다")
            for expected in ["UITestConvertedUSD", "13,922", "USD 10.00", "KRW 1.00 = USD 0.0007182"] {
                XCTAssertTrue(row.label.contains(expected), "행에 \(expected)이 보여야 한다 (실제: \(row.label))")
            }
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("13,922"), "고정 krwAmount가 월 합계에 정확히 반영돼야 한다")
        }
    }

    @MainActor
    func testTwoDecimalToZeroDecimalReformatsInputAndSavedAmount() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")

        typeAmount("1")
        XCTAssertTrue(entry.amountField.waitForValue("0.01"))
        app.typeText("2")
        XCTAssertTrue(entry.amountField.waitForValue("0.12"))
        app.typeText("3")
        XCTAssertTrue(entry.amountField.waitForValue("1.23"))
        app.typeText("4")
        XCTAssertTrue(entry.amountField.waitForValue("12.34"))

        selectCurrency(label: "일본, JPY", code: "JPY")
        XCTAssertTrue(entry.amountField.waitForValue("12"), "USD 소수부가 JPY 전환 시 절삭돼야 한다")
        entry.amountField.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(entry.amountField.waitForKeyboardFocus(), "JPY 추가 입력 전에 금액 필드가 포커스를 가져야 한다")
        app.typeText("5")
        XCTAssertTrue(
            entry.amountField.waitForValue("125"),
            "추가 입력도 0자리 정책을 따라야 한다 (실제: \(entry.amountField.value as? String ?? "nil"))"
        )

        selectRequiredEntryFields()
        entry.submitButton.tap()
        assertSavedEntryVisible(on: TestClock.today)
        XCTAssertTrue(home.expenseHistoryRow.label.contains("JPY 125"), "저장 금액도 JPY 0자리여야 한다")
    }

    @MainActor
    func testZeroDecimalToTwoDecimalReconstructsAmountDisplay() {
        launch()
        openNewEntry()
        typeAmount("1")
        XCTAssertTrue(entry.amountField.waitForValue("1"))
        app.typeText("2")
        XCTAssertTrue(entry.amountField.waitForValue("12"))
        app.typeText("3")
        XCTAssertTrue(entry.amountField.waitForValue("123"))
        app.typeText("4")
        XCTAssertTrue(entry.amountField.waitForValue("1234"))

        selectCurrency(label: "미국, USD", code: "USD")

        XCTAssertTrue(entry.amountField.waitForValue("1234.00"), "0자리 금액이 USD 2자리 표시로 재구성돼야 한다")
    }
}

// MARK: - Step 6 · LastUsedCurrencyUITests

final class LastUsedCurrencyUITests: EntryUITestCase {
    /// 기준 통화를 설정 화면에서 바꾼 테스트가 있으면 teardown에서 되돌린다.
    private var didChangeBaseCurrency = false

    override func tearDownWithError() throws {
        // 기준 통화는 앱 도메인 UserDefaults에 영구 저장된다(런치 인자와 달리 프로세스와 함께 사라지지 않는다).
        // 본문 끝에서만 되돌리면 `continueAfterFailure = false` 탓에 중간 실패 시 JPY가 남아
        // `-woni.app.baseCurrency` 없이 뜨는 이후 테스트를 조용히 오염시킨다. teardown에서 보장한다.
        if didChangeBaseCurrency {
            didChangeBaseCurrency = false
            restoreBaseCurrencyToKRW()
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testC4SavedCurrencyBecomesDefaultOnNextLaunch() {
        launchForPersistence(baseCurrency: "KRW", lastUsedCurrency: "KRW", clearLastUsed: true)
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")
        typeAmount("1")
        XCTAssertTrue(entry.amountField.waitForValue("0.01"))
        selectRequiredEntryFields()
        entry.submitButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))

        app.terminate()
        launchForPersistence(baseCurrency: "KRW", lastUsedCurrency: nil)
        openNewEntry()

        runCase("C4 saved-currency-is-next-default") {
            XCTAssertTrue(entry.currencyButton.waitForLabel("USD"))
        }
    }

    @MainActor
    func testC5NoLastUsedCurrencyStartsWithBaseCurrency() {
        // 판별 대상은 `AddExpenseViewModel`의 `lastUsedCurrency ?? baseCurrency`다.
        // 기준 통화를 KRW로 두면 이 폴백이 `?? .krw`로 회귀해 기준 통화를 통째로 무시해도
        // KRW가 나와 통과한다. 비-KRW로 둬야 갈린다 — 이 인자를 KRW로 되돌리지 마라.
        // (런치 인자 JPY는 NSArgumentDomain으로만 들어가 영구 저장되지 않는다.)
        launchForPersistence(baseCurrency: "JPY", lastUsedCurrency: nil, clearLastUsed: true)
        openNewEntry()

        runCase("C5 no-record-uses-default") {
            XCTAssertTrue(entry.currencyButton.waitForLabel("JPY"), "마지막 사용 통화가 없으면 기준 통화 JPY로 시작해야 한다")
            XCTAssertTrue(entry.amountField.waitForExistence(timeout: Timeout.transition), "기록이 없어도 입력 화면이 정상이어야 한다")
        }
    }

    @MainActor
    func testC6ChangingBaseCurrencyClearsLastUsedCurrency() {
        launchForPersistence(baseCurrency: "KRW", lastUsedCurrency: "KRW", clearLastUsed: true)
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")
        typeAmount("1")
        XCTAssertTrue(entry.amountField.waitForValue("0.01"))
        selectRequiredEntryFields()
        entry.submitButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))

        home.settingsButton.tap()
        let settings = SettingsScreen(app: app)
        XCTAssertTrue(settings.baseCurrencyRow.waitForExistence(timeout: Timeout.transition))
        settings.baseCurrencyRow.tap()
        let jpy = entry.currencyOption("일본, JPY")
        XCTAssertTrue(jpy.waitForExistence(timeout: Timeout.transition))
        // 영구 저장을 일으키기 **직전에** 표시해 이 지점 이후 어디서 실패해도 teardown이 되돌린다.
        didChangeBaseCurrency = true
        jpy.tap()
        XCTAssertTrue(settings.baseCurrencyRow.waitForLabelContaining("JPY"))

        app.terminate()
        launchForPersistence(baseCurrency: nil, lastUsedCurrency: nil)
        openNewEntry()

        runCase("C6 base-change-clears-last-used") {
            XCTAssertTrue(entry.currencyButton.waitForLabel("JPY"), "이전 USD가 아니라 새 기준 통화 JPY로 시작해야 한다")
        }
    }

    /// 어느 화면에서 멈췄든 되돌릴 수 있도록 앱을 새로 띄운 뒤 설정 화면을 거쳐 KRW로 되돌린다.
    ///
    /// KRW 재선택은 기준 통화 변경이므로 `MainRootView`의 `onChange`가 `lastUsedCurrency`까지 비운다.
    /// 따라서 클래스 전체를 돌리면 종료 상태가 기본값으로 수렴한다. 다만 `-only-testing`으로
    /// C4만 단독 실행하면 그 테스트가 남긴 `lastUsedCurrency = USD`는 남는다 — 다른 테스트가 전부
    /// `-woni.app.lastUsedCurrency`를 명시해 인자 도메인이 이기므로 현재 영향은 없다.
    private func restoreBaseCurrencyToKRW() {
        app.terminate()
        launchForPersistence(baseCurrency: nil, lastUsedCurrency: nil)
        XCTAssertTrue(home.settingsButton.waitForExistence(timeout: Timeout.transition))
        home.settingsButton.tap()
        let settings = SettingsScreen(app: app)
        XCTAssertTrue(settings.baseCurrencyRow.waitForExistence(timeout: Timeout.transition))
        settings.baseCurrencyRow.tap()
        let krw = entry.currencyOption("대한민국, KRW")
        XCTAssertTrue(krw.waitForExistence(timeout: Timeout.transition))
        krw.tap()
        XCTAssertTrue(settings.baseCurrencyRow.waitForLabelContaining("KRW"), "기준 통화를 KRW로 되돌려야 한다")
    }

    private func launchForPersistence(
        baseCurrency: String?,
        lastUsedCurrency: String?,
        clearLastUsed: Bool = false
    ) {
        app.launchArguments = [UITestFlags.enable, "-woni.app.language.override", "ko"]
        if let baseCurrency {
            app.launchArguments += ["-woni.app.baseCurrency", baseCurrency]
        }
        if let lastUsedCurrency {
            app.launchArguments += ["-woni.app.lastUsedCurrency", lastUsedCurrency]
        }
        if clearLastUsed {
            app.launchArguments.append(UITestFlags.clearLastUsedCurrency)
        }
        app.launch()
        home.waitForReady()
    }
}

// MARK: - Step 6 · DateFieldUITests

final class DateFieldUITests: EntryUITestCase {
    @MainActor
    func testC11InlineCalendarMovesMonthsSelectsDateAndCollapses() {
        launch()
        openNewEntry()

        runCase("C11 inline-calendar-opens-with-current-selection") {
            entry.dateRow.tap()
            XCTAssertTrue(entry.calendarDay(TestClock.todayDay).waitForExistence(timeout: Timeout.transition))
            XCTAssertTrue(entry.calendarDay(TestClock.todayDay).waitForSelected(), "현재 날짜가 선택 상태여야 한다")
        }

        let previous = TestClock.seoulCalendar.date(byAdding: .month, value: -1, to: TestClock.today) ?? TestClock.today
        runCase("C11 inline-calendar-previous-next-month") {
            entry.previousDateButton.tap()
            XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.monthTitle(for: previous)))
            let previousDay = TestClock.seoulCalendar.component(.day, from: previous)
            XCTAssertTrue(entry.calendarDay(previousDay).waitForSelected())

            entry.nextDateButton.tap()
            let returned = TestClock.seoulCalendar.date(byAdding: .month, value: 1, to: previous) ?? previous
            XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.monthTitle(for: returned)))
            let selectedDay = TestClock.seoulCalendar.component(.day, from: returned)
            XCTAssertTrue(entry.calendarDay(selectedDay).waitForSelected())

            let targetDay = selectedDay == 1 ? 2 : 1
            let targetDate = TestClock.date(
                year: TestClock.seoulCalendar.component(.year, from: returned),
                month: TestClock.seoulCalendar.component(.month, from: returned),
                day: targetDay
            ) ?? returned
            let target = entry.calendarDay(targetDay)
            XCTAssertTrue(target.waitForExistence(timeout: Timeout.transition))
            target.tap()
            XCTAssertTrue(target.waitForNonExistence(), "날짜 선택 후 인라인 달력이 접혀야 한다")
            XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.fullDate(for: targetDate)), "날짜 행이 선택일로 갱신돼야 한다")
        }
    }

    @MainActor
    func testD4EditingDateMovesTransactionToPreviousMonth() {
        launch(seedLedger: true)
        openSeededExpense()
        let previousMonthDate = TestClock.monthDate(byAdding: -1, day: 15)

        runCase("D4 edit-date-to-another-month") {
            entry.dateRow.tap()
            XCTAssertTrue(entry.calendarDay(TestClock.todayDay).waitForExistence(timeout: Timeout.transition))
            entry.previousDateButton.tap()
            XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.monthTitle(for: previousMonthDate)))
            entry.calendarDay(15).tap()
            XCTAssertTrue(entry.dateRow.waitForLabel(TestClock.fullDate(for: previousMonthDate)))
            entry.submitButton.tap()

            XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "원래 달 지출에서 수정 거래가 빠져야 한다")
            XCTAssertTrue(home.historyContainer.waitForExistence(timeout: Timeout.transition))
            XCTAssertTrue(home.historyRows.waitForCount(1), "원래 날짜에는 수입 거래만 남아야 한다")

            setHomeMonth(to: YearMonth(date: previousMonthDate))
            XCTAssertTrue(home.monthTitle.waitForLabel(TestClock.monthTitle(for: previousMonthDate)))
            home.calendarDay(15).tap()
            XCTAssertTrue(home.calendarDay(15).waitForSelected())
            XCTAssertTrue(home.historyRows.waitForCount(2), "이전 달 15일에는 기존 수입과 이동한 지출이 보여야 한다")
            XCTAssertTrue(home.historyRow(id: Fixture.expenseID).exists, "수정 거래가 이전 달에 나타나야 한다")
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel(Fixture.expenseText))
            XCTAssertTrue(home.summaryAmount(.income).waitForLabel(Fixture.previousMonthAmountText))
            XCTAssertTrue(home.summaryAmount(.total).waitForLabel("-3,000"))
        }
    }
}

// MARK: - Step 5 · CalendarSelectionUITests

final class CalendarSelectionUITests: HomeCalendarUITestCase {
    @MainActor
    func testB7SelectingTransactionDateShowsOnlyThatDatesEntries() {
        launchSeeded()

        let otherDay = TestClock.seedOtherDay
        home.calendarDay(otherDay).tap()
        XCTAssertTrue(home.calendarDay(otherDay).waitForSelected(), "다른 날짜 거래 셀이 선택돼야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(1), "다른 날짜에는 그 날짜 거래 한 건만 보여야 한다")
        XCTAssertTrue(home.historyRow(id: Fixture.otherDayID).exists, "다른 날짜의 수입 거래가 보여야 한다")

        home.todayCell.tap()

        XCTAssertTrue(home.todayCell.waitForSelected(), "오늘 셀이 선택돼야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(2), "오늘 거래 두 건만 보여야 한다")
        XCTAssertTrue(home.historyRow(id: Fixture.expenseID).exists, "오늘 지출 행이 보여야 한다")
        XCTAssertTrue(home.historyRow(id: Fixture.incomeID).exists, "오늘 수입 행이 보여야 한다")
    }

    @MainActor
    func testB7SelectingDateWithoutTransactionsKeepsSelectionAndShowsEmptyHistory() {
        launchSeeded()

        let emptyDay = TestClock.emptySeedDay
        XCTAssertTrue(home.calendarDay(emptyDay).waitForExistence(timeout: Timeout.transition), "거래 없는 날짜 셀이 있어야 한다")
        home.calendarDay(emptyDay).tap()

        XCTAssertTrue(home.calendarDay(emptyDay).waitForSelected(), "거래가 없어도 탭한 날짜는 선택돼야 한다")
        assertHistoryIsEmpty("거래 없는 날짜의 내역은 비어야 한다")
    }

    @MainActor
    func testMovingSelectionClearsPreviousCellAndShowsNewDate() {
        launchSeeded()

        home.todayCell.tap()
        XCTAssertTrue(home.todayCell.waitForSelected(), "첫 날짜가 선택돼야 한다")
        home.calendarDay(TestClock.seedOtherDay).tap()

        XCTAssertTrue(home.todayCell.waitForNotSelected(), "이전 날짜의 선택 상태가 해제돼야 한다")
        XCTAssertTrue(home.calendarDay(TestClock.seedOtherDay).waitForSelected(), "새 날짜가 선택돼야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(1), "새 날짜 거래만 보여야 한다")
        XCTAssertTrue(home.historyRow(id: Fixture.otherDayID).exists, "새 날짜의 유일한 거래가 보여야 한다")
    }

    /// 원장 L2(설계 확인 필요)의 **현재 동작**을 못박은 change-detector다.
    /// 설계 결정이 바뀌면 이 테스트가 먼저 실패하는 것이 의도다.
    /// 결함이 아니므로 `XCTExpectFailure`도 백로그 기록도 쓰지 않는다 — 그건 확정 결함용이다.
    @MainActor
    func testB8L2RetappingSelectedDateDoesNotToggleItOff() {
        launchSeeded()

        home.todayCell.tap()
        XCTAssertTrue(home.todayCell.waitForSelected(), "오늘이 선택돼야 한다")
        home.todayCell.tap()

        XCTAssertTrue(home.todayCell.waitForSelected(), "같은 날짜를 재탭해도 선택이 유지돼야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(2), "재탭 뒤에도 선택일 내역이 유지돼야 한다")
    }

    @MainActor
    func testTodayTraitIsExposedOnlyOnActualTodayCell() {
        launchSeeded()

        XCTAssertTrue(home.todayCell.waitForExistence(timeout: Timeout.transition), "오늘 날짜 셀이 있어야 한다")
        XCTAssertEqual(home.todayCell.value as? String, Fixture.todayAccessibilityValue)
        XCTAssertTrue(
            home.todayCells.waitForCount(1),
            "오늘 접근성 값은 실제 오늘 날짜 셀 하나에만 있어야 한다"
        )
    }

    /// 원장 L2(설계 확인 필요)로 남아 있던 "월 이동 시 선택 날짜"는 **확정 사양**이 됐다 —
    /// 오늘이 속한 달로 돌아올 때만 오늘을 고르고, 그 외 달로 옮길 때는 선택 날짜를 건드리지 않는다.
    /// 중간에 "그 달 1일 선택"을 넣었다가 사용자 실사용 판단으로 철회했다(2026-07-31, 플랜 §0).
    /// 여기서는 오늘이 없는 달로 옮기는 쪽만 본다(복귀 규칙은 `testReturningToCurrentMonthSelectsToday`).
    @MainActor
    func testB15MonthMoveKeepsSelectionAndEmptiesHistory() {
        launchSeeded()
        let currentMonth = YearMonth(date: TestClock.today)
        let nextDate = TestClock.monthDate(byAdding: 1, day: 15)

        home.todayCell.tap()
        XCTAssertTrue(home.todayCell.waitForSelected(), "이동 전 오늘이 선택돼야 한다")

        setHomeMonth(from: currentMonth, to: YearMonth(date: nextDate))
        waitForMonth(nextDate)

        XCTAssertTrue(home.selectedCalendarDays.waitForCount(0), "옮긴 달에는 선택 셀이 없어야 한다")
        assertHistoryIsEmpty("월 이동은 선택 날짜를 바꾸지 않으므로 옮긴 달의 내역은 비어야 한다")
    }

    @MainActor
    func testMonthMoveShowsHistoryOnlyAfterPickingDateInMovedMonth() {
        launchSeeded()
        let nextDate = TestClock.monthDate(byAdding: 1, day: 15)

        setHomeMonth(to: YearMonth(date: nextDate))
        waitForMonth(nextDate)

        XCTAssertTrue(home.selectedCalendarDays.waitForCount(0), "옮긴 달에는 선택 셀이 없어야 한다")
        XCTAssertTrue(
            home.summaryAmount(.expense).waitForLabel(Fixture.nextMonthAmountText),
            "옮긴 달의 거래가 로드돼 월 합계에 보여야 한다"
        )
        assertHistoryIsEmpty("거래가 있는 달이어도 선택 셀이 없으면 내역은 비어야 한다")

        home.calendarDay(15).tap()

        XCTAssertTrue(home.historyRows.waitForCount(1), "날짜를 직접 누르면 그 날 내역만 보여야 한다")
        XCTAssertTrue(
            home.expenseHistoryRow.waitForLabelContaining(Fixture.nextMonthAmountText),
            "옮긴 달 15일의 시드 지출이 보여야 한다"
        )
    }

    /// 연월 피커를 **탭**으로 조작한다(드래그는 `pickYearMonth`를 쓰는 다른 테스트가 덮는다).
    /// 가운데 항목을 누르면 값이 그대로라 검증력이 없으므로 두 칸 떨어진 달을 누른다.
    @MainActor
    func testYearMonthPickerTapChangesMonthAndSaveAppliesIt() {
        launchSeeded()
        // 월 휠은 1...12뿐이라 같은 해 안에서 두 칸 움직일 수 있는 방향을 고른다(연 휠은 건드리지 않는다).
        let target = TestClock.monthDate(byAdding: TestClock.currentMonth + 2 <= 12 ? 2 : -2, day: 1)
        let targetMonth = YearMonth(date: target)

        home.monthTitle.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForExistence(timeout: Timeout.transition), "연월 피커가 열려야 한다")

        let targetRow = entry.monthWheelRow(targetMonth.month)
        XCTAssertTrue(targetRow.waitForHittable(), "가운데서 두 칸 떨어진 달도 화면에 보여 눌릴 수 있어야 한다")
        targetRow.tap()

        XCTAssertTrue(
            entry.pickerTitle(year: targetMonth.year, month: targetMonth.month)
                .waitForExistence(timeout: Timeout.transition),
            "탭한 달이 피커 타이틀에 반영돼야 한다"
        )
        XCTAssertTrue(entry.yearMonthPickerSave.exists, "탭만으로는 피커가 닫히면 안 된다 — 반영은 저장 버튼이다")

        entry.yearMonthPickerSave.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForNonExistence(), "저장 후 피커가 닫혀야 한다")
        waitForMonth(target)
        XCTAssertTrue(home.selectedCalendarDays.waitForCount(0), "탭으로 옮긴 달에도 선택 셀이 없어야 한다")
    }

    @MainActor
    func testReturningToCurrentMonthSelectsToday() {
        launchSeeded()
        let nextDate = TestClock.monthDate(byAdding: 1, day: 15)

        dragCalendar(horizontal: -100, vertical: 0)
        waitForMonth(nextDate)
        XCTAssertTrue(home.selectedCalendarDays.waitForCount(0), "스와이프로 옮긴 달에는 선택 셀이 없어야 한다")

        // 옮긴 달에서 날짜를 고른다. 이렇게 해야 복귀 시의 "오늘"이 선택이 남아 있던 것과 구분된다.
        home.calendarDay(15).tap()
        XCTAssertTrue(home.calendarDay(15).waitForSelected(), "옮긴 달에서 고른 날짜가 선택돼야 한다")

        dragCalendar(horizontal: 100, vertical: 0)
        waitForMonth(TestClock.today)

        XCTAssertTrue(home.todayCell.waitForSelected(), "이번 달로 돌아오면 오늘이 선택돼야 한다")
        XCTAssertTrue(home.selectedCalendarDays.waitForCount(1), "선택 셀은 오늘 하나여야 한다")
        XCTAssertTrue(home.historyRows.waitForCount(2), "오늘 거래 두 건이 다시 보여야 한다")
    }
}

// MARK: - Step 5 · CalendarGestureUITests

final class CalendarGestureUITests: HomeCalendarUITestCase {
    @MainActor
    func testB3LeftDragMovesToNextMonthAndRefreshesDashboard() {
        launchSeeded()
        let nextMonth = TestClock.monthDate(byAdding: 1, day: 15)

        dragCalendar(horizontal: -100, vertical: 0)
        waitForMonth(nextMonth)

        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel(Fixture.nextMonthAmountText))
        XCTAssertTrue(home.summaryAmount(.income).waitForLabel("0"))
        XCTAssertTrue(home.calendarDay(15).waitForLabelContaining(Fixture.nextMonthAmountText))
    }

    @MainActor
    func testB3RightDragMovesToPreviousMonth() {
        launchSeeded()
        let previousMonth = TestClock.monthDate(byAdding: -1, day: 15)

        dragCalendar(horizontal: 100, vertical: 0)
        waitForMonth(previousMonth)

        XCTAssertTrue(home.summaryAmount(.income).waitForLabel(Fixture.previousMonthAmountText))
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"))
        XCTAssertTrue(home.calendarDay(15).waitForLabelContaining(Fixture.previousMonthAmountText))
    }

    /// 원장 L1(설계 확인 필요)의 **현재 동작**을 못박은 change-detector다.
    /// 세로 스와이프를 월 이동으로 쓰는 것이 의도인지 확인이 남아 있고, 결정이 바뀌면 여기서 먼저 실패한다.
    /// 사용자가 의도된 동작으로 확인했으므로(백로그 N-002) 결함으로 다루지 않는다.
    @MainActor
    func testB4L1UpDragMovesToNextMonth() {
        launchSeeded()
        let nextMonth = TestClock.monthDate(byAdding: 1, day: 15)

        dragCalendar(horizontal: 0, vertical: -80)

        waitForMonth(nextMonth)
    }

    /// 원장 L1(설계 확인 필요)의 **현재 동작**을 못박은 change-detector다.
    /// 세로 스와이프를 월 이동으로 쓰는 것이 의도인지 확인이 남아 있고, 결정이 바뀌면 여기서 먼저 실패한다.
    /// 사용자가 의도된 동작으로 확인했으므로(백로그 N-002) 결함으로 다루지 않는다.
    @MainActor
    func testB4L1DownDragMovesToPreviousMonth() {
        launchSeeded()
        let previousMonth = TestClock.monthDate(byAdding: -1, day: 15)

        dragCalendar(horizontal: 0, vertical: 80)

        waitForMonth(previousMonth)
    }

    /// 30×30pt는 벡터 길이 42라 `DragGesture(minimumDistance: 24)`에는 잡히지만,
    /// `handleSwipe`의 `max(abs(x), abs(y)) >= 40`에는 어느 축도 못 미쳐 월이 움직이면 안 된다.
    ///
    /// "안 바뀐다"를 확인하려고 연월 피커를 열었다 저장하면 안 된다 —
    /// 저장이 월을 원래 값으로 다시 설정하므로 **실제로 잘못 이동한 회귀까지 되돌려 통과시킨다.**
    /// 대신 일정 시간 동안 헤더가 원래 값에서 벗어나지 않는지를 inverted expectation으로 직접 본다.
    @MainActor
    func testDiagonalThirtyPointDragDoesNotCrossAxisThreshold() {
        launchSeeded()
        let originalTitle = TestClock.monthTitle(for: TestClock.today)
        XCTAssertEqual(home.monthTitle.label, originalTitle, "드래그 전 헤더가 당월이어야 한다")

        dragCalendar(horizontal: 30, vertical: 30)

        XCTAssertTrue(
            home.monthTitle.assertLabelStaysUnchanged(originalTitle),
            "각 축 40pt 미만이면 월이 바뀌면 안 된다 (실제: \(home.monthTitle.label))"
        )
        XCTAssertTrue(home.todayCell.waitForExistence(timeout: Timeout.transition), "당월 달력이 그대로 있어야 한다")

        // 양성 대조. 이게 없으면 드래그가 제스처 영역에 아예 전달되지 않아도 위 단언이 통과한다.
        // 41pt는 임계 바로 위라, 임계를 40에서 낮추는 변경도 여기서 드러난다(30은 안 움직이고 41은 움직인다).
        dragCalendar(horizontal: -41, vertical: 0)
        waitForMonth(TestClock.monthDate(byAdding: 1, day: 15))
    }

    @MainActor
    func testB2MonthHeaderPickerMovesToSpecifiedMonth() {
        launchSeeded()
        let targetDate = TestClock.monthDate(byAdding: -1, day: 15)

        setHomeMonth(to: YearMonth(date: targetDate))
        waitForMonth(targetDate)

        XCTAssertTrue(home.summaryAmount(.income).waitForLabel(Fixture.previousMonthAmountText))
        XCTAssertTrue(home.calendarDay(15).waitForLabelContaining(Fixture.previousMonthAmountText))
    }

    @MainActor
    func testThreeConsecutiveLeftDragsMoveExactlyThreeMonths() {
        launchSeeded()

        for offset in 1 ... 3 {
            dragCalendar(horizontal: -100, vertical: 0)
            waitForMonth(TestClock.monthDate(byAdding: offset, day: 15))
        }
    }
}

// MARK: - Step 5 · HomeUITests

final class HomeUITests: HomeCalendarUITestCase {
    @MainActor
    // swiftlint:disable:next function_body_length
    func testA1B1B6B9B10B11B12HomeDashboard() {
        launchSeeded()

        runCase("A1 cold-start-current-month") {
            XCTAssertTrue(home.monthTitle.waitForLabel(TestClock.monthTitle(for: TestClock.today)))
            XCTAssertTrue(home.calendar.waitForExistence(timeout: Timeout.launch))
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel(Fixture.expenseText))
            XCTAssertTrue(home.historyRows.waitForCount(2), "콜드 스타트가 끝나면 오늘 내역이 채워져야 한다")
        }
        runCase("B1 korean-month-title") {
            XCTAssertEqual(home.monthTitle.label, TestClock.monthTitle(for: TestClock.today))
        }
        runCase("B6 transaction-marker") {
            XCTAssertTrue(home.todayCell.waitForExistence(timeout: Timeout.transition), "오늘 셀이 있어야 한다")
            XCTAssertTrue(home.todayCell.label.contains(Fixture.expenseText), "오늘 지출 표식이 보여야 한다")
            XCTAssertTrue(home.todayCell.label.contains(Fixture.todayIncomeText), "오늘 수입 표식이 보여야 한다")
        }
        runCase("B9 monthly-totals") {
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel(Fixture.expenseText))
            XCTAssertTrue(home.summaryAmount(.income).waitForLabel(Fixture.monthlyIncomeText))
            XCTAssertTrue(home.summaryAmount(.total).waitForLabel(Fixture.totalText))
        }
        runCase("B11 no-warning-when-everything-converts") {
            // 음성 대조. 이게 없으면 경고를 **항상** 띄우는 회귀도 아래 B11 양성 케이스를 통과한다.
            // 기준 통화 KRW + 당월은 KRW 거래뿐이라 환산 실패가 나올 수 없는 결정적 상태다.
            XCTAssertFalse(home.conversionWarning.exists, "환산 가능한 달에는 경고가 뜨면 안 된다")
        }
        runCase("B10 complete-history-row") {
            let fixtureMonth = YearMonth(year: 2024, month: 6)
            setHomeMonth(to: fixtureMonth)
            guard let fixtureDate = TestClock.date(year: 2024, month: 6, day: 15) else {
                return XCTFail("미환산 fixture 날짜를 만들 수 없다")
            }
            waitForMonth(fixtureDate)
            home.calendarDay(15).tap()
            XCTAssertTrue(home.calendarDay(15).waitForSelected())
            let row = home.historyRow(id: Fixture.unconvertedID)
            XCTAssertTrue(row.waitForExistence(timeout: Timeout.transition), "고유 USD 행이 보여야 한다")
            for expected in ["UITestUSD", "카페/음료", "체크카드", "USD 10.00"] {
                XCTAssertTrue(row.label.contains(expected), "행에 \(expected)이 보여야 한다 (실제: \(row.label))")
            }
        }

        app.terminate()
        launchSeeded(language: "en")
        runCase("B1 english-month-title") {
            XCTAssertTrue(home.monthTitle.waitForLabel(TestClock.englishMonthTitle(for: TestClock.today)))
        }

        app.terminate()
        launchSeeded(baseCurrency: "JPY")
        runCase("B11 unconverted-warning") {
            let fixtureMonth = YearMonth(year: 2024, month: 6)
            setHomeMonth(to: fixtureMonth)
            guard let fixtureDate = TestClock.date(year: 2024, month: 6, day: 15) else {
                return XCTFail("미환산 fixture 날짜를 만들 수 없다")
            }
            waitForMonth(fixtureDate)
            XCTAssertTrue(
                home.conversionWarning.waitForLabel(Fixture.conversionWarning),
                "미환산 거래 경고가 원문 그대로 보여야 한다"
            )
        }

        app.terminate()
        launchSeeded()
        runCase("B12 empty-month") {
            let emptyMonth = TestClock.monthDate(byAdding: 4, day: 15)
            setHomeMonth(to: YearMonth(date: emptyMonth))
            waitForMonth(emptyMonth)
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"))
            XCTAssertTrue(home.summaryAmount(.income).waitForLabel("0"))
            XCTAssertTrue(home.summaryAmount(.total).waitForLabel("0"))
            XCTAssertTrue(home.calendarDays.waitForCount(TestClock.dayCount(in: emptyMonth)))
            for index in 0 ..< home.calendarDays.count {
                let cell = home.calendarDays.element(boundBy: index)
                let day = cell.identifier.replacingOccurrences(of: "main.calendar.day.", with: "")
                XCTAssertEqual(cell.label, day, "거래 없는 달의 날짜 셀에는 금액 표식이 없어야 한다")
            }
            assertHistoryIsEmpty("거래 없는 달의 내역은 비어야 한다")
        }
    }

    @MainActor
    func testB5CalendarGridMatchesMonthLengthAndWeekdayAlignment() {
        let targets = [
            (YearMonth(year: 2024, month: 1), 31, "31-day"),
            (YearMonth(year: 2024, month: 4), 30, "30-day"),
            (YearMonth(year: 2025, month: 2), 28, "common-february"),
            (YearMonth(year: 2024, month: 2), 29, "leap-february")
        ]

        for (target, expectedDays, name) in targets {
            app.terminate()
            launchSeeded()
            runCase("B5 \(name)") {
                setHomeMonth(to: target)
                guard let date = TestClock.date(year: target.year, month: target.month, day: 1) else {
                    return XCTFail("검증 월 날짜를 만들 수 없다")
                }
                waitForMonth(date)
                assertCalendar(target, expectedDays: expectedDays)
            }
        }
    }

    private func assertCalendar(_ target: YearMonth, expectedDays: Int) {
        XCTAssertTrue(home.calendarDays.waitForCount(expectedDays), "해당 월 날짜 수가 \(expectedDays)여야 한다")
        XCTAssertTrue(home.calendarDay(expectedDays).exists, "마지막 날짜가 달력에 있어야 한다")

        let firstY = home.calendarDay(1).frame.midY
        let wrapDay = (2 ... min(7, expectedDays)).first { home.calendarDay($0).frame.midY > firstY + 1 }
        let observedLeadingBlanks = wrapDay.map { 8 - $0 } ?? 0
        XCTAssertEqual(
            observedLeadingBlanks,
            TestClock.leadingBlankCount(year: target.year, month: target.month),
            "1일의 요일 열 정렬이 달력 계산과 일치해야 한다"
        )
    }
}

// MARK: - Step 7 · 설정 진입 공통

class SettingsUITestCase: HomeCalendarUITestCase {
    fileprivate var settings: SettingsScreen {
        SettingsScreen(app: app)
    }

    func openSettings() {
        home.settingsButton.tap()
        XCTAssertTrue(settings.baseCurrencyRow.waitForExistence(timeout: Timeout.transition), "설정 화면이 열려야 한다")
    }

    /// 설정·언어·법적 고지 화면은 네비게이션 바를 숨겨 시스템 back이 없다. 세 화면이 공유하는 헤더 버튼으로 돌아간다.
    func goBack() {
        XCTAssertTrue(settings.backButton.waitForHittable(), "헤더 뒤로가기 버튼이 있어야 한다")
        settings.backButton.tap()
    }

    /// 화면에 남아 있는 한국어 문구. 문구를 하나씩 나열하는 방식은 나열하지 않은 문구가
    /// 한국어로 남는 회귀를 놓치므로 전수로 훑는다. 시드 메모·식별자는 모두 ASCII다.
    ///
    /// XCUITest 질의는 **요소 유형 단위**라 유형을 명시해야 한다. 사용자가 읽는 문구가 실릴 수 있는
    /// 네 유형을 모두 넣고, 라벨뿐 아니라 **접근성 값**(`value`)도 본다 — 오늘 셀처럼 값으로만
    /// 문구를 노출하는 요소가 있어서다(`MonthCalendarGrid`). 유형을 좁히면 그만큼 회귀를 놓친다.
    func koreanLabels(in scope: XCUIElement? = nil) -> [String] {
        let korean = NSPredicate(format: "label MATCHES %@ OR value MATCHES %@", ".*[가-힣].*", ".*[가-힣].*")
        // `app`이 암시적 언래핑 옵셔널이라 명시하지 않으면 `XCUIElement?`로 추론된다.
        let root: XCUIElement = scope ?? app
        let queries = [root.staticTexts, root.buttons, root.textFields, root.otherElements]
        return queries.flatMap { query in
            query.matching(korean).allElementsBoundByIndex.map { element in
                element.label.isEmpty ? (element.value as? String ?? "") : element.label
            }
        }
    }
}

// MARK: - Step 7 · BaseCurrencyUITests

final class BaseCurrencyUITests: SettingsUITestCase {
    /// 설정 화면으로 기준 통화를 바꾼 테스트만 true. 기준 통화는 런치 인자와 달리 앱 도메인에 영구 저장된다.
    private var didChangeBaseCurrency = false

    override func tearDownWithError() throws {
        if didChangeBaseCurrency {
            didChangeBaseCurrency = false
            restoreBaseCurrencyToKRW()
        }
        try super.tearDownWithError()
    }

    /// F1 — 시드의 2025-07에는 USD 1건뿐이라 "환산해서 합산"과 "그냥 표시"가 같은 결과를 낸다.
    /// 같은 날짜에 KRW 수입을 하나 넣어 **두 통화가 함께 더해지는지**로 가른다.
    /// 지출 13,922 = 10.00 USD × 1392.28(저장 환율, 소수 절삭) · 수입 20,000 · 합계 6,077.
    @MainActor
    func testF1KRWBaseSumsLocalAndForeignTransactions() {
        guard let fixtureDate = TestClock.date(year: 2025, month: 7, day: 15) else {
            return XCTFail("환율 fixture 날짜를 만들 수 없다")
        }
        launchSeeded()

        openNewEntry()
        entry.tab(.income).tap()
        XCTAssertTrue(entry.tab(.income).waitForSelected(), "수입 탭으로 바뀌어야 한다")
        setEntryDate(to: fixtureDate)
        typeAmount("20000")
        XCTAssertTrue(entry.amountField.waitForValue("20000"))
        selectRequiredEntryFields(categoryId: Fixture.incomeCategoryID)
        entry.submitButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition), "저장 후 홈으로 돌아와야 한다")

        setHomeMonth(to: YearMonth(date: fixtureDate))
        waitForMonth(fixtureDate)

        runCase("F1 krw-base-mixed-currency-totals") {
            XCTAssertTrue(home.summaryAmount(.income).waitForLabel("20,000"), "KRW 수입은 액면 그대로 합산돼야 한다")
            XCTAssertTrue(
                home.summaryAmount(.expense).waitForLabel("13,922"),
                "USD 지출이 KRW로 환산돼 합산돼야 한다 (실제: \(home.summaryAmount(.expense).label))"
            )
            XCTAssertTrue(home.summaryAmount(.total).waitForLabel("6,077"), "합계는 수입 − 환산 지출이어야 한다")
            XCTAssertFalse(home.conversionWarning.exists, "모두 환산된 달에는 경고가 뜨면 안 된다")
        }
    }

    /// F2 · F3 — 설정에서 기준 통화를 바꾸면 홈이 **돌아온 즉시** 새 기준으로 재환산돼 있다.
    /// 2025-07-15 CNY 시드 tts 194.12(1 단위) → 13,922.80 ÷ 194.12 = 71.7226… → CNY 2자리 절삭 71.72.
    @MainActor
    func testF2F3ChangingBaseCurrencyReconvertsHomeImmediately() {
        guard let fixtureDate = TestClock.date(year: 2025, month: 7, day: 15) else {
            return XCTFail("환율 fixture 날짜를 만들 수 없다")
        }
        launchSeeded()
        setHomeMonth(to: YearMonth(date: fixtureDate))
        waitForMonth(fixtureDate)
        home.calendarDay(15).tap()
        XCTAssertTrue(home.calendarDay(15).waitForSelected(), "거래 날짜를 선택해야 내역이 보인다")

        let row = home.historyRow(id: Fixture.convertedUSDID)
        XCTAssertTrue(row.waitForLabelContaining("13,922"), "변경 전 내역은 KRW 환산액이어야 한다")
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("13,922"), "변경 전 합계는 KRW 기준이어야 한다")

        openSettings()
        changeBaseCurrency(label: "중국, CNY", code: "CNY")
        goBack()

        runCase("F3 home-updates-without-manual-refresh") {
            XCTAssertTrue(
                home.summaryAmount(.expense).waitForLabel("71.72"),
                "설정에서 돌아온 즉시 CNY 기준 합계여야 한다 (실제: \(home.summaryAmount(.expense).label))"
            )
            XCTAssertTrue(
                home.monthTitle.waitForLabel(TestClock.monthTitle(for: fixtureDate)),
                "기준 통화만 바뀌고 보던 달은 유지돼야 한다"
            )
        }
        runCase("F2 history-row-reconverted") {
            XCTAssertTrue(row.waitForLabelContaining("71.72"), "내역 금액도 CNY 기준으로 재환산돼야 한다")
            XCTAssertTrue(row.label.contains("USD 10.00"), "원 통화 금액은 그대로 보여야 한다")
            XCTAssertFalse(row.label.contains("13,922"), "이전 기준 통화 금액이 남으면 안 된다")
        }
    }

    /// F4 — 기준이 비-KRW일 때 환산 못 한 거래가 경고로 드러나고 합계에서 빠진다.
    /// 2024-06-15는 환율 스냅샷 시작(2024-07-29) 이전이라 **어떤 통화도** 환산할 수 없다.
    /// 그래서 같은 달의 대조군은 기준 통화와 같은 통화(JPY)로 만든다 — 환율 없이도 액면으로 합산된다.
    @MainActor
    func testF4NonKRWBaseWarnsAndSumsOnlyConvertibleTransactions() {
        guard let unconvertibleDate = TestClock.date(year: 2024, month: 6, day: 15),
              let convertibleDate = TestClock.date(year: 2025, month: 7, day: 15)
        else {
            return XCTFail("fixture 날짜를 만들 수 없다")
        }
        // 기준 통화는 런치 인자로만 고정한다(NSArgumentDomain이라 영구 저장되지 않는다).
        launchSeeded(baseCurrency: "JPY")

        openNewEntry()
        selectCurrency(label: "일본, JPY", code: "JPY")
        setEntryDate(to: unconvertibleDate)
        typeAmount("5000")
        XCTAssertTrue(entry.amountField.waitForValue("5000"))
        selectRequiredEntryFields()
        entry.submitButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition), "저장 후 홈으로 돌아와야 한다")

        setHomeMonth(to: YearMonth(date: unconvertibleDate))
        waitForMonth(unconvertibleDate)

        runCase("F4 warning-and-partial-total") {
            XCTAssertTrue(home.conversionWarning.waitForLabel(Fixture.conversionWarning), "미환산 거래 경고가 떠야 한다")
            XCTAssertTrue(
                home.summaryAmount(.expense).waitForLabel("5,000"),
                "환산 가능한 JPY 거래만 합산돼야 한다 (실제: \(home.summaryAmount(.expense).label))"
            )
        }
        runCase("F4 unconvertible-entry-stays-in-history") {
            home.calendarDay(15).tap()
            XCTAssertTrue(home.calendarDay(15).waitForSelected())
            XCTAssertTrue(home.historyRows.waitForCount(2), "환산 못 한 거래도 내역에는 남아야 한다")
            XCTAssertTrue(
                home.historyRow(id: Fixture.unconvertedID).waitForLabelContaining("USD 10.00"),
                "환산 못 한 거래는 원 통화로 표시돼야 한다"
            )
        }
        // 경고를 **항상** 띄우는 회귀는 위 단언만으로는 잡히지 않는다. 같은 기준 통화에서 경고가 없는 달까지 본다.
        // 2025-07-15 JPY tts 941.84(100엔 단위) → 13,922.80 ÷ 9.4184 = 1,478.25… → JPY 0자리 절삭 1,478.
        runCase("F4 convertible-month-has-no-warning") {
            setHomeMonth(from: YearMonth(date: unconvertibleDate), to: YearMonth(date: convertibleDate))
            waitForMonth(convertibleDate)
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("1,478"), "JPY 기준으로 환산돼야 한다")
            XCTAssertFalse(home.conversionWarning.exists, "환산 가능한 달에는 경고가 뜨면 안 된다")
        }
    }

    private func changeBaseCurrency(label: String, code: String) {
        settings.baseCurrencyRow.tap()
        let option = entry.currencyOption(label)
        XCTAssertTrue(option.waitForHittable(), "기준 통화 시트에서 \(label)을 탭할 수 있어야 한다")
        // 영구 저장을 일으키기 **직전에** 표시해 이 지점 이후 어디서 실패해도 teardown이 되돌린다.
        didChangeBaseCurrency = true
        option.tap()
        XCTAssertTrue(settings.baseCurrencyRow.waitForLabelContaining(code), "설정 행이 \(code)로 바뀌어야 한다")
    }

    /// 어느 화면에서 멈췄든 되돌릴 수 있도록 앱을 새로 띄운 뒤 설정 화면을 거쳐 KRW로 되돌린다.
    /// `-woni.app.baseCurrency`는 붙이지 않는다 — 인자 도메인이 이기면 저장된 값을 확인·수정할 수 없다.
    private func restoreBaseCurrencyToKRW() {
        app.terminate()
        app.launchArguments = [
            UITestFlags.enable,
            "-woni.app.language.override", "ko",
            "-woni.app.lastUsedCurrency", "KRW"
        ]
        app.launch()
        home.waitForReady()
        openSettings()
        settings.baseCurrencyRow.tap()
        let krw = entry.currencyOption("대한민국, KRW")
        XCTAssertTrue(krw.waitForHittable(), "기준 통화 시트가 열려야 한다")
        krw.tap()
        XCTAssertTrue(settings.baseCurrencyRow.waitForLabelContaining("KRW"), "기준 통화를 KRW로 되돌려야 한다")
    }
}

// MARK: - Step 7 · LanguageUITests

final class LanguageUITests: SettingsUITestCase {
    /// 언어 화면에서 언어를 바꾼 테스트만 true. 언어도 기준 통화처럼 앱 도메인에 영구 저장된다.
    private var didChangeLanguage = false

    override func tearDownWithError() throws {
        if didChangeLanguage {
            didChangeLanguage = false
            restoreLanguageToKorean()
        }
        try super.tearDownWithError()
    }

    @MainActor
    func testG1LanguageSwitchAppliesToSettingsHomeAndEntry() {
        launchSeeded()
        openSettings()
        XCTAssertTrue(settings.baseCurrencyRow.waitForLabelContaining("기본 통화"), "한국어 상태에서 시작해야 한다")

        selectLanguage("en")
        runCase("G1 language-screen-switches-in-place") {
            XCTAssertTrue(
                app.staticTexts["Language"].waitForExistence(timeout: Timeout.transition),
                "선택 즉시 보고 있던 화면 문구가 영어로 바뀌어야 한다"
            )
            XCTAssertFalse(app.staticTexts["언어 설정"].exists, "한국어 제목이 남으면 안 된다")
        }

        goBack()
        runCase("G1 settings-in-english") {
            assertSettingsIsEnglish()
        }
        goBack()
        runCase("G1 home-in-english") {
            assertHomeIsEnglish()
        }
        openNewEntry()
        runCase("G1 entry-in-english") {
            assertEntryIsEnglish()
        }
        entry.closeButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition), "입력 화면을 닫으면 홈으로 돌아와야 한다")

        openSettings()
        selectLanguage("ko")
        runCase("G1 switch-back-to-korean") {
            XCTAssertTrue(
                app.staticTexts["언어 설정"].waitForExistence(timeout: Timeout.transition),
                "반대 방향 전환도 즉시 반영돼야 한다"
            )
            XCTAssertFalse(app.staticTexts["Language"].exists, "영어 제목이 남으면 안 된다")
        }
        goBack()
        goBack()
        XCTAssertTrue(
            home.monthTitle.waitForLabel(TestClock.monthTitle(for: TestClock.today)),
            "홈 월 헤더도 한국어 표기로 돌아와야 한다 (실제: \(home.monthTitle.label))"
        )
    }

    /// G2 — 언어는 런치 인자로만 고정한다(영구 저장되지 않아 오염이 없다).
    /// 히스토리 행에는 날짜 표기가 없어 월 헤더와 입력 화면 날짜 행으로 판정한다(원장 「자동화 커버리지 한계」).
    @MainActor
    func testG2DateFormatsFollowLanguage() {
        launchSeeded(language: "en")
        runCase("G2 english-date-formats") {
            XCTAssertTrue(
                home.monthTitle.waitForLabel(TestClock.englishMonthTitle(for: TestClock.today)),
                "월 헤더가 영어 형식이어야 한다 (실제: \(home.monthTitle.label))"
            )
            openNewEntry()
            XCTAssertTrue(
                entry.dateRow.waitForLabel(TestClock.englishFullDate(for: TestClock.today)),
                "날짜 행이 영어 형식이어야 한다 (실제: \(entry.dateRow.label))"
            )
        }

        app.terminate()
        launchSeeded(language: "ko")
        runCase("G2 korean-date-formats") {
            XCTAssertTrue(
                home.monthTitle.waitForLabel(TestClock.monthTitle(for: TestClock.today)),
                "월 헤더가 한국어 형식이어야 한다 (실제: \(home.monthTitle.label))"
            )
            openNewEntry()
            XCTAssertTrue(
                entry.dateRow.waitForLabel(TestClock.fullDate(for: TestClock.today)),
                "날짜 행이 한국어 형식이어야 한다 (실제: \(entry.dateRow.label))"
            )
        }
    }

    @MainActor
    func testG3CategoryAndAssetNamesFollowLanguage() {
        launch(language: "en")
        openNewEntry()
        runCase("G3 english-catalog-names") {
            XCTAssertTrue(entry.categoryChip(1).waitForLabelContaining("Food & Dining"), "카테고리가 영어여야 한다")
            XCTAssertTrue(entry.assetChip(1).waitForLabelContaining("Credit Card"), "자산이 영어여야 한다")
            assertChipCounts()
            // 개별 칩만 보면 나머지 칩에 한국어가 남아도 통과한다. 화면 전체로 못 박는다.
            assertNoKoreanText("영어 입력 화면")
        }

        app.terminate()
        launch(language: "ko")
        openNewEntry()
        runCase("G3 korean-catalog-names") {
            XCTAssertTrue(entry.categoryChip(1).waitForLabelContaining("식비"), "카테고리가 한국어여야 한다")
            XCTAssertTrue(entry.assetChip(1).waitForLabelContaining("신용카드"), "자산이 한국어여야 한다")
            assertChipCounts()
            // 영어 화면의 "한국어 없음" 단언이 실제로 판별력이 있는지 같은 질의로 확인한다.
            // 한국어 화면에서도 아무것도 잡히지 않는다면 그 질의는 처음부터 실패할 수 없는 단언이다.
            XCTAssertFalse(koreanLabels().isEmpty, "한국어 화면에서는 한국어 문구가 잡혀야 한다(탐지 질의 자체 검증)")
        }
    }

    /// G4 — 두 번째 실행에서 `-woni.app.language.override`를 빼고 저장된 값만으로 뜨는지 본다.
    /// 저장을 읽지 못하면 `AppLanguage.resolved(from: .current)` 시스템 폴백으로 떨어지므로,
    /// **폴백과 다른 언어**가 나와야 단언이 회귀를 잡는다. 그래서 매 실행 시스템 언어를 반대로 고정하고,
    /// `-AppleLanguages`가 먹지 않는 경우까지 대비해 두 방향(영어 유지·한국어 유지)을 모두 본다 —
    /// 시뮬레이터 기본 로케일이 영어라, 한국어 유지 쪽은 그 인자와 무관하게 폴백과 갈린다.
    @MainActor
    func testG4SelectedLanguagePersistsAcrossRelaunch() {
        launchForPersistence(languageOverride: "ko")
        openSettings()
        selectLanguage("en")
        XCTAssertTrue(
            app.staticTexts["Language"].waitForExistence(timeout: Timeout.transition),
            "종료 전에 영어로 바뀐 것을 확인해야 한다"
        )

        app.terminate()
        launchForPersistence(languageOverride: nil)
        runCase("G4 english-persists-after-relaunch") {
            XCTAssertTrue(
                home.monthTitle.waitForLabel(TestClock.englishMonthTitle(for: TestClock.today)),
                "재실행 후에도 영어로 시작해야 한다 (실제: \(home.monthTitle.label))"
            )
        }

        openSettings()
        selectLanguage("ko")
        XCTAssertTrue(
            app.staticTexts["언어 설정"].waitForExistence(timeout: Timeout.transition),
            "종료 전에 한국어로 바뀐 것을 확인해야 한다"
        )

        app.terminate()
        launchForPersistence(languageOverride: nil, systemLanguage: "en")
        runCase("G4 korean-persists-after-relaunch") {
            XCTAssertTrue(
                home.monthTitle.waitForLabel(TestClock.monthTitle(for: TestClock.today)),
                "한국어를 고른 뒤 재실행하면 한국어로 시작해야 한다 (실제: \(home.monthTitle.label))"
            )
        }
    }

    private func selectLanguage(_ code: String) {
        settings.languageRow.tap()
        let option = settings.languageOption(code)
        XCTAssertTrue(option.waitForHittable(), "언어 화면에 \(code) 옵션이 있어야 한다")
        // 영구 저장을 일으키기 **직전에** 표시해 이 지점 이후 어디서 실패해도 teardown이 되돌린다.
        didChangeLanguage = true
        option.tap()
    }

    private func assertSettingsIsEnglish() {
        XCTAssertTrue(settings.baseCurrencyRow.waitForLabelContaining("Main Currency"), "기본 통화 행이 영어여야 한다")
        XCTAssertTrue(settings.languageRow.waitForLabel("Language"), "언어 행이 영어여야 한다")
        XCTAssertTrue(settings.supportRow.waitForLabel("Customer Service"), "고객센터 행이 영어여야 한다")
        XCTAssertTrue(settings.termsRow.waitForLabel("Terms of Service"), "약관 행이 영어여야 한다")
        XCTAssertTrue(settings.privacyRow.waitForLabel("Privacy Policy"), "개인정보 행이 영어여야 한다")
        XCTAssertTrue(app.staticTexts["App Version"].exists, "앱 버전 제목이 영어여야 한다")
        assertNoKoreanText("설정 화면")
    }

    private func assertHomeIsEnglish() {
        XCTAssertTrue(
            home.monthTitle.waitForLabel(TestClock.englishMonthTitle(for: TestClock.today)),
            "월 헤더가 영어 형식이어야 한다 (실제: \(home.monthTitle.label))"
        )
        for title in ["Expense", "Income", "Total"] {
            XCTAssertTrue(app.staticTexts[title].exists, "합계 제목 \(title)이 영어여야 한다")
        }
        // 내역이 비어 있으면 카테고리·자산 문구가 화면에 없어 아래 전수 검사가 헐거워진다.
        XCTAssertTrue(home.historyRows.waitForCount(2), "시드 내역이 보이는 상태에서 판정해야 한다")
        assertNoKoreanText("홈 화면")
    }

    private func assertEntryIsEnglish() {
        XCTAssertTrue(
            entry.dateRow.waitForLabel(TestClock.englishFullDate(for: TestClock.today)),
            "날짜 행이 영어 형식이어야 한다 (실제: \(entry.dateRow.label))"
        )
        for title in ["CATEGORY", "PROPERTY", "MEMO"] {
            XCTAssertTrue(app.staticTexts[title].exists, "입력 화면 제목 \(title)이 영어여야 한다")
        }
        assertNoKoreanText("입력 화면")
    }

    /// 이름만 확인하면 칩이 빠지거나 늘어나는 회귀를 놓친다. 언어와 무관한 개수로 상한까지 못 박는다.
    private func assertChipCounts() {
        XCTAssertTrue(
            entry.chips(prefix: "entry.category.").waitForCount(Fixture.expenseCategoryCount),
            "지출 카테고리 칩은 \(Fixture.expenseCategoryCount)개여야 한다"
        )
        XCTAssertTrue(
            entry.chips(prefix: "entry.asset.").waitForCount(Fixture.assetCount),
            "자산 칩은 \(Fixture.assetCount)개여야 한다"
        )
    }

    private func assertNoKoreanText(_ context: String) {
        let labels = koreanLabels()
        XCTAssertTrue(labels.isEmpty, "\(context)에 한국어가 남으면 안 된다: \(labels)")
    }

    /// 저장된 언어만으로 뜨는지 보기 위해 override 인자를 선택적으로 뺀다.
    /// `systemLanguage`는 저장을 읽지 못했을 때의 폴백을 결정한다 — 기대값과 반대로 둬야 단언이 갈린다.
    private func launchForPersistence(languageOverride: String?, systemLanguage: String = "ko") {
        app.launchArguments = [
            UITestFlags.enable,
            "-woni.app.baseCurrency", "KRW",
            "-woni.app.lastUsedCurrency", "KRW",
            "-AppleLanguages", "(\(systemLanguage))",
            "-AppleLocale", systemLanguage == "ko" ? "ko_KR" : "en_US"
        ]
        if let languageOverride {
            app.launchArguments += ["-woni.app.language.override", languageOverride]
        }
        app.launch()
        home.waitForReady()
    }

    /// 어느 화면에서 멈췄든 되돌릴 수 있도록 앱을 새로 띄운 뒤 언어 화면에서 한국어로 되돌린다.
    private func restoreLanguageToKorean() {
        app.terminate()
        launchForPersistence(languageOverride: nil)
        openSettings()
        settings.languageRow.tap()
        let korean = settings.languageOption("ko")
        XCTAssertTrue(korean.waitForHittable(), "언어 화면이 열려야 한다")
        korean.tap()
        XCTAssertTrue(
            app.staticTexts["언어 설정"].waitForExistence(timeout: Timeout.transition),
            "언어를 한국어로 되돌려야 한다"
        )
    }
}

// MARK: - Step 7 · SettingsUITests

final class SettingsUITests: SettingsUITestCase {
    /// J1·J6은 로그인 세션에서만 노출되는 행이라 익명 상태로 도는 이 스위트의 범위 밖이다.
    /// 여기서는 "로그아웃 상태에서 노출되지 않는다"는 절반만 덮고 나머지는 원장의 manual 항목으로 둔다.
    ///
    /// J3·J4(약관·방침 전문)는 문서가 Notion 게시본을 여는 `SFSafariViewController`로 바뀌면서 빠졌다.
    /// 웹 콘텐츠는 별도 프로세스라 XCUITest가 본문을 읽지 못하고, 시스템 브라우저 UI와 네트워크에
    /// 의존해 판정이 흔들린다. 대신 언어별 URL 분기는 `LegalLinkTests`(unit)가, 실제 문서가 보이는지는
    /// 원장의 manual 항목이 덮는다.
    @MainActor
    func testJ1J2J5SettingsInformationRows() {
        launch()
        openSettings()

        runCase("J1 my-info-hidden-when-anonymous") {
            XCTAssertTrue(settings.supportRow.exists, "설정 본문이 그려진 상태에서 판정해야 한다")
            XCTAssertFalse(app.staticTexts["내 정보"].exists, "익명 상태에서는 내 정보 행이 없어야 한다")
        }
        runCase("J2 app-version-row") {
            assertAppVersionRow()
        }
        runCase("J5 support-opens-document") {
            assertSupportRowOpensDocument()
        }
    }

    /// 소셜로그인이 곧 이용계약 체결이라(약관 제4조 1항) 동의 대상 문서를 로그인 시트에서 바로 열 수 있어야 한다.
    /// OAuth는 태울 수 없으므로 시트 진입과 두 문서 링크가 놓여 있는지까지만 검증한다.
    /// 링크를 누르면 Notion 게시본이 `SFSafariViewController`로 열리는데, 웹 콘텐츠는 별도 프로세스라
    /// XCUITest가 읽지 못하고 시스템 브라우저 UI·네트워크에 의존해 판정이 흔들린다 — 탭 이후는 manual로 둔다.
    /// 설정 화면에도 같은 이름의 행이 있어 라벨로 집으면 어느 쪽인지 흐려진다 — 링크는 식별자로 집는다.
    @MainActor
    func testLoginSheetShowsLegalDocumentLinks() {
        launch()
        openSettings()
        XCTAssertTrue(settings.loginRow.waitForHittable(), "게스트에게는 로그인/회원가입 행이 보여야 한다")
        settings.loginRow.tap()

        XCTAssertTrue(
            app.staticTexts[LegalFixture.loginConsentNotice].waitForExistence(timeout: Timeout.transition),
            "로그인 시트에 동의 안내가 보여야 한다"
        )
        XCTAssertTrue(settings.loginTermsLink.waitForHittable(), "약관 링크를 누를 수 있어야 한다")
        XCTAssertTrue(settings.loginPrivacyLink.isHittable, "개인정보 보호정책 링크도 같은 자리에 있어야 한다")
    }

    /// 앱 버전 행은 액션이 없어 Button이 아니다 — 제목과 값이 별개 staticText라 같은 행에 붙어 있는지까지 본다.
    /// 기대값은 테스트 번들의 짧은 버전이다. 두 타깃 모두 프로젝트의 `MARKETING_VERSION`을 쓰므로 함께 움직인다.
    private func assertAppVersionRow() {
        let bundleVersion = Bundle(for: WoniAppUITestCase.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String
        guard let expected = bundleVersion,
              expected.range(of: "^[0-9]+(\\.[0-9]+)+$", options: .regularExpression) != nil
        else {
            return XCTFail("테스트 번들에서 빌드 버전을 읽지 못했다 (실제: \(bundleVersion ?? "nil"))")
        }

        let title = app.staticTexts["앱 버전"]
        XCTAssertTrue(title.waitForExistence(timeout: Timeout.transition), "앱 버전 행이 보여야 한다")
        let version = app.staticTexts[expected]
        XCTAssertTrue(version.exists, "빌드된 버전 \(expected)이 표시돼야 한다")
        XCTAssertEqual(version.frame.midY, title.frame.midY, accuracy: 1, "버전 값이 앱 버전 행에 붙어 있어야 한다")
    }

    /// 고객센터는 준비 중 안내를 띄우던 데서 지원 페이지를 여는 인앱 브라우저로 바뀌었다.
    /// 약관·방침과 같은 이유로 문서 **본문**은 판정하지 않는다 — 웹 콘텐츠는 별도 프로세스라
    /// XCUITest가 읽지 못하고 네트워크에 의존해 판정이 흔들린다.
    ///
    /// 대신 브라우저가 설정 화면을 덮는 것까지는 앱 프로세스 안에서 관측된다. 이 단언이 없으면
    /// 링크가 `nil`로 만들어져 눌러도 아무 일이 없는 회귀(오탈자 한 글자면 난다)를 놓친다.
    private func assertSupportRowOpensDocument() {
        settings.supportRow.tap()
        XCTAssertTrue(settings.supportRow.waitForNonHittable(), "고객센터를 누르면 문서 화면이 덮어야 한다")
    }
}

// MARK: - Step 8 · DisplayMatrixUITests

/// K2 · K4 — 표시 환경. **iPhone SE (3rd generation) 전용**이라 코어 스위트에서 `-skip-testing`으로 제외된다.
///
/// 레이아웃 "깨짐"을 픽셀로 판정하지 않는다. 기기·런타임에 따라 흔들려 게이트가 무의미해지기 때문이다.
/// 대신 **필수 조작 요소의 도달 가능성**(화면 밖이면 스크롤해서 닿는 것까지 포함)과
/// **라벨이 온전하고 화면 폭 안에 있는지**로 판정한다.
final class DisplayMatrixUITests: SettingsUITestCase {
    /// 접근성 텍스트 최대 크기. Xcode 스킴의 Dynamic Type 옵션이 쓰는 UIKit 런치 인자와 같다.
    private static let largeTextArguments = [
        "-UIPreferredContentSizeCategoryName",
        UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
    ]

    /// iPhone SE (3rd generation)의 논리 폭. 이보다 넓은 기기에서 돌면 K4가 아무것도 검증하지 못한다.
    private static let smallScreenMaxWidth: CGFloat = 375

    /// 하나라도 도달하지 못하면 거래를 만들 수 없는 입력 화면의 필수 조작 요소. 화면 위→아래 순서다.
    /// 순서가 뒤섞이면 스크롤이 왕복해 판정이 흔들리므로 폼 순서를 그대로 따른다.
    private var essentialControls: [(name: String, element: XCUIElement)] {
        [
            ("저장 버튼", entry.submitButton),
            ("지출 탭", entry.tab(.expense)),
            ("수입 탭", entry.tab(.income)),
            ("날짜 행", entry.dateRow),
            ("통화 버튼", entry.currencyButton),
            ("금액 필드", entry.amountField),
            ("카테고리 칩", entry.categoryChip(1)),
            ("자산 칩", entry.assetChip(1)),
            ("메모 필드", entry.memoField)
        ]
    }

    @MainActor
    func testK4SmallScreenKeepsEntryScreenOperable() {
        launch()
        assertRunningOnSmallScreen()
        openNewEntry()

        // 원장 K4의 전제는 "키패드 올린 상태"다. 키패드가 없으면 가장 좁은 조건을 비켜 간다.
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "키패드가 올라와야 한다")
        assertEntryScreenIsOperable()
    }

    @MainActor
    func testK2LargeTextKeepsEntryScreenOperable() {
        launch(extraArguments: Self.largeTextArguments)
        assertRunningOnSmallScreen()
        openNewEntry()

        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: Timeout.transition), "키패드가 올라와야 한다")
        assertEntryScreenIsOperable()
        assertLabelsAreComplete()
    }

    /// K2 대조 — 큰 글씨 런치 인자가 앱 프로세스에 **실제로 먹었는지** 확인한다.
    /// 이 대조가 없으면 인자가 무시돼도 위 K2 단언이 전부 통과해 기본 크기 실행과 구분되지 않는다.
    ///
    /// 앱 문구는 Dynamic Type을 따르지 않는다 — `WoniTypography`가 `.custom(_:fixedSize:)`를,
    /// 아이콘이 `.system(size:)`를 쓴다. 그래서 대조는 앱이 그리지 않는 **시스템 경고창**으로 세운다.
    /// 앱 문구가 커지지 않는 것은 접근성 공백이라 백로그에 기록했다(`defect-backlog.md` D-006).
    /// 고정 폰트를 걷어내면 두 번째 단언이 깨지고, 그때 K2 레이아웃을 실제로 다시 봐야 한다.
    @MainActor
    func testK2LargeTextArgumentReachesTheAppProcess() {
        let normal = measureTextHeights()
        app.terminate()
        let large = measureTextHeights(extraArguments: Self.largeTextArguments)

        XCTAssertGreaterThan(
            large.systemAlertMessage,
            normal.systemAlertMessage,
            "큰 글씨 인자가 먹었다면 시스템 경고창 문구가 커져야 한다 "
                + "(기본 \(normal.systemAlertMessage) · 큰 글씨 \(large.systemAlertMessage))"
        )
        XCTAssertEqual(
            large.appDateRow,
            normal.appDateRow,
            accuracy: 1,
            "앱 문구는 고정 크기 폰트라 큰 글씨를 따르지 않는다(D-006). "
                + "커졌다면 고정 폰트가 걷혔다는 뜻이므로 K2 레이아웃을 다시 봐야 한다"
        )
    }

    private struct MeasuredHeights {
        let systemAlertMessage: CGFloat
        let appDateRow: CGFloat
    }

    /// 시스템이 그리는 문구(데이터 삭제 확인 경고창)와 앱이 그리는 문구(입력 화면 날짜 행)의 높이를
    /// 한 실행에서 잰다. 고객센터가 경고창 대신 인앱 브라우저를 열게 되면서 대조 대상을 옮겼다 —
    /// 게스트 삭제 확인은 취소로 되돌릴 수 있는 유일한 다중 행 시스템 경고창이다.
    private func measureTextHeights(extraArguments: [String] = []) -> MeasuredHeights {
        launch(extraArguments: extraArguments)

        openSettings()
        settings.withdrawRow.tap()
        let alert = app.alerts[WithdrawalFixture.guestRowTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: Timeout.transition), "삭제 확인 안내가 떠야 한다")

        // 문구를 문자열로 집지 않는다. 이 경고창은 온라인이면 삭제 확인을, 오프라인이면 연결 안내를
        // 띄우는데 어느 쪽이든 시스템이 그리는 문구라 대조 대상으로는 같다. 한쪽 문자열로 고정하면
        // 실행 기기의 네트워크 상태가 판정을 가른다(실측: 오프라인 시뮬레이터에서 연결 안내가 떴다).
        let texts = alert.staticTexts.allElementsBoundByIndex
        XCTAssertEqual(texts.count, 2, "경고창은 제목과 문구 두 줄이어야 한다 (실제: \(texts.map(\.label)))")
        let alertMessageHeight = texts.last?.frame.height ?? 0

        // 삭제 확인에는 파괴 버튼이 함께 있으므로 순번으로 집지 않는다 — 되돌리는 버튼만 라벨로 고른다.
        let dismiss = alert.buttons[WithdrawalFixture.cancel].exists
            ? alert.buttons[WithdrawalFixture.cancel]
            : alert.buttons[WithdrawalFixture.confirmOK]
        dismiss.tap()
        XCTAssertTrue(alert.waitForNonExistence(), "안내가 닫혀야 한다")

        goBack()
        XCTAssertTrue(home.addButton.waitForHittable(), "설정에서 홈으로 돌아와야 한다")
        openNewEntry()

        return MeasuredHeights(systemAlertMessage: alertMessageHeight, appDateRow: entry.dateRow.frame.height)
    }

    private func assertRunningOnSmallScreen() {
        XCTAssertLessThanOrEqual(
            app.frame.width,
            Self.smallScreenMaxWidth,
            "이 클래스는 iPhone SE 전용이다. 폭 \(app.frame.width)pt 기기에서는 작은 화면 회귀를 잡지 못한다"
        )
    }

    private func assertEntryScreenIsOperable() {
        for control in essentialControls {
            assertReachable(control.element, control.name)
        }
        assertChipsFitScreenWidth()
    }

    /// 화면 밖이면 폼을 끌어 올려 도달을 시도한다. **스크롤해서 닿는 것까지가 "온전"** 이다.
    /// `exists`만 보면 화면 밖 요소도 참이라 도달 가능성 판정이 되지 않으므로 `hittable`로 가른다.
    private func assertReachable(_ element: XCUIElement, _ name: String) {
        for _ in 0 ..< 6 where !element.isHittable {
            dragFormUp()
        }
        XCTAssertTrue(element.waitForHittable(), "\(name)에 도달할 수 있어야 한다")
        assertFitsScreenWidth(element, name)
    }

    /// 칩은 `FlowLayout`으로 줄바꿈되므로 문구가 길어지면 가로로 넘칠 수 있다.
    /// 지금은 고정 폰트라 넘치지 않지만, D-006을 고쳐 문구가 커지는 순간 이 단언이 먼저 알린다.
    private func assertChipsFitScreenWidth() {
        for prefix in ["entry.category.", "entry.asset."] {
            for chip in entry.chips(prefix: prefix).allElementsBoundByIndex {
                assertFitsScreenWidth(chip, "칩 \"\(chip.label)\"")
            }
        }
    }

    /// 가로로 화면을 넘어간 요소는 잘려 보인다. 세로는 스크롤로 도달하므로 폭만 본다.
    private func assertFitsScreenWidth(_ element: XCUIElement, _ name: String) {
        let screen = app.frame
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 1, "\(name)이 화면 왼쪽으로 넘치면 안 된다 (\(frame))")
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 1, "\(name)이 화면 오른쪽으로 넘치면 안 된다 (\(frame))")
    }

    /// 라벨이 비거나 말줄임으로 대체되지 않았는지. 값 전체와 비교해 일부만 남는 경우까지 가른다.
    private func assertLabelsAreComplete() {
        XCTAssertEqual(entry.tab(.expense).label, "지출")
        XCTAssertEqual(entry.tab(.income).label, "수입")
        XCTAssertEqual(entry.submitButton.label, "저장")
        XCTAssertEqual(entry.currencyButton.label, "KRW")
        XCTAssertEqual(entry.dateRow.label, TestClock.fullDate(for: TestClock.today))
        XCTAssertEqual(entry.memoField.value as? String, Fixture.memoPlaceholder)
    }
}

// MARK: - Step 8 · GuestEntryUITests

/// A3 — 로그인 없이(게스트) 입력·조회가 가능하다.
/// `-uiTest` 하네스가 `FakeAuthService`의 익명 신원으로 뜨므로 별도 인자가 없다.
final class GuestEntryUITests: SettingsUITestCase {
    @MainActor
    func testA3GuestSavesEntryWithoutSignIn() {
        launch()

        // 게스트임을 먼저 못박는다. 로그인 상태에서도 저장은 되므로 이 전제가 없으면 A3가 아니라 C20이다.
        runCase("A3 anonymous-identity") {
            openSettings()
            assertAnonymousIdentityRows()
            goBack()
            XCTAssertTrue(home.addButton.waitForHittable(), "설정에서 홈으로 돌아와야 한다")
        }

        runCase("A3 guest-save-reflects-on-home") {
            openNewEntry()
            typeAmount("8200")
            selectRequiredEntryFields()
            entry.submitButton.tap()

            assertSavedEntryVisible(on: TestClock.today)
            XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("8,200"), "게스트 저장이 지출 합계에 반영돼야 한다")
            XCTAssertTrue(home.expenseHistoryRow.label.contains("8,200"), "게스트 저장이 내역 행에 보여야 한다")
            XCTAssertTrue(home.todayCell.label.contains("8,200"), "게스트 저장이 달력 표식에 보여야 한다")
        }
    }

    /// 로그인 세션 전용 행이 게스트에게 새지 않는지.
    /// 음성 단언만 두면 설정 화면이 안 그려져도 전부 통과하므로, 익명 분기에서만 렌더되는
    /// 로그인 행(`SettingsView`의 `identityState == .anonymous` 분기)을 양성 대조로 짝짓는다.
    private func assertAnonymousIdentityRows() {
        XCTAssertTrue(settings.supportRow.waitForExistence(timeout: Timeout.transition), "설정 본문이 그려진 상태에서 판정해야 한다")
        XCTAssertTrue(settings.loginRow.waitForHittable(), "게스트에게는 로그인/회원가입 행이 보여야 한다")

        XCTAssertFalse(settings.logoutRow.exists, "게스트에게 로그아웃 행이 보이면 안 된다")
        // 삭제 행 자체는 게스트에게도 있다. 새는지 여부는 제목으로 갈린다 — 계정 탈퇴 제목이면 안 된다.
        XCTAssertEqual(settings.withdrawRow.label, WithdrawalFixture.guestRowTitle, "게스트에게는 데이터 삭제 제목이어야 한다")
        // 내 정보 행은 액션이 없어 Button이 아니다 — 제목 텍스트로 부재를 확인한다.
        XCTAssertFalse(app.staticTexts["내 정보"].exists, "게스트에게 내 정보 행이 보이면 안 된다")
    }
}

// MARK: - Step 8 · WithdrawalUITests

/// 탈퇴·데이터 삭제 진입점과 파괴적 확인까지만 자동화한다. 실제 삭제 완주는 서버 상태를 바꿔
/// 반복 실행이 비결정적이 되므로 실기기 e2e(manual)로 둔다.
///
/// 회원 상태는 `-uiTestSignInApple`·`-uiTestSignInGoogle`이 만들고, 시드 조립은 오프라인이 기본이라
/// 확인 다이얼로그를 보려면 `-uiTestOnline`이 함께 필요하다(오프라인이면 안내 알럿에서 끊긴다).
final class WithdrawalUITests: SettingsUITestCase {
    @MainActor
    func testAppleMemberConfirmDialogWarnsAboutAppleSheet() {
        launchMember(provider: UITestFlags.signInApple)
        openSettings()

        XCTAssertEqual(settings.withdrawRow.label, WithdrawalFixture.memberRowTitle, "회원에게는 탈퇴 제목이어야 한다")

        let alert = presentWithdrawConfirmation()

        XCTAssertTrue(hasAppleSheetNotice(in: alert), "Apple 연동 회원에게는 시트 예고 문구가 있어야 한다")
    }

    @MainActor
    func testGoogleMemberConfirmDialogHasNoAppleNoticeAndCancelKeepsSettings() {
        launchMember(provider: UITestFlags.signInGoogle)
        openSettings()

        XCTAssertEqual(settings.withdrawRow.label, WithdrawalFixture.memberRowTitle, "회원에게는 탈퇴 제목이어야 한다")

        let alert = presentWithdrawConfirmation()

        XCTAssertFalse(hasAppleSheetNotice(in: alert), "Apple 연동이 없으면 시트 예고 문구도 없어야 한다")

        alert.buttons[WithdrawalFixture.cancel].tap()

        XCTAssertTrue(alert.waitForNonExistence(), "취소하면 확인 다이얼로그가 닫혀야 한다")
        XCTAssertTrue(settings.withdrawRow.waitForHittable(), "취소 후에도 삭제 행을 다시 누를 수 있어야 한다")
        XCTAssertTrue(settings.logoutRow.exists, "취소는 세션을 건드리지 않으므로 회원 행이 그대로여야 한다")
    }

    private func launchMember(provider: String) {
        launch(extraArguments: [provider, UITestFlags.online])
    }

    private func presentWithdrawConfirmation() -> XCUIElement {
        settings.withdrawRow.tap()
        let alert = app.alerts[WithdrawalFixture.memberRowTitle]
        XCTAssertTrue(alert.waitForExistence(timeout: Timeout.transition), "파괴적 확인 다이얼로그가 떠야 한다")
        return alert
    }

    private func hasAppleSheetNotice(in alert: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", WithdrawalFixture.appleSheetNotice)
        return alert.staticTexts.containing(predicate).firstMatch.exists
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

            // 수정 화면도 신규와 동일하게 비운다 — 탭을 잘못 눌러도 원 카테고리·자산이 딸려가지 않는다.
            XCTAssertTrue(entry.selectedChips(prefix: "entry.category.").waitForCount(0), "탭 전환 후 카테고리 선택이 사라져야 한다")
            XCTAssertTrue(entry.selectedChips(prefix: "entry.asset.").waitForCount(0), "탭 전환 후 자산 선택도 사라져야 한다")
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
    static let clearLastUsedCurrency = "-uiTestClearLastUsedCurrency"
    static let signInApple = "-uiTestSignInApple"
    static let signInGoogle = "-uiTestSignInGoogle"
    static let online = "-uiTestOnline"
}

private enum Timeout {
    static let launch: TimeInterval = 20
    static let transition: TimeInterval = 8
}

/// 앱의 `UITestSupport.Fixture`와 짝을 이루는 기대값. 한쪽만 바뀌면 테스트가 먼저 깨진다.
private enum Fixture {
    static let expenseID = "00000000-0000-0000-0000-000000000001"
    static let incomeID = "00000000-0000-0000-0000-000000000002"
    static let otherDayID = "00000000-0000-0000-0000-000000000003"
    static let unconvertedID = "00000000-0000-0000-0000-000000000006"
    static let convertedUSDID = "00000000-0000-0000-0000-000000000007"
    static let expenseText = "10,000"
    /// 오늘 셀 표식 전용. 월 합계는 `monthlyIncomeText`다.
    static let todayIncomeText = "30,000"
    static let monthlyIncomeText = "35,000"
    static let totalText = "25,000"
    static let previousMonthAmountText = "7,000"
    static let nextMonthAmountText = "4,000"
    /// 25.00 USD × 1392.28(2025-07-15 시드 환율) = 34,807. 나누어떨어져 반올림 규칙에 기대지 않는다.
    static let computedConversionText = "34,807"
    static let conversionWarning = "선택한 기본 통화로 환산할 수 없는 거래는 집계에서 제외했습니다."
    /// 시드 지출이 쓰는 카테고리·자산. 수정 화면 진입 시 이 칩만 선택 상태여야 한다.
    static let expenseCategoryID = 1
    static let expenseAssetID = 1
    /// 시드 카탈로그의 첫 수입 카테고리. 수입 탭에서 저장까지 가는 흐름이 고른다.
    static let incomeCategoryID = 14
    /// 언어를 `ko`로 고정해 실행하므로 오늘 셀의 접근성 값은 한국어다.
    static let todayAccessibilityValue = "오늘"
    /// 시드 카탈로그의 지출 카테고리·자산 개수. 순회만 하면 항목이 늘어나는 회귀를 놓치므로 상한도 센다.
    static let expenseCategoryCount = 13
    static let assetCount = 6
    /// 빈 메모 TextField는 placeholder를 접근성 값으로 노출한다. "비었다"를 정확히 단언하는 기준값이다.
    static let memoPlaceholder = "어디에 사용했는지 적어주세요."
}

/// 설정 안내 문구와 짝을 이루는 기대값.
///
/// 약관·방침 본문 기대값(조항 제목·문단 수·"준비 중" 안내)은 문서가 Notion 게시본을 여는
/// 인앱 브라우저로 바뀌면서 함께 걷어냈다. 웹 콘텐츠는 XCUITest가 읽지 못하므로 대조할 대상이 없다.
private enum LegalFixture {
    static let loginConsentNotice = "로그인하면 아래 문서에 동의한 것으로 봅니다"
}

/// 탈퇴 문구(`WoniStringsWithdrawal.swift`)와 짝을 이루는 기대값. 한쪽만 바뀌면 테스트가 먼저 깨진다.
private enum WithdrawalFixture {
    static let memberRowTitle = "탈퇴하기"
    static let guestRowTitle = "내 데이터 삭제"
    static let appleSheetNotice = "Apple 로그인 창이 한 번 더 열립니다"
    static let cancel = "취소"
    static let confirmOK = "확인"
}

private enum SummaryKind: String {
    case expense
    case income
    case total
}

/// 연월 피커를 한 칸씩 움직이기 위한 좌표. 월 오버플로를 여기서만 다뤄 테스트가 재구현하지 않게 한다.
private struct YearMonth: Equatable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date) {
        let components = TestClock.seoulCalendar.dateComponents([.year, .month], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
    }

    /// 목표 쪽으로 정확히 한 칸 이동한 좌표. 연이 다르면 연부터 맞춘다.
    func stepped(toward target: YearMonth) -> YearMonth {
        if year != target.year {
            return YearMonth(year: year + (target.year > year ? 1 : -1), month: month)
        }
        return YearMonth(year: year, month: month + (target.month > month ? 1 : -1))
    }
}

/// 앱은 거래 날짜를 Asia/Seoul 기준으로 다룬다(시드도 `ServerDateFormatter`로 같은 기준).
/// 테스트가 러너 로컬 타임존으로 "오늘"을 계산하면 KST 자정 전후 구간에서 하루가 어긋나므로 기준을 맞춘다.
private enum TestClock {
    static let seoulCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        if let seoul = TimeZone(identifier: "Asia/Seoul") {
            calendar.timeZone = seoul
        }
        // 앱의 `Calendar.woniSeoul`이 일요일 시작을 명시한다. 여백 셀 기대가 로케일 기본값에 기대지 않도록 맞춘다.
        calendar.firstWeekday = 1
        return calendar
    }()

    /// 실행 중 **한 번만** 캡처한다. 호출마다 `Date()`를 새로 읽으면 한 테스트 안에서
    /// 날짜 선택·기대 문자열·월 이동 시작점이 서로 다른 시각으로 계산돼 자정 경계에서 어긋난다.
    static let today = Date()

    static var todayDay: Int {
        seoulCalendar.component(.day, from: today)
    }

    static var tomorrow: Date {
        seoulCalendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// `count`달 전의 15일. 15일로 고정해 월 길이·윤년 경계를 피한다.
    static func dayInMonthsAgo(_ count: Int) -> Date {
        let shifted = seoulCalendar.date(byAdding: .month, value: -count, to: today) ?? today
        var components = seoulCalendar.dateComponents([.year, .month], from: shifted)
        components.day = 15
        return seoulCalendar.date(from: components) ?? shifted
    }

    /// 휠 픽커 한 칸 높이. 아래로 이 만큼 끌면 이전 항목이 선택된다.
    static let wheelRowHeight: CGFloat = 44

    static var currentYear: Int {
        seoulCalendar.component(.year, from: today)
    }

    static var currentMonth: Int {
        seoulCalendar.component(.month, from: today)
    }

    static var seedOtherDay: Int {
        let lastDay = seoulCalendar.range(of: .day, in: .month, for: today)?.last ?? todayDay
        return todayDay == lastDay ? max(1, lastDay - 1) : lastDay
    }

    static var emptySeedDay: Int {
        (1 ... dayCount(in: today)).first { $0 != todayDay && $0 != seedOtherDay } ?? 1
    }

    static func monthDate(byAdding offset: Int, day: Int) -> Date {
        let shifted = seoulCalendar.date(byAdding: .month, value: offset, to: today) ?? today
        let components = seoulCalendar.dateComponents([.year, .month], from: shifted)
        return date(year: components.year ?? currentYear, month: components.month ?? currentMonth, day: day)
            ?? shifted
    }

    static func date(year: Int, month: Int, day: Int) -> Date? {
        seoulCalendar.date(from: DateComponents(
            calendar: seoulCalendar,
            timeZone: seoulCalendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }

    static func dayCount(in date: Date) -> Int {
        seoulCalendar.range(of: .day, in: .month, for: date)?.count ?? 0
    }

    static func leadingBlankCount(year: Int, month: Int) -> Int {
        guard let firstDay = date(year: year, month: month, day: 1) else {
            return 0
        }
        return (seoulCalendar.component(.weekday, from: firstDay) - seoulCalendar.firstWeekday + 7) % 7
    }

    static func fullDate(for date: Date) -> String {
        let components = seoulCalendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 1970)년 \(components.month ?? 1)월 \(components.day ?? 1)일"
    }

    static func monthTitle(for date: Date) -> String {
        let components = seoulCalendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 1970)년 \(components.month ?? 1)월"
    }

    static func englishMonthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = seoulCalendar
        formatter.timeZone = seoulCalendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).uppercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// 영어 전체 날짜 표기(`WoniDateFormat.fullDate`의 en 형식).
    static func englishFullDate(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = seoulCalendar
        formatter.timeZone = seoulCalendar.timeZone
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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

    var calendar: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "main.calendar").firstMatch
    }

    var historyContainer: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "main.history").firstMatch
    }

    var conversionWarning: XCUIElement {
        app.staticTexts["main.conversionWarning"]
    }

    /// 히스토리 행은 지출·수입으로 식별자가 갈린다. 정렬 순서에 기대지 않도록 종류로 직접 집는다.
    var historyRows: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main.history.row"))
    }

    var expenseHistoryRow: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "main.history.row.expense.")
        ).firstMatch
    }

    var incomeHistoryRow: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "main.history.row.income.")
        ).firstMatch
    }

    /// UUID 접미만 보면 다른 화면이 같은 접미를 붙였을 때 조용히 엉뚱한 요소를 집는다. 접두까지 묶는다.
    func historyRow(id: String) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "main.history.row.", id)
        ).firstMatch
    }

    var todayCell: XCUIElement {
        calendarDay(TestClock.todayDay)
    }

    func calendarDay(_ day: Int) -> XCUIElement {
        app.buttons["main.calendar.day.\(day)"]
    }

    var calendarDays: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "main.calendar.day."))
    }

    var selectedCalendarDays: XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", "main.calendar.day.")
        )
    }

    var todayCells: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "value == %@", Fixture.todayAccessibilityValue))
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

    var formScroll: XCUIElement {
        app.scrollViews.firstMatch
    }

    var currencyPickerScroll: XCUIElement {
        app.scrollViews["currencyPicker.list"]
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

    var previousDateButton: XCUIElement {
        app.buttons["entry.date.previous"]
    }

    var yearMonthPickerSave: XCUIElement {
        app.buttons["yearMonthPicker.save"]
    }

    /// 휠 항목은 값 텍스트로만 잡을 수 있다. 언어는 `ko`로 고정해 실행한다.
    /// 행에 탭 선택이 붙으면서 `.isButton` trait이 생겨 버튼으로 노출된다(`WheelColumn`).
    func yearWheelRow(_ year: Int) -> XCUIElement {
        app.buttons["\(year)년"]
    }

    func monthWheelRow(_ month: Int) -> XCUIElement {
        app.buttons["\(month)월"]
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

    func selectedChips(prefix: String) -> XCUIElementQuery {
        app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND selected == true", prefix)
        )
    }

    func chips(prefix: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    func currencyOption(_ label: String) -> XCUIElement {
        app.otherElements[label]
    }

    /// 통화 시트 안의 옵션 행 전체. 라벨이 `<국가명>, <통화코드>` 꼴인 것만 센다.
    var currencyOptions: XCUIElementQuery {
        currencyPickerScroll.otherElements.matching(
            NSPredicate(format: "label MATCHES %@", "^.+, [A-Z]{3}$")
        )
    }

    var estimatedRateLabel: XCUIElement {
        app.staticTexts["추정 환율"]
    }

    func rateLabel(prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// 환산액 텍스트의 숫자 부분("KRW " 접두 제거). 같은 줄의 환율 라벨("KRW 1.00 = …")과 구분해 집는다.
    func convertedAmountText() -> String? {
        let element = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)", "KRW ", "1.00 =")
        ).firstMatch
        guard element.waitForExistence(timeout: Timeout.transition) else {
            return nil
        }
        return String(element.label.dropFirst("KRW ".count))
    }

    func errorText(_ label: String) -> XCUIElement {
        app.staticTexts[label]
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

    var logoutRow: XCUIElement {
        app.buttons["settings.row.logout"]
    }

    /// 로그인/회원가입 행에는 식별자가 없다(익명 신원 전용 행). 언어를 ko로 고정해 실행하므로 라벨로 집는다.
    var loginRow: XCUIElement {
        app.buttons["로그인/회원가입"]
    }

    var supportRow: XCUIElement {
        app.buttons["settings.row.support"]
    }

    var termsRow: XCUIElement {
        app.buttons["settings.row.terms"]
    }

    var privacyRow: XCUIElement {
        app.buttons["settings.row.privacy"]
    }

    /// 로그인 시트의 동의 대상 문서 링크. 설정 화면의 같은 이름 행과는 식별자로 구분한다.
    var loginTermsLink: XCUIElement {
        app.buttons["login.link.terms"]
    }

    var loginPrivacyLink: XCUIElement {
        app.buttons["login.link.privacy"]
    }

    /// 설정·언어·법적 고지 화면이 공유하는 헤더 뒤로가기 버튼.
    var backButton: XCUIElement {
        app.buttons["settings.back"]
    }

    func languageOption(_ code: String) -> XCUIElement {
        app.buttons["settings.language.option.\(code)"]
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

    func waitForNotSelected(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "exists == true AND selected == false"), timeout: timeout)
    }

    func waitForHittable(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "hittable == true"), timeout: timeout)
    }

    func waitForNonHittable(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "hittable == false"), timeout: timeout)
    }

    func waitForKeyboardFocus(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "hasKeyboardFocus == true"), timeout: timeout)
    }

    func waitForLabelContaining(_ text: String, timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    func waitForLabelNotContaining(_ text: String, timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "NOT (label CONTAINS %@)", text), timeout: timeout)
    }

    /// 주어진 시간 동안 label이 바뀌지 않으면 true. "바뀌면 실패"라서 inverted expectation을 쓴다.
    /// 상태를 되돌리는 조작으로 확인하면 실제 회귀까지 되돌려 통과시키므로, 안정 구간을 직접 관찰한다.
    func assertLabelStaysUnchanged(_ expected: String, timeout: TimeInterval = 3) -> Bool {
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", expected),
            object: self
        )
        changed.isInverted = true
        return XCTWaiter.wait(for: [changed], timeout: timeout) == .completed
    }

    func waitForLabelPrefix(_ text: String, timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "label BEGINSWITH %@", text), timeout: timeout)
    }

    func waitForValueNotEqual(to text: String, timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "value != %@", text), timeout: timeout)
    }

    func waitForValue(_ text: String, timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "value == %@", text), timeout: timeout)
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
