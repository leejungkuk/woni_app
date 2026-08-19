import SwiftUI

struct MainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: MainViewModel
    @State private var isYearMonthPickerPresented = false
    /// 손가락 추종. `@GestureState`가 아닌 이유는 커밋 처리 전에 자동 리셋되어 리베이스가
    /// 무너지기 때문이다. 정착(`baseOffset`)과는 애니메이션 컨텍스트가 달라 값도 분리한다 —
    /// 하나로 합치면 정착 중 재드래그에서 목표값이 교체되며 튄다.
    @State private var dragTranslation: CGFloat = 0
    @State private var baseOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0
    /// 진행 중인 정착 수. Bool이 아니라 카운터인 이유는 `monthTransitionPauseCount`와 같다 —
    /// 정착이 겹치면 먼저 시작한 전환의 completion이 나중 전환의 창을 닫아버린다.
    @State private var settlingCount = 0
    @State private var lockedAxis: MonthPagingRule.Axis?
    @State private var gestureCommitInFlight = false
    @State private var crossfade: (month: MainMonth, days: [MainCalendarDay])?
    @State private var crossfadeOpacity: Double = 0
    /// 시스템이 제스처를 삼켜 `onEnded`가 오지 않아도 자동 리셋된다 — 방치된 추종을 되돌리는 감시용.
    @GestureState private var isDragging = false
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
        .onChange(of: isDragging) { _, dragging in
            guard !dragging else {
                return
            }

            lockedAxis = nil
            // 정상 종료는 onEnded가 이미 0으로 만든다. 남아 있다면 시스템이 제스처를 삼킨 것이다.
            guard dragTranslation != 0 else {
                return
            }

            withAnimation(settleAnimation(velocity: 0, remaining: dragTranslation)) {
                dragTranslation = 0
            }
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
        // 높이는 나가는 그리드가 아니라 현재 달 행 수로 구동해야 6주→5주에서 스냅하지 않는다.
        // 스트립을 높이 애니메이션 스코프 안에 두면 커밋 리베이스까지 애니메이션돼 이음새가 튄다 —
        // 높이만 애니메이션하는 빈 뷰 위에 스트립을 overlay로 얹어 스코프를 가른다.
        Color.clear
            .frame(height: MonthCalendarGrid.dayGridHeight(dayCount: viewModel.calendarDays.count))
            .animation(
                .spring(duration: MainViewModel.monthTransitionDuration),
                value: viewModel.selectedMonth
            )
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    monthStrip(width: proxy.size.width)
                }
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
    }

    private var isSettling: Bool {
        settlingCount > 0
    }

    /// 이전·현재·다음 달을 가로로 이어 붙인 스트립. 중앙이 화면을 채우는 상태가 두 오프셋 모두 0이다.
    /// 정렬이 `.top`이어야 한다 — 기본 `.center`면 행 수가 더 많은 이웃 달이 스트립 높이를 키우고,
    /// 그 안에서 현재 달 그리드가 아래로 내려앉아 마지막 행이 잘린다.
    private func monthStrip(width: CGFloat) -> some View {
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
        .offset(x: baseOffset - width)
        .offset(x: dragTranslation)
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

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                // 첫 이벤트에서 정한 축을 제스처가 끝날 때까지 고정한다. 저장하지 않으면
                // 세로 잠금이 후속 이벤트에서 가로로 재판정된다.
                let axis = lockedAxis ?? MonthPagingRule.axis(translation: value.translation)
                lockedAxis = axis
                guard axis == .horizontal else {
                    return
                }

                dragTranslation = value.translation.width
            }
            .onEnded { value in
                let axis = lockedAxis ?? MonthPagingRule.axis(translation: value.translation)
                lockedAxis = nil
                guard axis == .horizontal else {
                    if case let .move(step) = MonthPagingRule.verticalCommit(
                        translation: value.translation.height
                    ) {
                        Task { await viewModel.moveMonth(by: step) }
                    }
                    return
                }

                endHorizontalDrag(value)
            }
    }

    private func endHorizontalDrag(_ value: DragGesture.Value) {
        let translation = value.translation.width
        guard case let .move(step) = MonthPagingRule.horizontalCommit(
            translation: translation,
            predictedEnd: value.predictedEndTranslation.width,
            width: pageWidth
        ) else {
            withAnimation(settleAnimation(velocity: value.velocity.width, remaining: dragTranslation)) {
                dragTranslation = 0
            }
            return
        }

        // 커밋과 리베이스는 한 프레임 안에서 끝나야 한다. 사이에 비동기 홉을 두면 그 프레임에서
        // 새 달이 리베이스 없이 그려져 스트립이 한 폭만큼 튄다.
        let rebased = translation + CGFloat(step) * pageWidth
        withTransaction(Transaction(animation: nil)) {
            gestureCommitInFlight = true
            viewModel.commitGestureMonthChange(by: step)
            baseOffset = rebased
            dragTranslation = 0
            settlingCount += 1
        }
        withAnimation(settleAnimation(velocity: value.velocity.width, remaining: rebased)) {
            baseOffset = 0
        } completion: {
            settlingCount -= 1
        }
    }

    /// 픽커·세로 스와이프처럼 View 밖에서 월이 바뀐 경우. 새 달은 이미 중앙 슬롯에 있으니
    /// 방향만큼 밀어 두고 0으로 정착시키면 제스처 커밋과 같은 모습이 된다.
    private func startProgrammaticTransition() {
        guard !reduceMotion else {
            startCrossfade()
            return
        }

        let entryOffset = viewModel.monthChangeDirection == .next ? pageWidth : -pageWidth
        withTransaction(Transaction(animation: nil)) {
            baseOffset = entryOffset
            settlingCount += 1
        }
        withAnimation(settleAnimation(velocity: 0, remaining: entryOffset)) {
            baseOffset = 0
        } completion: {
            settlingCount -= 1
        }
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

    /// 놓는 순간의 속도를 그대로 이어받는 정착 스프링.
    private func settleAnimation(velocity: CGFloat, remaining: CGFloat) -> Animation {
        .interpolatingSpring(
            Spring(duration: MainViewModel.monthTransitionDuration),
            initialVelocity: MonthPagingRule.settleVelocity(velocity: velocity, remaining: remaining)
        )
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
