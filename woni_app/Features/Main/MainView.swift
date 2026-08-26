import SwiftUI

struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: MainViewModel
    @State private var isYearMonthPickerPresented = false
    /// 가로 이동은 `UIScrollView`가 구동한다 — 추종·감속·탄성을 직접 계산하지 않는다.
    @State private var slideCommand: MonthSlideCommand?
    @State private var pageWidth: CGFloat = 0
    /// 진행 중인 정착 수. Bool이 아니라 카운터인 이유는 `monthTransitionPauseCount`와 같다 —
    /// 정착이 겹치면 먼저 시작한 전환의 completion이 나중 전환의 창을 닫아버린다.
    @State private var settlingCount = 0
    @State private var gestureCommitInFlight = false
    @State private var crossfade: (month: MainMonth, days: [MainCalendarDay])?
    @State private var crossfadeOpacity: Double = 0
    let language: AppLanguage
    let onAdd: (_ defaultDate: Date) -> Void
    let onSelectEntry: (_ clientEntryID: UUID) -> Void
    let onOpenSettings: () -> Void

    init(
        viewModel: MainViewModel,
        language: AppLanguage,
        onAdd: @escaping (_ defaultDate: Date) -> Void,
        onSelectEntry: @escaping (_ clientEntryID: UUID) -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.language = language
        self.onAdd = onAdd
        self.onSelectEntry = onSelectEntry
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                MonthHeaderView(
                    monthTitle: viewModel.monthTitle,
                    language: language,
                    onOpenMonthPicker: {
                        isYearMonthPickerPresented = true
                    },
                    onOpenSettings: onOpenSettings
                )
                .zIndex(1)

                TotalsSummaryView(items: viewModel.summaryItems)

                calendarContent

                ScrollView {
                    HistoryListView(
                        dateTitle: viewModel.historyDateTitle,
                        rows: viewModel.historyRows,
                        conversionWarningText: viewModel.conversionWarningText,
                        onSelectEntry: onSelectEntry
                    )
                    .padding(.bottom, 76)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WoniColor.base10)
            }
            .background(WoniColor.base10)

            addButton
                .padding(16)

            if isYearMonthPickerPresented {
                YearMonthPickerOverlay(
                    initialYear: viewModel.selectedMonth.year,
                    initialMonth: viewModel.selectedMonth.month,
                    language: language,
                    onSave: { year, month in
                        isYearMonthPickerPresented = false
                        Task {
                            await viewModel.setMonth(year: year, month: month)
                        }
                    },
                    onCancel: {
                        isYearMonthPickerPresented = false
                    }
                )
                .zIndex(2)
            }
        }
        .background(WoniColor.base10)
        .ignoresSafeArea(.container, edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.selectedMonth) { _, _ in
            // 제스처 커밋은 View가 이미 리베이스했다. 플래그는 진입 즉시 소비한다 —
            // 남겨두면 이후 프로그램적 전환이 영구히 무모션이 된다.
            let wasGestureCommit = gestureCommitInFlight
            gestureCommitInFlight = false
            guard !wasGestureCommit else {
                return
            }

            startProgrammaticTransition()
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        if viewModel.isInitialLoading {
            ProgressView()
                .tint(WoniColor.olive100)
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .background(WoniColor.gray00)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(WoniColor.gray00)
        } else {
            MonthCalendarContainer(language: language, dayGrid: calendarDayGrid)
                .gesture(pagingGesture)
        }
    }

    private var calendarDayGrid: some View {
        // 스트립을 높이 애니메이션 스코프 안에 두면 커밋 리베이스까지 애니메이션돼 이음새가 튄다 —
        // 높이만 애니메이션하는 빈 뷰 위에 스트립을 overlay로 얹어 스코프를 가른다.
        Color.clear
            .frame(height: calendarGridHeight)
            .animation(
                .spring(duration: MainViewModel.monthTransitionDuration),
                value: calendarGridHeight
            )
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    MonthPagingScrollView(
                        onCommit: { step in
                            gestureCommitInFlight = true
                            viewModel.commitGestureMonthChange(by: step)
                        },
                        onScrollActivity: { scrolling in
                            settlingCount += scrolling ? 1 : -1
                        },
                        slide: slideCommand,
                        onSlideFinished: {
                            settlingCount -= 1
                        },
                        content: {
                            monthStrip(width: proxy.size.width, height: proxy.size.height)
                        }
                    )
                }
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
    }

    private var isSettling: Bool {
        settlingCount > 0
    }

    /// 미는 동안에는 딸려 들어오는 이웃 달이 잘리거나 아래가 뜨지 않도록 화면에 걸친 달 중
    /// 가장 큰 높이로 잡아 둔다. 정착하면 현재 달 높이로 돌아오며, 그 변화가 곧 "전환이 끝나고
    /// 하단이 늘었다 줄었다" 하는 모습이 된다. 높이는 나가는 그리드가 아니라 현재 달 행 수로
    /// 구동해야 6주→5주에서 스냅하지 않는다.
    private var calendarGridHeight: CGFloat {
        let current = MonthCalendarGrid.dayGridHeight(dayCount: viewModel.calendarDays.count)
        guard isSettling else {
            return current
        }

        let neighbors = [-1, 1].map {
            MonthCalendarGrid.dayGridHeight(dayCount: neighborDays(offset: $0).count)
        }
        return max(current, neighbors.max() ?? current)
    }

    /// 이전·현재·다음 달을 가로로 이어 붙인 스트립. 중앙이 화면을 채우는 상태가 두 오프셋 모두 0이다.
    /// 정렬이 `.top`이어야 한다 — 기본 `.center`면 행 수가 더 많은 이웃 달이 스트립 높이를 키우고,
    /// 그 안에서 현재 달 그리드가 아래로 내려앉아 마지막 행이 잘린다.
    private func monthStrip(width: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            decorativeGrid(days: neighborDays(offset: -1), width: width)

            // 정착 중엔 중앙도 닫는다 — 어느 달도 노출되지 않아야 날짜 셀 카운트가
            // "전환 완료"를 뜻한다(UI 테스트 waitForMonth가 이 계약에 기댄다).
            monthGrid(days: viewModel.calendarDays, width: width, isDecorative: isSettling)
                .allowsHitTesting(!isSettling)
                .overlay(alignment: .top) {
                    if let crossfade {
                        decorativeGrid(days: crossfade.days, width: width)
                            .opacity(crossfadeOpacity)
                    }
                }

            decorativeGrid(days: neighborDays(offset: 1), width: width)
        }
        // 높이를 명시해 스트립이 컨테이너보다 커지는 상황 자체를 없앤다. 스트립은 세 달 중 가장
        // 큰 달만큼 커지는데 정착하면 컨테이너는 현재 달 높이로 줄어든다. 그 넘침을 그대로 두면
        // 콘텐츠가 세로 중앙에 놓이며 그리드 전체가 차이의 절반만큼 위로 밀려, 첫 행이 요일 헤더를
        // 파고든다(실측: 6행 옆 5행에서 32pt — day1 y가 209.67→177.67로 헤더 186보다 위로 갔다).
        // 클리핑은 바깥 `calendarDayGrid`가 이미 한다 — 여기서 또 자르면 히트 테스팅 영역까지
        // 잘려 날짜 셀 탭이 죽는다(2026-08-23 실기 회귀).
        .frame(height: height, alignment: .top)
    }

    /// 정착 중에는 나가는 달이 실제 인접 월이 아니어도(피커로 먼 달 점프) 나가는 쪽 슬롯에 보존본을
    /// 둔다 — 그러지 않으면 1월에서 3월로 뛸 때 밀려 나가는 것이 1월이 아니라 2월 골격이 된다.
    private func neighborDays(offset: Int) -> [MainCalendarDay] {
        let outgoingSlot = viewModel.monthChangeDirection == .next ? -1 : 1
        if isSettling, offset == outgoingSlot, let outgoing = viewModel.outgoingCalendarDays {
            return outgoing.days
        }

        return viewModel.neighborCalendarDays(offset: offset)
    }

    private func monthGrid(days: [MainCalendarDay], width: CGFloat, isDecorative: Bool) -> some View {
        MonthCalendarGrid(
            days: days,
            language: language,
            isDecorative: isDecorative,
            formatAmount: viewModel.formatBaseAmount,
            onSelect: { day in
                viewModel.selectDay(day)
            }
        )
        .frame(width: width, alignment: .top)
    }

    private func decorativeGrid(days: [MainCalendarDay], width: CGFloat) -> some View {
        monthGrid(days: days, width: width, isDecorative: true)
            .allowsHitTesting(false)
    }

    /// 세로 스와이프 월 이동은 종전 규칙 그대로다. 가로는 `UIScrollView`가 가져가므로
    /// 여기서는 세로만 판정한다 — 축 잠금·반 폭 임계는 더 이상 우리 몫이 아니다.
    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard MonthPagingRule.axis(translation: value.translation) == .vertical,
                      case let .move(step) = MonthPagingRule.verticalCommit(
                          translation: value.translation.height
                      )
                else {
                    return
                }

                Task { await viewModel.moveMonth(by: step) }
            }
    }

    /// 픽커·세로 스와이프처럼 View 밖에서 월이 바뀐 경우. 새 달은 이미 중앙 슬롯에 있으니
    /// 방향만큼 밀어 두고 0으로 정착시키면 제스처 커밋과 같은 모습이 된다.
    private func startProgrammaticTransition() {
        guard !reduceMotion else {
            startCrossfade()
            return
        }

        settlingCount += 1
        slideCommand = MonthSlideCommand(
            id: UUID(),
            direction: viewModel.monthChangeDirection == .next ? 1 : -1
        )
    }

    private func startCrossfade() {
        guard let outgoing = viewModel.outgoingCalendarDays else {
            return
        }

        withTransaction(Transaction(animation: nil)) {
            crossfade = outgoing
            crossfadeOpacity = 1
            settlingCount += 1
        }
        withAnimation(.easeInOut(duration: MainViewModel.monthTransitionDuration)) {
            crossfadeOpacity = 0
        } completion: {
            settlingCount -= 1
            // 연속 전환에서 앞선 페이드의 완료가 새 오버레이를 걷어내면 안 된다.
            guard crossfade?.month == outgoing.month else {
                return
            }

            crossfade = nil
        }
    }

    private var addButton: some View {
        Button {
            onAdd(viewModel.defaultEntryDate)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WoniColor.base10)
                .frame(width: 52, height: 52)
                .background(WoniColor.terracotta100)
                .clipShape(Circle())
                .woniShadow(.shadow1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("main.add")
        .accessibilityLabel(WoniStrings.addTransactionA11y(language))
    }
}

#Preview {
    if let dependencies = try? AppDependencyFactory.makeSeedDependencies(inMemory: true) {
        MainView(
            viewModel: MainViewModel(
                transactionRepository: dependencies.transactionRepository,
                catalogProvider: dependencies.catalogProvider,
                customCategoryStore: dependencies.customCategoryStore,
                rateProvider: dependencies.mainRateProvider,
                baseRateResolver: BaseRateResolver(
                    cache: dependencies.exchangeRateCache,
                    seedRateProvider: dependencies.mainRateProvider
                ),
                baseCurrency: .krw
            ),
            language: .ko,
            onAdd: { _ in },
            onSelectEntry: { _ in },
            onOpenSettings: {}
        )
    } else {
        Text("Preview unavailable")
    }
}
