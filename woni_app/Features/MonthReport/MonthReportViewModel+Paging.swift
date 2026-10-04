//
//  MonthReportViewModel+Paging.swift
//  woni_app
//

import Foundation

/// 통계 페이저의 한 칸(한 달). 화면은 칸을 그릴 때 이 값만 읽는다 — 이번 달 값을 빌려 그리면 옆 달에만 있는
/// 카테고리가 "미분류"로 보이고 금액이 다른 기준통화로 적힌다. 이번 달·옆 달이 같은 타입·같은 계산이다(`page(offset:)`).
struct MonthReportPage: Equatable {
    enum Status: Equatable {
        case loading
        case failed(String)
        case loaded
    }

    let month: MainMonth
    let status: Status
    let kind: MainSummaryItem.Kind
    let language: AppLanguage
    let baseCurrency: SelectableCurrency
    let summary: MainMonthlySummary
    let expenseCategoryItems: [ReportCategoryItem]
    let incomeCategoryItems: [ReportCategoryItem]
    /// 그 달 내역에서 구한 표시명. 없는 카테고리는 `categoryDisplayName` 이 언어별 "미분류"로 채운다.
    let categoryDisplayNames: [Int: String]
    let hasUnconvertedTransactions: Bool

    var categoryItems: [ReportCategoryItem] {
        switch kind {
        case .expense:
            expenseCategoryItems
        case .income:
            incomeCategoryItems
        case .total:
            []
        }
    }

    var selectedTotal: Decimal {
        switch kind {
        case .expense:
            summary.expense
        case .income:
            summary.income
        case .total:
            summary.total
        }
    }

    var donutSlices: [ReportDonutSlice] {
        MonthReportAggregator.donutSlices(items: categoryItems, total: selectedTotal)
    }

    /// 합계는 부호를 붙이지 않는다 — 적자는 tone 색으로만 보인다(UI_GUIDE "위계").
    var summaryItems: [MainSummaryItem] {
        [
            (MainSummaryItem.Kind.expense, WoniStrings.expense(language), summary.expense, MainAmountTone.expense),
            (.income, WoniStrings.income(language), summary.income, .income),
            (.total, WoniStrings.total(language), abs(summary.total), summary.totalTone)
        ].map { kind, title, amount, tone in
            MainSummaryItem(kind: kind, title: title, amountText: formatAmount(amount), tone: tone)
        }
    }

    var conversionWarningText: String? {
        hasUnconvertedTransactions ? WoniStrings.conversionWarning(language) : nil
    }

    /// 지출도 수입도 0인 달 — 화면은 달 빈 상태를 그린다.
    var isMonthEmpty: Bool {
        summary.expense == 0 && summary.income == 0
    }

    /// 선택 탭만 0인 달 — 화면은 탭 빈 상태를 그린다. 합계 탭에는 없다.
    var isTabEmpty: Bool {
        switch kind {
        case .expense:
            summary.expense == 0
        case .income:
            summary.income == 0
        case .total:
            false
        }
    }

    /// 도넛 VoiceOver 요약. 1위 카테고리 이름은 그 칸의 달에서 구한다.
    var donutAccessibilitySummary: String {
        guard let leading = categoryItems.first,
              let selected = summaryItems.first(where: { $0.kind == kind })
        else {
            return ""
        }
        return WoniStrings.reportDonutAccessibility(
            kind: kind,
            total: (selected.amountText, baseCurrency),
            leading: (categoryDisplayName(categoryID: leading.categoryID), leading.percent),
            moreCategoryCount: categoryItems.count - 1,
            language: language
        )
    }

    func categoryDisplayName(categoryID: Int) -> String {
        categoryDisplayNames[categoryID] ?? WoniStrings.uncategorized(language)
    }

    func formatAmount(_ amount: Decimal) -> String {
        CurrencyFormat.string(amount, currencyCode: baseCurrency.rawValue)
    }
}

extension MonthReportViewModel {
    /// -1·0·+1 칸. 0 은 이번 달이고, ±1 은 읽어 둔 원자료를 **지금의** 탭·언어·기준통화로 집계한다.
    /// 상태는 오류 문구 → 그 달 값 없음(읽는 중) → 읽음 순으로 정한다. 값이 있는 채 다시 읽는 동안은 읽음이다 —
    /// `isLoading` 이 참이어도 보던 값을 그대로 보이다 새 값으로 바꾼다(본보기 `MainViewModel.isInitialLoading`).
    func page(offset: Int) -> MonthReportPage {
        guard offset != 0 else {
            return makePage(month: selectedMonth, snapshot: displaySnapshot, errorMessage: errorMessage)
        }

        let month = selectedMonth.addingMonths(offset, calendar: calendar)
        // 옆 달 읽기 실패는 칸에 보이지 않는다 — 읽는 중으로 두고, 그 달로 가면 다시 읽는다.
        return makePage(
            month: month,
            snapshot: cachedSnapshot(for: month) ?? .empty(baseCurrency: requestedBaseCurrency),
            errorMessage: nil
        )
    }

    /// 손가락 커밋 전용 **동기** 진입점. 달 바꿈이 같은 프레임에 일어나야 이음새가 튀지 않는다.
    /// 통계는 전환 대기가 없어 버튼·피커와 같은 길(`setMonth`)이다 — 읽어 둔 달이면 그 자리에서 채운다.
    func commitGestureMonthChange(by step: Int) {
        setMonth(selectedMonth.addingMonths(step, calendar: calendar))
    }

    func cachedSnapshot(for month: MainMonth) -> MonthReportDisplaySnapshot? {
        monthCache[month].map {
            makeDisplaySnapshot(
                baseCurrency: requestedBaseCurrency,
                baseTTSByDate: $0.baseTTSByDate,
                transactions: $0.transactions
            )
        }
    }

    /// 방금 이번 달에 적용한 원자료를 넣고 옆 달을 미리 읽는다. 축출은 미리 읽기를 꺼도 돈다 —
    /// 묶어 두면 달을 옮길 때마다 캐시가 끝없이 자란다(본보기 `MainViewModel.cacheLoadedMonth`).
    func cacheLoadedMonth(_ month: MainMonth, data: MainMonthData) {
        monthCache[month] = data
        evictDistantMonths()
        guard prefetchesNeighborMonths else {
            return
        }

        Task { await prefetchNeighborMonths() }
    }

    /// 밑의 거래나 읽기 기준(기준통화·계정)이 바뀌었을 수 있다 — 캐시를 비우고 세대를 올린다.
    func invalidateMonthCache() {
        monthCache.removeAll()
        monthCacheGeneration += 1
    }
}

private extension MonthReportViewModel {
    func makePage(
        month: MainMonth,
        snapshot: MonthReportDisplaySnapshot,
        errorMessage: String?
    ) -> MonthReportPage {
        let status: MonthReportPage.Status
        if let errorMessage {
            status = .failed(errorMessage)
        } else if snapshot.isPlaceholder {
            status = .loading
        } else {
            status = .loaded
        }

        return MonthReportPage(
            month: month,
            status: status,
            kind: selectedKind,
            language: language,
            baseCurrency: snapshot.baseCurrency,
            summary: snapshot.summary,
            expenseCategoryItems: snapshot.expenseCategoryItems,
            incomeCategoryItems: snapshot.incomeCategoryItems,
            categoryDisplayNames: snapshot.categoryDisplayNames,
            hasUnconvertedTransactions: snapshot.hasUnconvertedTransactions
        )
    }

    /// 이번 달 ±1 의 원자료를 읽어 둔다. 이미 가진 달은 건너뛴다. 읽는 동안 캐시가 비워졌으면(`start`·다시 읽기·
    /// 기준통화 변경) 그 결과는 버린다 — 본보기는 기준통화만 보지만, 그러면 낡은 거래나 다른 계정의 달이 남는다.
    func prefetchNeighborMonths() async {
        let generation = monthCacheGeneration
        let base = requestedBaseCurrency
        let center = selectedMonth
        for offset in [-1, 1] {
            let month = center.addingMonths(offset, calendar: calendar)
            guard generation == monthCacheGeneration else {
                return
            }
            guard monthCache[month] == nil,
                  let transactions = try? await loadTransactions(month.ledgerMonth)
            else {
                continue
            }

            let baseTTSByDate = await baseRateResolver.ttsByDate(
                for: base,
                dates: Set(transactions.map(\.transactionDate))
            )
            guard generation == monthCacheGeneration else {
                return
            }

            monthCache[month] = MainMonthData(transactions: transactions, baseTTSByDate: baseTTSByDate)
        }

        evictDistantMonths()
    }

    /// 이번 달 ±1 밖은 버린다. 페이저가 한 번에 보여 줄 수 있는 범위가 그만큼이다.
    func evictDistantMonths() {
        let keep = Set([-1, 0, 1].map { selectedMonth.addingMonths($0, calendar: calendar) })
        monthCache = monthCache.filter { keep.contains($0.key) }
    }
}
