//
//  MonthReportPagingTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 통계 페이저의 칸(`page(offset:)`)·옆 달 미리 읽기·달 이동 계약. 달마다 금액과 카테고리를 다르게 둔다 —
/// 같으면 칸이 뒤바뀌어도 통과한다.
@Suite(.serialized)
@MainActor
struct MonthReportPagingTests: MonthReportTestFixture {
    let november = MainMonth(year: 2025, month: 11)
    let december = MainMonth(year: 2025, month: 12)
    let january = MainMonth(year: 2026, month: 1)
    let february = MainMonth(year: 2026, month: 2)
    let march = MainMonth(year: 2026, month: 3)
    let april = MainMonth(year: 2026, month: 4)
    let july = MainMonth(year: 2026, month: 7)
    let august = MainMonth(year: 2026, month: 8)
    let september = MainMonth(year: 2026, month: 9)

    @Test("RNP.S0-R1 start·setMonth·커밋 뒤 옆 칸은 미리 읽은 그 달 금액·카테고리다")
    func neighborsArePrefetchedAfterEveryMove() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = alternatingCategoryExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)

        startJanuary(viewModel)
        await waitForNeighbors(viewModel)
        #expect(expenses(viewModel) == [10000, 20000, 30000])
        #expect(categoryIDs(viewModel) == [11, 10, 11])

        viewModel.setMonth(february)
        await waitForNeighbors(viewModel)
        #expect(expenses(viewModel) == [20000, 30000, 40000])
        #expect(categoryIDs(viewModel) == [10, 11, 10])

        viewModel.commitGestureMonthChange(by: 1)
        await waitForNeighbors(viewModel)
        #expect(expenses(viewModel) == [30000, 40000, 50000])
        #expect(categoryIDs(viewModel) == [11, 10, 11])
        #expect(viewModel.page(offset: 1).categoryDisplayName(categoryID: 11) == "airplane 여행")
    }

    @Test("RNP.S0-R1 앞 달 읽기가 실패하면 앞 칸은 읽는 중이고 이번 달·다음 달 칸은 그대로다")
    func failedNeighborReadStaysLoading() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        loader.errorsByMonth = [december: MonthReportViewModelTestError.loadFailure]
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)

        startJanuary(viewModel)
        await waitUntil { viewModel.page(offset: 1).status == .loaded }

        #expect(viewModel.page(offset: -1).status == .loading)
        #expect(viewModel.page(offset: 0).status == .loaded)
        #expect(viewModel.page(offset: 0).summary.expense == 20000)
        #expect(viewModel.page(offset: 1).summary.expense == 30000)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("RNP.S0-R1 두 달 넘게 옮기면 멀어진 달 캐시가 남지 않고 다시 옆이 되면 새로 읽는다")
    func distantMonthsAreEvicted() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        viewModel.setMonth(april)
        await waitForNeighbors(viewModel)
        viewModel.setMonth(february)

        #expect(viewModel.page(offset: 0).status == .loading)
        await waitForNeighbors(viewModel)
        #expect(expenses(viewModel) == [20000, 30000, 40000])
        #expect(loader.requestedMonths.filter { $0 == january }.count == 2)
        #expect(loader.requestedMonths.filter { $0 == february }.count == 2)
    }

    @Test("RNP.S0-R1 미리 읽기를 끄면 로더는 이번 달만 부르고 옆 칸은 읽는 중이다")
    func disabledPrefetchReadsOnlyCurrentMonth() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load)

        startJanuary(viewModel)
        await waitUntil { !viewModel.isLoading }
        await settle()

        #expect(loader.requestedMonths == [january])
        #expect(viewModel.page(offset: 0).summary.expense == 20000)
        #expect(viewModel.page(offset: -1).status == .loading)
        #expect(viewModel.page(offset: 1).status == .loading)
    }
}

extension MonthReportPagingTests {
    @Test("RNP.S0-R2 옆 칸은 이번 달과 같은 계산이고 그 달 카테고리 이름·경고·빈 상태·탭·언어를 따른다")
    func neighborPageUsesSameDerivations() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = [
            december: [
                expense(10000, in: december, categoryID: 11),
                makeTransaction(amount: 10, currencyCode: "USD", transactionDate: "2025-12-15")
            ],
            january: [expense(20000, in: january)],
            february: [
                makeTransaction(amount: 30000, categoryID: 31, transactionType: .income, transactionDate: "2026-02-15")
            ]
        ]
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        let previous = viewModel.page(offset: -1)
        #expect(previous.month == december)
        #expect(previous.summaryItems.map(\.amountText) == ["10,000", "0", "10,000"])
        #expect(previous.categoryItems.map(\.categoryID) == [11])
        #expect(previous.donutSlices.count == 1)
        #expect(previous.categoryDisplayName(categoryID: 11) == "airplane 여행")
        #expect(viewModel.categoryDisplayName(categoryID: 11) == WoniStrings.uncategorized(.ko))
        #expect(previous.conversionWarningText == WoniStrings.conversionWarning(.ko))
        #expect(previous.donutAccessibilitySummary == "지출 10,000원, airplane 여행 100%")
        #expect(!previous.isMonthEmpty && !previous.isTabEmpty)
        let next = viewModel.page(offset: 1)
        #expect(!next.isMonthEmpty && next.isTabEmpty)
        #expect(next.categoryItems.isEmpty && next.donutSlices.isEmpty)
        #expect(next.conversionWarningText == nil)

        viewModel.setKind(.income)
        #expect(viewModel.page(offset: 1).categoryItems.map(\.amount) == [30000])
        #expect(viewModel.page(offset: 1).categoryDisplayName(categoryID: 31) == "laptopcomputer 부수입")
        #expect(viewModel.page(offset: -1).isTabEmpty)

        viewModel.applyLanguage(.en)
        let english = viewModel.page(offset: -1)
        #expect(english.categoryDisplayName(categoryID: 11) == "airplane Travel")
        #expect(english.summaryItems.map(\.title) == ["Expense", "Income", "Total"])
        #expect(english.conversionWarningText == WoniStrings.conversionWarning(.en))
    }

    @Test("RNP.S0-R2 거래가 없는 옆 달은 읽음 상태의 달 빈 상태다")
    func emptyNeighborMonthIsMonthEmpty() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = [january: [expense(20000, in: january)]]
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)

        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        let previous = viewModel.page(offset: -1)
        #expect(previous.status == .loaded)
        #expect(previous.isMonthEmpty)
        #expect(previous.summary == .empty)
        #expect(!viewModel.page(offset: 0).isMonthEmpty)
    }

    @Test("RNP.S0-R2 옆 칸 금액 문자열은 그 칸의 기준통화 표기다")
    func neighborAmountsUseBaseCurrency() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = summerExpenses
        let viewModel = try makeViewModel(
            baseCurrency: .usd,
            loadTransactions: loader.load,
            prefetchesNeighborMonths: true
        )

        viewModel.start(month: august, language: .ko, baseCurrency: .usd, revision: 0)
        await waitForNeighbors(viewModel)

        let previous = viewModel.page(offset: -1)
        #expect(previous.baseCurrency == .usd)
        #expect(previous.summaryItems.first?.amountText == "10.00")
        #expect(previous.formatAmount(10) == "10.00")
        #expect(previous.donutAccessibilitySummary == "지출 USD 10.00, fork.knife 식비 100%")
        #expect(viewModel.page(offset: 1).summaryItems.first?.amountText == "30.00")
    }

    @Test("RNP.S0-R2 이번 달 칸은 기존 공개 값과 같다")
    func currentPageMatchesPublicValues() async throws {
        let transactions = [
            expense(20000, in: january),
            expense(5000, in: january, categoryID: 11),
            makeTransaction(amount: 7000, categoryID: 30, transactionType: .income),
            makeTransaction(amount: 10, currencyCode: "USD")
        ]
        let viewModel = try makeViewModel(loadTransactions: { _ in transactions })
        await viewModel.reload()

        let current = viewModel.page(offset: 0)
        #expect(current.month == viewModel.selectedMonth)
        #expect(current.status == .loaded)
        #expect(current.summaryItems.map(\.amountText) == ["25,000", "7,000", "18,000"])
        #expect(current.summaryItems == viewModel.summaryItems)
        #expect(current.categoryItems.map(\.amount) == [20000, 5000])
        #expect(current.categoryItems == viewModel.categoryItems)
        #expect(current.donutSlices == viewModel.donutSlices)
        #expect(current.conversionWarningText != nil)
        #expect(current.conversionWarningText == viewModel.conversionWarningText)
        #expect(current.categoryDisplayName(categoryID: 11) == viewModel.categoryDisplayName(categoryID: 11))
        #expect(current.categoryDisplayName(categoryID: 99) == viewModel.categoryDisplayName(categoryID: 99))
        #expect(current.formatAmount(12345) == viewModel.formatBaseAmount(12345))
    }

    @Test("RNP.S0-R2 이번 달 칸 상태 — 오류는 같은 문구, 첫 읽기는 읽는 중, 값이 있는 채 다시 읽으면 읽음")
    func currentPageStatusFollowsLoadState() async throws {
        let failing = MutableMonthReportLoader()
        failing.error = MonthReportViewModelTestError.loadFailure
        let failed = try makeViewModel(loadTransactions: failing.load)
        await failed.reload()
        let message = try #require(failed.errorMessage)
        #expect(failed.page(offset: 0).status == .failed(message))

        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        startJanuary(viewModel)
        await loader.waitForRequestCount(1)
        viewModel.applyLanguage(.en)
        #expect(viewModel.isLoading)
        #expect(viewModel.page(offset: 0).status == .loading)

        loader.resumeFirst(month: january.ledgerMonth, returning: [expense(20000, in: january)])
        await waitUntil { !viewModel.isLoading }
        let reload = Task { await viewModel.reload() }
        await loader.waitForRequestCount(2)
        #expect(viewModel.isLoading)
        #expect(viewModel.page(offset: 0).status == .loaded)
        #expect(viewModel.page(offset: 0).summary.expense == 20000)

        loader.resumeFirst(month: january.ledgerMonth, returning: [expense(25000, in: january)])
        await reload.value
        #expect(viewModel.page(offset: 0).summary.expense == 25000)
    }
}

extension MonthReportPagingTests {
    @Test("RNP.S0-R3 손가락 커밋은 동기로 읽어 둔 달을 채우고 다시 읽는 동안에도 읽음이다", arguments: [1, -1])
    func gestureCommitFillsFromCacheSynchronously(step: Int) async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        await primeJanuaryUntilNextMonthPending(viewModel, loader: loader)
        loader.resumeFirst(month: february.ledgerMonth, returning: monthlyExpenses[february] ?? [])
        await waitForNeighbors(viewModel)
        let target = january.addingMonths(step, calendar: viewModel.calendar)

        viewModel.commitGestureMonthChange(by: step)

        #expect(viewModel.selectedMonth == target)
        #expect(viewModel.page(offset: 0).status == .loaded)
        #expect(viewModel.page(offset: 0).summary.expense == monthlyExpense(target))
        #expect(viewModel.page(offset: -step).summary.expense == 20000)
        await loader.waitForRequestCount(4)
        #expect(viewModel.isLoading)
        #expect(viewModel.page(offset: 0).status == .loaded)

        let beyond = target.addingMonths(step, calendar: viewModel.calendar)
        loader.resumeFirst(month: target.ledgerMonth, returning: monthlyExpenses[target] ?? [])
        await loader.waitForRequestCount(5)
        loader.resumeFirst(month: beyond.ledgerMonth, returning: monthlyExpenses[beyond] ?? [])
        await waitUntil { viewModel.page(offset: step).status == .loaded }
        #expect(viewModel.page(offset: step).summary.expense == monthlyExpense(beyond))
    }

    @Test("RNP.S0-R3 캐시가 없던 달로 커밋하면 직후 읽는 중이고 읽기가 끝나면 그 달 값이다", arguments: [1, -1])
    func gestureCommitWithoutCacheShowsLoading(step: Int) async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        startJanuary(viewModel)
        await waitUntil { !viewModel.isLoading }
        let target = january.addingMonths(step, calendar: viewModel.calendar)

        viewModel.commitGestureMonthChange(by: step)

        #expect(viewModel.selectedMonth == target)
        #expect(viewModel.page(offset: 0).status == .loading)
        await waitUntil { !viewModel.isLoading }
        #expect(viewModel.page(offset: 0).status == .loaded)
        #expect(viewModel.page(offset: 0).summary.expense == monthlyExpense(target))
    }

    @Test("RNP.S0-R3 커밋 전에 시작된 옛 달 읽기가 늦게 끝나도 새 달 값을 덮지 않는다")
    func staleReadBeforeCommitCannotOverwrite() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        startJanuary(viewModel)
        await loader.waitForRequestCount(1)
        loader.resumeFirst(month: january.ledgerMonth, returning: monthlyExpenses[january] ?? [])
        await waitUntil { !viewModel.isLoading }
        viewModel.setMonth(february)
        await loader.waitForRequestCount(2)
        loader.resumeFirst(month: february.ledgerMonth, returning: monthlyExpenses[february] ?? [])
        await waitUntil { !viewModel.isLoading }
        viewModel.setMonth(january)
        await loader.waitForRequestCount(3)

        viewModel.commitGestureMonthChange(by: 1)
        await loader.waitForRequestCount(4)
        loader.resumeFirst(month: february.ledgerMonth, returning: monthlyExpenses[february] ?? [])
        await waitUntil { !viewModel.isLoading }
        loader.resumeFirst(month: january.ledgerMonth, returning: [expense(99999, in: january)])
        await settle()

        #expect(viewModel.selectedMonth == february)
        #expect(viewModel.page(offset: 0).status == .loaded)
        #expect(viewModel.page(offset: 0).summary.expense == 30000)
        #expect(!viewModel.isLoading)
    }

    @Test("RNP.S0-R4 버튼·피커 이동은 방향과 떠난 칸을 남기고 읽어 둔 달은 바로 채운다")
    func setMonthRecordsDirectionAndOutgoingPage() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let yearBefore = MainMonth(year: 2025, month: 2)
        loader.transactionsByMonth[yearBefore] = [expense(7000, in: yearBefore, categoryID: 11)]
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        viewModel.setMonth(february)
        #expect(viewModel.monthChangeDirection == .next)
        #expect(viewModel.outgoingPage?.month == january)
        #expect(viewModel.outgoingPage?.status == .loaded)
        #expect(viewModel.outgoingPage?.summary.expense == 20000)
        #expect(viewModel.page(offset: 0).status == .loaded)
        #expect(viewModel.page(offset: 0).summary.expense == 30000)
        await waitUntil { !viewModel.isLoading }

        viewModel.setMonth(yearBefore)
        #expect(viewModel.monthChangeDirection == .previous)
        #expect(viewModel.outgoingPage?.month == february)
        #expect(viewModel.outgoingPage?.summary.expense == 30000)
        #expect(viewModel.page(offset: 0).status == .loading)
        await waitUntil { viewModel.page(offset: 0).status == .loaded }
        #expect(viewModel.page(offset: 0).summary.expense == 7000)
    }

    @Test("RNP.S0-R4 연달아 옮기면 떠난 칸은 바로 앞 달이다")
    func consecutiveMovesKeepImmediatelyPreviousPage() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        viewModel.setMonth(february)
        viewModel.setMonth(march)

        #expect(viewModel.monthChangeDirection == .next)
        #expect(viewModel.outgoingPage?.month == february)
        #expect(viewModel.outgoingPage?.summary.expense == 30000)
        await waitUntil { !viewModel.isLoading }
    }

    @Test("RNP.S0-R4 같은 달 setMonth 는 방향·떠난 칸·로더 호출 수를 바꾸지 않는다")
    func sameMonthSetMonthIsNoOp() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load)
        startJanuary(viewModel)
        await waitUntil { !viewModel.isLoading }
        viewModel.setMonth(december)
        await waitUntil { !viewModel.isLoading }
        let outgoing = viewModel.outgoingPage
        let loadCount = loader.loadCount

        viewModel.setMonth(december)
        await settle()

        #expect(viewModel.monthChangeDirection == .previous)
        #expect(outgoing?.month == january)
        #expect(viewModel.outgoingPage == outgoing)
        #expect(loader.loadCount == loadCount)
        #expect(!viewModel.isLoading)
    }
}

extension MonthReportPagingTests {
    @Test("RNP.S0-R5 거래가 바뀌어 다시 읽으면(리비전·reload) 옆 칸은 새 금액이다")
    func ledgerChangeRefreshesNeighbors() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        loader.transactionsByMonth[february] = [expense(35000, in: february)]
        await viewModel.observeLedgerChanges(AsyncStream { $0.finish() }, revision: { 1 })
        await waitUntil { viewModel.page(offset: 1).summary.expense == 35000 }
        #expect(viewModel.page(offset: 1).status == .loaded)

        loader.transactionsByMonth[december] = [expense(15000, in: december, categoryID: 11)]
        await viewModel.reload()
        await waitUntil { viewModel.page(offset: -1).summary.expense == 15000 }
        #expect(viewModel.page(offset: -1).status == .loaded)
    }

    @Test("RNP.S0-R5 기준통화를 바꾸면 옆 칸 금액이 새 통화다")
    func baseCurrencyChangeRefreshesNeighbors() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = summerExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        viewModel.start(month: august, language: .ko, baseCurrency: .krw, revision: 0)
        await waitForNeighbors(viewModel)
        #expect(viewModel.page(offset: -1).summaryItems.first?.amountText == "14,000")

        viewModel.requestBaseCurrency(.usd)

        await waitUntil {
            viewModel.page(offset: -1).summaryItems.first?.amountText == "10.00"
                && viewModel.page(offset: 1).summaryItems.first?.amountText == "30.00"
        }
        #expect(viewModel.page(offset: -1).baseCurrency == .usd)
    }

    @Test("RNP.S0-R5 리비전 갱신 전에 시작한 다음 달 미리 읽기가 늦게 끝나도 캐시에 들어가지 않는다")
    func staleNeighborReadBeforeRefreshIsDropped() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        await primeJanuaryUntilNextMonthPending(viewModel, loader: loader)

        let refresh = Task {
            await viewModel.observeLedgerChanges(AsyncStream { $0.finish() }, revision: { 1 })
        }
        await loader.waitForRequestCount(4)
        loader.resumeFirst(month: january.ledgerMonth, returning: monthlyExpenses[january] ?? [])
        await refresh.value
        // 갱신이 끝난 뒤에 옛 읽기를 푼다 — 읽는 중에만 버리는 구현은 여기서 옛 금액을 캐시에 넣고,
        // 새 미리 읽기가 그 달을 건너뛴다.
        loader.resumeFirst(month: february.ledgerMonth, returning: monthlyExpenses[february] ?? [])

        await finishNeighborReads(viewModel, loader: loader, next: [expense(35000, in: february)])
        #expect(viewModel.page(offset: 1).summary.expense == 35000)
    }

    @Test("RNP.S0-R5 옆 달을 읽는 도중 기준통화가 바뀌면 그 결과는 캐시에 들어가지 않는다")
    func neighborReadDuringBaseCurrencyChangeIsDropped() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        viewModel.start(month: august, language: .ko, baseCurrency: .krw, revision: 0)
        await loader.waitForRequestCount(1)
        loader.resumeFirst(month: august.ledgerMonth, returning: summerExpenses[august] ?? [])
        await loader.waitForRequestCount(2)

        viewModel.requestBaseCurrency(.usd)
        await loader.waitForRequestCount(3)
        loader.resumeFirst(month: july.ledgerMonth, returning: summerExpenses[july] ?? [])
        loader.resumeFirst(month: august.ledgerMonth, returning: summerExpenses[august] ?? [])
        await waitUntil { !viewModel.isLoading }

        await loader.waitForRequestCount(4)
        loader.resumeFirst(month: july.ledgerMonth, returning: summerExpenses[july] ?? [])
        await loader.waitForRequestCount(5)
        loader.resumeFirst(month: september.ledgerMonth, returning: summerExpenses[september] ?? [])
        await waitForNeighbors(viewModel)
        #expect(viewModel.page(offset: -1).summaryItems.first?.amountText == "10.00")
    }
}

extension MonthReportPagingTests {
    @Test("RNP.S0-R6 같은 달로 start 하면 캐시·방향·떠난 칸이 처음으로 돌아가 새 계정 금액을 읽는다")
    func startResetsCacheForNewAccount() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)
        viewModel.setMonth(december)
        await waitForNeighbors(viewModel)
        #expect(viewModel.outgoingPage != nil)

        loader.transactionsByMonth = [
            december: [expense(11000, in: december, categoryID: 11)],
            january: [expense(21000, in: january)],
            february: [expense(31000, in: february)]
        ]
        startJanuary(viewModel)

        #expect(viewModel.outgoingPage == nil)
        #expect(viewModel.monthChangeDirection == .next)
        #expect(viewModel.page(offset: -1).status == .loading)
        #expect(viewModel.page(offset: 1).status == .loading)
        await waitForNeighbors(viewModel)
        #expect(expenses(viewModel) == [11000, 21000, 31000])
    }

    @Test("RNP.S0-R6 start 전에 시작한 옛 계정의 다음 달 미리 읽기가 늦게 끝나도 캐시에 들어가지 않는다")
    func staleNeighborReadBeforeStartIsDropped() async throws {
        let loader = DeferredMonthReportLoader()
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        await primeJanuaryUntilNextMonthPending(viewModel, loader: loader)

        startJanuary(viewModel)
        await loader.waitForRequestCount(4)
        loader.resumeFirst(month: january.ledgerMonth, returning: [expense(21000, in: january)])
        await waitUntil { !viewModel.isLoading }
        // 새 계정 읽기가 끝난 뒤에 옛 계정 읽기를 푼다 — 읽는 중에만 버리는 구현은 여기서 옛 계정 금액을
        // 캐시에 넣고, 새 미리 읽기가 그 달을 건너뛴다.
        loader.resumeFirst(month: february.ledgerMonth, returning: monthlyExpenses[february] ?? [])

        await finishNeighborReads(viewModel, loader: loader, next: [expense(31000, in: february)])
        #expect(viewModel.page(offset: 1).summary.expense == 31000)
    }

    @Test("RNP.S0-R6 멀리 떨어진 달로 start 하면 옆 칸은 그 달의 옆 달이다")
    func startOnDistantMonthPrefetchesItsNeighbors() async throws {
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = monthlyExpenses.merging(summerExpenses) { first, _ in first }
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)

        viewModel.start(month: august, language: .ko, baseCurrency: .krw, revision: 0)
        await waitForNeighbors(viewModel)

        #expect(viewModel.page(offset: -1).month == july)
        #expect(viewModel.page(offset: 1).month == september)
        #expect(expenses(viewModel) == [14000, 28000, 42000])
    }

    @Test("RNP.S0-R7 상세용 함수는 옆 달 캐시를 보지 않고 이번 달 기준이다")
    func detailFunctionsIgnoreNeighborCache() async throws {
        let januaryID = try #require(UUID(uuidString: "10000000-0000-0000-0000-0000000000A1"))
        let februaryID = try #require(UUID(uuidString: "20000000-0000-0000-0000-0000000000B2"))
        let loader = MutableMonthReportLoader()
        loader.transactionsByMonth = [
            january: [makeTransaction(clientEntryID: januaryID, amount: 20000)],
            february: [
                makeTransaction(clientEntryID: februaryID, amount: 30000, categoryID: 11, transactionDate: "2026-02-15")
            ]
        ]
        let viewModel = try makeViewModel(loadTransactions: loader.load, prefetchesNeighborMonths: true)
        startJanuary(viewModel)
        await waitForNeighbors(viewModel)
        #expect(viewModel.page(offset: 1).categoryDisplayName(categoryID: 11) == "airplane 여행")

        #expect(viewModel.transaction(clientEntryID: februaryID) == nil)
        #expect(viewModel.entryRows(categoryID: 11).isEmpty)
        #expect(viewModel.categoryDisplayName(categoryID: 11) == WoniStrings.uncategorized(.ko))
        #expect(viewModel.resolvedCategoryDisplayName(categoryID: 11) == nil)
        #expect(viewModel.categoryTotal(categoryID: 11) == 0)
        let missing = viewModel.categoryDetail(categoryID: 11)
        #expect(missing.sections.isEmpty)
        #expect(missing.totalText == "0")
        #expect(missing.entryCountText == "내역 0건")

        #expect(viewModel.transaction(clientEntryID: januaryID)?.clientEntryID == januaryID)
        #expect(viewModel.entryRows(categoryID: 10).map(\.amount) == [20000])
        #expect(viewModel.categoryDisplayName(categoryID: 10) == "fork.knife 식비")
        #expect(viewModel.resolvedCategoryDisplayName(categoryID: 10) == "fork.knife 식비")
        #expect(viewModel.categoryTotal(categoryID: 10) == 20000)
        let present = viewModel.categoryDetail(categoryID: 10)
        #expect(present.totalText == "20,000")
        #expect(present.sections.flatMap(\.rows).map(\.id) == [januaryID])
    }
}

private extension MonthReportPagingTests {
    /// 11월 5,000 · 12월 여행 10,000 · 1월 20,000 · 2월 30,000 · 3월 40,000 · 4월 50,000 (12월 밖은 식비).
    var monthlyExpenses: [MainMonth: [LocalTransaction]] {
        [
            november: [expense(5000, in: november)],
            december: [expense(10000, in: december, categoryID: 11)],
            january: [expense(20000, in: january)],
            february: [expense(30000, in: february)],
            march: [expense(40000, in: march)],
            april: [expense(50000, in: april)]
        ]
    }

    /// 시드 USD 환율(1,400, 2026-07-02 부터)이 닿는 달 — KRW 14,000 · 28,000 · 42,000 = USD 10 · 20 · 30.
    var summerExpenses: [MainMonth: [LocalTransaction]] {
        [
            july: [expense(14000, in: july)],
            august: [expense(28000, in: august)],
            september: [expense(42000, in: september)]
        ]
    }

    /// `monthlyExpenses` 와 금액은 같고 카테고리만 달마다 번갈아(시드 지출 카테고리가 식비·여행 둘뿐) 옆 칸끼리 다르다.
    var alternatingCategoryExpenses: [MainMonth: [LocalTransaction]] {
        [
            december: [expense(10000, in: december, categoryID: 11)],
            january: [expense(20000, in: january)],
            february: [expense(30000, in: february, categoryID: 11)],
            march: [expense(40000, in: march)],
            april: [expense(50000, in: april, categoryID: 11)]
        ]
    }

    func categoryIDs(_ viewModel: MonthReportViewModel) -> [Int] {
        [-1, 0, 1].compactMap { viewModel.page(offset: $0).categoryItems.first?.categoryID }
    }

    func monthlyExpense(_ month: MainMonth) -> Decimal {
        monthlyExpenses[month]?.reduce(Decimal(0)) { $0 + $1.amount } ?? 0
    }

    func expense(_ amount: Decimal, in month: MainMonth, categoryID: Int = 10) -> LocalTransaction {
        makeTransaction(
            amount: amount,
            categoryID: categoryID,
            transactionDate: String(format: "%04d-%02d-15", month.year, month.month)
        )
    }

    func expenses(_ viewModel: MonthReportViewModel) -> [Decimal] {
        [-1, 0, 1].map { viewModel.page(offset: $0).summary.expense }
    }

    func startJanuary(_ viewModel: MonthReportViewModel) {
        viewModel.start(month: january, language: .ko, baseCurrency: .krw, revision: 0)
    }

    func waitForNeighbors(
        _ viewModel: MonthReportViewModel,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        await waitUntil(
            {
                viewModel.page(offset: -1).status == .loaded
                    && viewModel.page(offset: 1).status == .loaded
            },
            sourceLocation: sourceLocation
        )
    }

    /// 1월을 읽고 앞 달(12월)까지 미리 읽은 뒤, 다음 달(2월) 미리 읽기가 대기 중인 데서 멈춘다(요청 3건).
    func primeJanuaryUntilNextMonthPending(
        _ viewModel: MonthReportViewModel,
        loader: DeferredMonthReportLoader
    ) async {
        startJanuary(viewModel)
        await loader.waitForRequestCount(1)
        loader.resumeFirst(month: january.ledgerMonth, returning: monthlyExpenses[january] ?? [])
        await loader.waitForRequestCount(2)
        loader.resumeFirst(month: december.ledgerMonth, returning: monthlyExpenses[december] ?? [])
        await loader.waitForRequestCount(3)
    }

    /// 다시 읽은 1월 뒤의 새 미리 읽기(요청 5·6건 — 12월, 2월)를 끝낸다. 옛 2월 결과가 캐시에 들어갔다면
    /// 새 미리 읽기가 2월을 건너뛰어 6번째 요청이 오지 않는다.
    func finishNeighborReads(
        _ viewModel: MonthReportViewModel,
        loader: DeferredMonthReportLoader,
        next: [LocalTransaction]
    ) async {
        await loader.waitForRequestCount(5)
        loader.resumeFirst(month: december.ledgerMonth, returning: monthlyExpenses[december] ?? [])
        await loader.waitForRequestCount(6)
        loader.resumeFirst(month: february.ledgerMonth, returning: next)
        await waitForNeighbors(viewModel)
    }

    /// 배경 작업이 돌 기회를 준다. 일어나면 안 되는 일을 단언하기 전에만 쓴다 — 일어나야 할 일은 `waitUntil` 로 기다린다.
    func settle() async {
        for _ in 0 ..< 100 {
            await Task.yield()
        }
    }
}
