//
//  ReportMonthPageView.swift
//  woni_app
//

import SwiftUI

/// 통계의 달 제목 줄 아래 전부(금액 탭·도넛/막대·목록). 앞·이번·다음 달 칸을 공용 페이저에 얹어
/// 손가락을 따라 밀리고, 놓으면 붙는다(UI_GUIDE "달 넘기기"). 화살표·피커로 달이 바뀌면 그 방향으로
/// 미끄러지고, '동작 줄이기'면 떠나는 칸이 겹쳐 사라진다.
struct ReportMonthPager: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let viewModel: MonthReportViewModel
    let onSelectCategory: (Int) -> Void

    @State private var slide: MonthSlideCommand?
    /// 진행 중인 정착 수(손가락 스크롤·미끄러짐·겹쳐 사라짐). Bool 이 아니라 세는 이유는 메인과 같다 —
    /// 정착이 겹치면 먼저 끝난 쪽이 나중 정착의 창을 닫아 버린다.
    @State private var settlingCount = 0
    /// 손가락으로 붙인 달. 페이저가 이미 그 달로 옮겼으니 다시 미끄러뜨리지 않는다.
    @State private var gestureCommittedMonth: MainMonth?
    /// 미끄러지는 동안 떠나는 쪽 칸. 정착이 모두 끝나면 비운다 — 남기면 다음 손가락 끌기에 낡은 달이 딸려 들어온다.
    @State private var leaving: LeavingPage?
    @State private var fade: FadingPage?

    var body: some View {
        // 칸 값은 여기서 읽는다 — 페이저 안쪽 호스팅이 아니라 이 화면이 VM 변화를 따라 다시 그려진다.
        let pages = [-1, 0, 1].map(slotPage(offset:))
        let isSettling = settlingCount > 0
        GeometryReader { proxy in
            MonthPagingScrollView(
                onCommit: { step in
                    viewModel.commitGestureMonthChange(by: step)
                    gestureCommittedMonth = viewModel.selectedMonth
                },
                onScrollActivity: { isScrolling in
                    if isScrolling {
                        beginSettling()
                    } else {
                        endSettling()
                    }
                },
                slide: slide,
                onSlideFinished: endSettling,
                content: {
                    strip(pages: pages, size: proxy.size, isSettling: isSettling)
                }
            )
        }
        .overlay {
            if let fade {
                pageView(fade.page, isDecorative: true)
                    .opacity(fade.opacity)
            }
        }
        .onChange(of: viewModel.selectedMonth) { _, month in
            // 표시는 들어오는 즉시 소비한다 — 남기면 그 뒤 화살표 이동이 미끄러지지 않는다.
            let isGestureCommit = month == gestureCommittedMonth
            gestureCommittedMonth = nil
            // 떠난 칸이 없으면 `start` 로 다시 시작한 것이다 — 화살표·피커 이동이 아니라 미끄러뜨리지 않는다.
            guard !isGestureCommit, let outgoing = viewModel.outgoingPage else {
                return
            }

            if reduceMotion {
                fadeOut(outgoing)
            } else {
                slideIn(leaving: outgoing)
            }
        }
    }
}

private extension ReportMonthPager {
    struct LeavingPage {
        let page: MonthReportPage
        let offset: Int
    }

    struct FadingPage {
        let id: UUID
        let page: MonthReportPage
        var opacity: Double
    }

    func slotPage(offset: Int) -> MonthReportPage {
        if let leaving, leaving.offset == offset {
            return leaving.page
        }
        return viewModel.page(offset: offset)
    }

    /// 세 칸이 같은 뷰 코드다 — 값만 다르다. 옆 칸은 늘 장식이고, 정착하는 동안은 가운데 칸도 장식이다 —
    /// 어느 칸도 누를 수 없고 식별자가 없어야 UI 테스트의 단일 조회가 "붙은 달"을 뜻한다.
    func strip(pages: [MonthReportPage], size: CGSize, isSettling: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.offset) { slot, page in
                pageView(page, isDecorative: slot != 1 || isSettling)
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    func pageView(_ page: MonthReportPage, isDecorative: Bool) -> some View {
        ReportMonthPageView(
            page: page,
            isDecorative: isDecorative,
            onSelectKind: viewModel.setKind,
            onSelectCategory: onSelectCategory
        )
    }

    func beginSettling() {
        settlingCount += 1
    }

    func endSettling() {
        settlingCount -= 1
        if settlingCount == 0 {
            leaving = nil
        }
    }

    /// 새 달은 이미 가운데 칸에 있다. 떠난 달을 들어오는 반대쪽 칸에 두면, 페이저가 그 칸에서 가운데로
    /// 되돌아오는 움직임이 곧 미끄러짐이다. 피커로 먼 달에 뛰어도 밀려 나가는 것은 실제로 보던 달이다.
    func slideIn(leaving outgoing: MonthReportPage) {
        let direction = viewModel.monthChangeDirection == .next ? 1 : -1
        leaving = LeavingPage(page: outgoing, offset: -direction)
        beginSettling()
        slide = MonthSlideCommand(id: UUID(), direction: direction)
    }

    /// '동작 줄이기' — 움직이지 않고, 떠난 달을 새 달 위에 얹었다가 투명하게 걷어 낸다.
    func fadeOut(_ outgoing: MonthReportPage) {
        let id = UUID()
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            fade = FadingPage(id: id, page: outgoing, opacity: 1)
            beginSettling()
        }
        withAnimation(.easeInOut(duration: MonthPaging.transitionDuration)) {
            fade?.opacity = 0
        } completion: {
            endSettling()
            // 연달아 바꾸면 앞선 페이드의 끝이 나중에 얹은 칸을 걷어 내면 안 된다.
            if fade?.id == id {
                fade = nil
            }
        }
    }
}

/// 통계 한 달 칸. 칸 값(`MonthReportPage`)만 읽는다 — 표시명·금액 문자열도 그 달 값이다.
/// 금액 탭과 도넛/막대는 고정이고, 그 아래 목록만 세로로 스크롤된다.
struct ReportMonthPageView: View {
    let page: MonthReportPage
    /// 옆 칸·정착 중 칸. 누를 수 없고 접근성에서 빠지며 식별자를 내지 않는다(메인 `MonthCalendarGrid.isDecorative`).
    let isDecorative: Bool
    let onSelectKind: (MainSummaryItem.Kind) -> Void
    let onSelectCategory: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReportSummaryTabs(
                items: page.summaryItems,
                selected: page.kind,
                isDecorative: isDecorative,
                onSelect: onSelectKind
            )
            fixedChart
            list
        }
        .background(WoniColor.base10)
        .allowsHitTesting(!isDecorative)
        .accessibilityHidden(isDecorative)
    }
}

private extension ReportMonthPageView {
    /// 달·탭이 바뀌면 목록을 새로 만든다 — 새 달·새 탭의 목록은 맨 위에서 시작하고, 옆 칸도 늘 맨 위다.
    struct ListIdentity: Hashable {
        let month: MainMonth
        let kind: MainSummaryItem.Kind
    }

    @ViewBuilder
    var fixedChart: some View {
        if page.status == .loaded, !page.isMonthEmpty {
            switch page.kind {
            case .expense where !page.isTabEmpty:
                donutChart(type: .expense)
            case .income where !page.isTabEmpty:
                donutChart(type: .income)
            case .total:
                ReportCompareBars(
                    items: page.summaryItems,
                    summary: page.summary,
                    remainingTitle: WoniStrings.reportRemaining(page.language)
                )
            case .expense, .income:
                EmptyView()
            }
        }
    }

    func donutChart(type: CatalogTransactionType) -> some View {
        let selected = summaryItem(kind: page.kind)
        return DonutChartView(
            slices: page.donutSlices,
            items: page.categoryItems,
            type: type,
            modeTitle: selected?.title ?? "",
            modeTitleColor: page.kind == .expense ? WoniColor.terracotta110 : WoniColor.olive110,
            amountText: selected?.amountText ?? "",
            accessibilitySummary: page.donutAccessibilitySummary,
            isDecorative: isDecorative
        )
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
        .background(WoniColor.gray00)
    }

    var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                content

                if let warning = page.conversionWarningText {
                    conversionWarning(warning)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, 24)
        }
        .id(ListIdentity(month: page.month, kind: page.kind))
        .accessibilityIdentifier(isDecorative ? "" : "report.list")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WoniColor.base10)
    }

    @ViewBuilder
    var content: some View {
        switch page.status {
        case .loading:
            ProgressView()
                .tint(WoniColor.olive100)
                .frame(maxWidth: .infinity)
                .frame(height: 280)
        case let .failed(message):
            Text(message)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        case .loaded where page.isMonthEmpty:
            emptyMonth
        case .loaded where page.isTabEmpty:
            emptyTab(kind: page.kind)
        case .loaded:
            switch page.kind {
            case .expense:
                categoryList(items: page.categoryItems, type: .expense)
                    .padding(.top, 16)
            case .income:
                categoryList(items: page.categoryItems, type: .income)
                    .padding(.top, 16)
            case .total:
                VStack(spacing: 0) {
                    totalSection(kind: .expense, type: .expense, items: page.expenseCategoryItems)
                    totalSection(kind: .income, type: .income, items: page.incomeCategoryItems)
                }
            }
        }
    }

    var emptyMonth: some View {
        Text(WoniStrings.reportMonthEmpty(page.language))
            .woniFont(.body2)
            .foregroundStyle(WoniColor.gray60)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 280)
            .accessibilityIdentifier(isDecorative ? "" : "report.empty.month")
    }

    func emptyTab(kind: MainSummaryItem.Kind) -> some View {
        VStack(spacing: 8) {
            Text(WoniStrings.reportTabEmptyTitle(kind, language: page.language))
                .woniFont(.body2)
                .foregroundStyle(WoniColor.gray100)
            Text(WoniStrings.reportTabEmptyHint(kind, language: page.language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isDecorative ? "" : "report.empty.tab")
    }

    func categoryList(items: [ReportCategoryItem], type: CatalogTransactionType) -> some View {
        ReportCategoryListView(
            items: items,
            type: type,
            categoryName: page.categoryDisplayName,
            formatAmount: page.formatAmount,
            onSelect: onSelectCategory,
            isDecorative: isDecorative
        )
    }

    func totalSection(
        kind: MainSummaryItem.Kind,
        type: CatalogTransactionType,
        items: [ReportCategoryItem]
    ) -> some View {
        let item = summaryItem(kind: kind)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item?.title ?? "")
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.gray100)

                Spacer(minLength: 8)

                Text(item?.amountText ?? "")
                    .woniFont(.body2)
                    .foregroundStyle(
                        item?.tone.amountTone.foregroundColor
                            ?? WoniColor.gray100
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 16)

            if items.isEmpty {
                Text(WoniStrings.reportTabEmptyTitle(kind, language: page.language))
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray60)
                    .padding(.horizontal, 16)
            } else {
                categoryList(items: items, type: type)
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func summaryItem(kind: MainSummaryItem.Kind) -> MainSummaryItem? {
        page.summaryItems.first { $0.kind == kind }
    }

    func conversionWarning(_ text: String) -> some View {
        Text(text)
            .woniFont(.small1)
            .foregroundStyle(WoniColor.terracotta110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(WoniColor.terracotta10)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(isDecorative ? "" : "report.conversionWarning")
    }
}
