//
//  woni_appUITests.swift
//  woni_appUITests
//
//  Created by J on 6/2/26.
//

import XCTest

// Step별 UI 테스트를 한 타깃 파일에 유지해 pbxproj 변경을 피한다.
// swiftlint:disable file_length

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
        // 회원탈퇴·로그아웃은 로그인 상태에서만 노출된다. UI 테스트는 익명 신원이라 여기서는 대상이 아니다.
        XCTAssertFalse(settings.withdrawRow.exists, "익명 상태에서는 회원탈퇴 행이 없어야 한다")
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

    func launch(seedLedger: Bool = false) {
        app.launchArguments = [
            UITestFlags.enable,
            "-woni.app.baseCurrency", "KRW",
            "-woni.app.language.override", "ko",
            "-woni.app.lastUsedCurrency", "KRW"
        ]
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
        entry.currencyButton.tap()
        let option = entry.currencyOption(label)
        XCTAssertTrue(option.waitForExistence(timeout: Timeout.transition), "통화 옵션 \(label)이 보여야 한다")
        option.tap()
        XCTAssertTrue(entry.currencyButton.waitForLabel(code), "선택 통화가 \(code)로 바뀌어야 한다")
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
        let current = YearMonth(date: TestClock.today)
        guard current != target else {
            return
        }
        home.monthTitle.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForExistence(timeout: Timeout.transition), "홈 연월 피커가 열려야 한다")
        pickYearMonth(from: current, to: target)
        entry.yearMonthPickerSave.tap()
        XCTAssertTrue(entry.yearMonthPickerSave.waitForNonExistence(), "저장 후 피커가 닫혀야 한다")
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
            XCTAssertTrue(entry.categoryChip(1).isSelected, "저장된 식비가 선택돼야 한다")
            XCTAssertTrue(entry.assetChip(1).isSelected, "저장된 신용카드가 선택돼야 한다")
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

        // 접두만 보면 환율 숫자가 비어도 통과한다. 실제 숫자가 붙었는지까지 확인한다.
        let rateElement = entry.rateLabel(prefix: "KRW 1.00 = USD ")
        XCTAssertTrue(rateElement.waitForExistence(timeout: Timeout.transition), "USD 환율이 표시돼야 한다")
        XCTAssertTrue(
            rateElement.label.range(of: "KRW 1\\.00 = USD [0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
            "환율 라벨에 실제 숫자가 붙어야 한다 (실제: \(rateElement.label))"
        )

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
        entry.deleteConfirmButton.tap()

        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "삭제 거래가 합계에서 빠져야 한다")
        XCTAssertTrue(
            app.buttons.matching(identifier: "main.history.row.expense").waitForCount(0),
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
        XCTAssertTrue(home.summaryAmount(.income).waitForLabel(Fixture.incomeText), "수입 합계는 그대로여야 한다")
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
    /// 키보드 출현을 먼저 기다린다. 기다리지 않으면 키패드가 아직 없어서 소수점 키 부재 단언이 공짜로 통과한다.
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
        entry.submitButton.tap()

        assertSavedEntryVisible(on: TestClock.today)
        // 1,000 이나 1,001 이면 소수를 몰래 반올림·절삭해 저장했다는 뜻이다.
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("10,005"), "입력한 숫자 그대로 저장돼야 한다")
    }

    /// C7의 대비군. 같은 키스트로크가 2자리 통화에서는 소수로 해석되는지 확인해
    /// "0자리 통화라서 소수가 안 들어간다"가 실제로 통화별 정책임을 증명한다.
    @MainActor
    func testC7SameKeystrokesBecomeFractionOnTwoDecimalCurrency() {
        launch()
        openNewEntry()
        selectCurrency(label: "미국, USD", code: "USD")

        typeAmount("10005")

        XCTAssertEqual(
            entry.amountField.value as? String,
            "100.05",
            "2자리 통화에서는 같은 키스트로크가 소수로 해석돼야 한다"
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
        entry.submitButton.tap()

        XCTAssertTrue(entry.errorText("외화 거래는 미래 날짜를 사용할 수 없습니다.").waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(entry.amountField.exists, "거부 후 입력 화면에 남아야 한다")
        XCTAssertFalse(home.addButton.exists, "거부된 거래는 홈으로 복귀하면 안 된다")

        // 오류를 띄우고도 거래를 넣어버린 구현이라면 위 세 단언은 그대로 통과한다. 저장 부재까지 확인한다.
        entry.closeButton.tap()
        XCTAssertTrue(home.addButton.waitForExistence(timeout: Timeout.transition))
        XCTAssertTrue(home.summaryAmount(.expense).waitForLabel("0"), "거부된 거래가 합계에 반영되면 안 된다")
        XCTAssertTrue(home.historyRows.waitForCount(0), "거부된 거래가 내역에 남으면 안 된다")
    }

    @MainActor
    func testC17MemoWith255CharactersSavesUnchanged() {
        let memo = String(repeating: "a", count: 255)
        launch()
        openNewEntry()
        typeAmount("100")
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

        runCase("C2 tab-switch-replaces-categories") {
            XCTAssertTrue(entry.categoryChip(1).waitForExistence(timeout: Timeout.transition), "지출 카테고리가 보여야 한다")
            XCTAssertTrue(entry.categoryChip(1).isSelected, "첫 지출 카테고리가 기본 선택돼야 한다")
            XCTAssertFalse(entry.categoryChip(14).exists, "수입 카테고리가 지출 탭에 보이면 안 된다")

            entry.tab(.income).tap()
            XCTAssertTrue(entry.tab(.income).waitForSelected())
            XCTAssertTrue(entry.categoryChip(14).waitForExistence(timeout: Timeout.transition), "수입 카테고리로 교체돼야 한다")
            XCTAssertTrue(entry.categoryChip(14).isSelected, "첫 수입 카테고리가 기본 선택돼야 한다")
            XCTAssertFalse(entry.categoryChip(1).exists, "이전 지출 카테고리와 선택이 사라져야 한다")

            entry.tab(.expense).tap()
            XCTAssertTrue(entry.categoryChip(1).waitForSelected(), "되돌아오면 기본 선택으로 돌아와야 한다")
            XCTAssertFalse(entry.categoryChip(14).exists)
        }

        // 위 케이스만으로는 "복귀 시 기본값 리셋"과 "이전 선택 보존"을 구분할 수 없다 —
        // 지출 탭에서 선택된 적 있는 칩이 기본값(1)뿐이라 두 정책이 같은 결과를 낸다.
        // 비기본 칩을 골라 두고 왕복해야 실제 정책(`selectDefaultCategoryIfNeeded` = 리셋)이 드러난다.
        runCase("C2 tab-return-resets-to-default-selection") {
            entry.categoryChip(2).tap()
            XCTAssertTrue(entry.categoryChip(2).waitForSelected(), "비기본 카테고리를 선택해 둔다")

            entry.tab(.income).tap()
            XCTAssertTrue(entry.categoryChip(14).waitForSelected(), "수입 탭 기본 선택으로 바뀌어야 한다")

            entry.tab(.expense).tap()
            XCTAssertTrue(
                entry.categoryChip(1).waitForSelected(),
                "복귀 시 이전 선택(2)이 아니라 기본값(1)으로 리셋돼야 한다"
            )
            XCTAssertFalse(entry.categoryChip(2).isSelected, "이전 선택이 되살아나면 안 된다")
        }

        // 원장 C15·C16의 전제는 "선택 해제 상태로 저장 시도"다. 그런데 `ChipSection`의 `onSelect`는 토글이 아니라
        // 항상 선택으로 바꾼다 — UI로는 미선택 상태를 만들 수 없다. 그래서 거부 경로 대신
        // **미선택이 불가능하다는 사실 자체**를 단언한다. 거부 로직은 ViewModel 유닛 테스트가 담당한다.
        runCase("C15 category-selection-cannot-be-cleared") {
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

    /// 이미 선택된 칩을 다시 탭해도 선택이 풀리지 않는다 — 즉 "미선택 저장"이라는 상태 자체가 UI로 도달 불가다.
    private func assertSelectionCannotBeCleared(prefix: String, chip: XCUIElement) {
        XCTAssertTrue(entry.selectedChips(prefix: prefix).waitForCount(1), "\(prefix) 는 정확히 하나 선택돼 있어야 한다")
        XCTAssertTrue(chip.isSelected, "기본 선택된 칩을 대상으로 해야 한다")

        chip.tap()

        XCTAssertTrue(chip.waitForSelected(), "선택된 칩을 다시 탭해도 선택이 유지돼야 한다")
        XCTAssertTrue(entry.selectedChips(prefix: prefix).waitForCount(1), "재탭 후에도 선택은 정확히 하나여야 한다")
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
    /// 빈 메모 TextField는 placeholder를 접근성 값으로 노출한다. "비었다"를 정확히 단언하는 기준값이다.
    static let memoPlaceholder = "어디에 사용했는지 적어주세요."
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
        return calendar
    }()

    /// 실행 중 **한 번만** 캡처한다. 호출마다 `Date()`를 새로 읽으면 한 테스트 안에서
    /// 날짜 선택·기대 문자열·월 이동 시작점이 서로 다른 시각으로 계산돼 자정 경계에서 어긋난다.
    static let today = Date()

    static var todayDay: Int {
        seoulCalendar.component(.day, from: today)
    }

    static var todayDayNumber: String {
        String(TestClock.todayDay)
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

    static func fullDate(for date: Date) -> String {
        let components = seoulCalendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 1970)년 \(components.month ?? 1)월 \(components.day ?? 1)일"
    }

    static func monthTitle(for date: Date) -> String {
        let components = seoulCalendar.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 1970)년 \(components.month ?? 1)월"
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

    var formScroll: XCUIElement {
        app.scrollViews.firstMatch
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
    func yearWheelRow(_ year: Int) -> XCUIElement {
        app.staticTexts["\(year)년"]
    }

    func monthWheelRow(_ month: Int) -> XCUIElement {
        app.staticTexts["\(month)월"]
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

    func currencyOption(_ label: String) -> XCUIElement {
        app.otherElements[label]
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

    func waitForHittable(timeout: TimeInterval = Timeout.transition) -> Bool {
        wait(for: NSPredicate(format: "hittable == true"), timeout: timeout)
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
