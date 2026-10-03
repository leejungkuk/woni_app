//
//  BudgetTabView.swift
//  woni_app
//

import SwiftUI

/// 예산 탭. 상태·달 이동·버튼 표시는 `BudgetTabViewModel` 이 정하고 여기서는 그리기와 입력 전달만 한다.
/// 다시 읽기 사건은 루트가 넘긴다.
struct BudgetTabView: View {
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var viewModel: BudgetTabViewModel
    /// (i) 말풍선. 열려 있는 동안 화면 어디를 눌러도 닫힌다(UI_GUIDE "아무 데나 누르면 닫힌다").
    @State private var isInfoOpen = false

    /// 달 피커·알림 창은 루트가 탭바보다 위에 그린다 — 이 화면은 무엇을 띄울지만 알린다.
    let overlays: RootOverlayModel
    /// "알림을 받을까요?" 창을 물을지·어떤 모양인지 정한다.
    let notificationPreference: NotificationPreferenceController
    /// 지금 창을 띄울 수 있는지(선택된 탭·가림). 루트가 만든다.
    let askGate: NotificationAskGate
    let onEdit: () -> Void
    let onSetBudget: () -> Void

    init(
        viewModel: BudgetTabViewModel,
        overlays: RootOverlayModel,
        notificationPreference: NotificationPreferenceController,
        askGate: NotificationAskGate,
        onEdit: @escaping () -> Void,
        onSetBudget: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.overlays = overlays
        self.notificationPreference = notificationPreference
        self.askGate = askGate
        self.onEdit = onEdit
        self.onSetBudget = onSetBudget
    }

    private var language: AppLanguage {
        languageStore.language
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }
        }
        .background(WoniColor.base10)
        .toolbar(.hidden, for: .navigationBar)
        // 말풍선이 열려 있을 때만 켠다 — 버튼·스크롤과 함께 인식돼 다른 곳을 눌러도 그 동작과 함께 닫힌다.
        .simultaneousGesture(
            TapGesture().onEnded { isInfoOpen = false },
            including: isInfoOpen ? .all : .subviews
        )
        // 가림·탭·보이는 응답이 바뀌면 SwiftUI 가 앞 작업을 취소한다 — 다시 읽는 사이 생긴 가림 위에 창을 띄우지 않는다.
        .task(id: notificationAskKey) {
            await askNotificationsIfNeeded()
        }
    }
}

/// "알림을 받을까요?" 창(UI_GUIDE 204-207). 물을지·모양은 컨트롤러가 정하고, 이 화면은 지금 띄울 수 있을 때 묻고 그린다.
private extension BudgetTabView {
    /// 물을지는 "정한 달인지"와 "물어봤음"만으로 정해져, 같은 달·같은 상태의 새 응답으로는 다시 묻지 않는다.
    struct NotificationAskKey: Equatable {
        let gate: NotificationAskGate
        let month: ServerMonth?
        let status: BudgetStatus?
    }

    /// 보이는 달의 응답. 로딩·실패·신원 없는 비회원이면 nil.
    var visibleBudget: MonthlyBudget? {
        guard case let .loaded(content) = viewModel.phase else {
            return nil
        }
        return content.budget
    }

    var notificationAskKey: NotificationAskKey {
        NotificationAskKey(gate: askGate, month: viewModel.month, status: visibleBudget?.status)
    }

    func askNotificationsIfNeeded() async {
        guard askGate.canAsk,
              let budget = visibleBudget,
              let variant = await notificationPreference.askIfNeeded(for: budget)
        else {
            return
        }
        // 신원 리셋으로 닫히면 답하지 않은 것이다 — 다음에 다시 묻는다(임시, 메모리 budget-open-decisions-2026-10-03 #22).
        overlays.present(.notificationAsk, content: notificationAskDialog(variant))
    }

    func notificationAskDialog(_ variant: NotificationAskVariant) -> some View {
        WoniConfirmDialog(
            title: WoniStrings.notificationAskTitle(language),
            message: variant.message(language),
            confirmTitle: variant.confirmTitle(language),
            cancelTitle: WoniStrings.notificationAskLater(language),
            identifier: "budget.notificationAsk",
            onConfirm: { answerNotificationAsk(variant.confirmAnswer) },
            onCancel: { answerNotificationAsk(.later) }
        )
    }

    /// 창을 닫는 일과 "물어봤음"을 남기는 일을 한 흐름에서 한다(`answerAsk` 는 첫 await 앞에서 남긴다) — 닫혀 다시 도는
    /// 묻기 작업이 답보다 먼저 판정하면 같은 창이 또 뜬다. 그 사이 이미 닫혔으면(연타·신원 리셋) 답하지 않는다.
    func answerNotificationAsk(_ answer: NotificationAskAnswer) {
        Task {
            guard overlays.isPresented(.notificationAsk) else {
                return
            }
            overlays.dismiss(.notificationAsk)
            await notificationPreference.answerAsk(answer)
        }
    }
}

private extension BudgetTabView {
    var header: some View {
        ZStack {
            if viewModel.showsMonthHeader, let month = viewModel.month {
                HStack(spacing: 0) {
                    monthArrow(
                        systemName: "chevron.left",
                        identifier: "budget.prev",
                        label: WoniStrings.previousMonth(language),
                        offset: -1,
                        isEnabled: viewModel.canGoPrevious
                    )

                    Button {
                        presentMonthPicker(from: month)
                    } label: {
                        Text(WoniDateFormat.monthTitle(year: month.year, month: month.month, language: language))
                            .woniFont(.body1)
                            .foregroundStyle(WoniColor.gray100)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("budget.monthTitle")

                    monthArrow(
                        systemName: "chevron.right",
                        identifier: "budget.next",
                        label: WoniStrings.nextMonth(language),
                        offset: 1,
                        isEnabled: viewModel.canGoNext
                    )
                }
                .padding(.horizontal, 72)
            }

            if viewModel.showsEditButton {
                HStack {
                    Spacer(minLength: 0)
                    editButton
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(WoniColor.gray00)
    }

    /// 월 리포트 `monthButton` 과 같은 모양에 범위 끝 비활성(`gray20`)을 더했다.
    func monthArrow(
        systemName: String,
        identifier: String,
        label: String,
        offset: Int,
        isEnabled: Bool
    ) -> some View {
        Button {
            Task { await viewModel.go(by: offset) }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isEnabled ? WoniColor.gray80 : WoniColor.gray20)
                .frame(width: 32, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// 카테고리 추가 저장 캡슐과 같은 규격.
    var editButton: some View {
        Button(action: onEdit) {
            Text(WoniStrings.budgetEdit(language))
                .woniFont(.body2)
                .foregroundStyle(WoniColor.base10)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(WoniColor.terracotta100)
                .clipShape(Capsule())
                .woniShadow(.shadow1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("budget.edit")
    }

    func presentMonthPicker(from month: ServerMonth) {
        guard let years = viewModel.pickerYears else {
            return
        }
        overlays.present(.budgetMonthPicker, content: YearMonthPickerOverlay(
            initialYear: month.year,
            initialMonth: month.month,
            years: years,
            saveColor: WoniColor.terracotta100,
            language: language,
            months: { viewModel.pickerMonths(inYear: $0) },
            onSave: { year, month in
                overlays.dismiss(.budgetMonthPicker)
                Task { await viewModel.select(year: year, month: month) }
            },
            onCancel: {
                overlays.dismiss(.budgetMonthPicker)
            }
        ))
    }

    /// 카드 순서는 총액 → 카테고리 → 결제수단(편집 화면 순서와 같다).
    @ViewBuilder
    var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .accessibilityIdentifier("budget.loading")
        case let .loaded(content) where content.budget.status == .notSet:
            setBudgetCard
        case let .loaded(content):
            VStack(spacing: 12) {
                if let total = BudgetTotalPresentation(content: content, language: language) {
                    BudgetTotalCard(presentation: total, isInfoOpen: $isInfoOpen)
                        // 말풍선이 아래 카드에 가리지 않게 한다.
                        .zIndex(1)
                }
                if let breakdown = BudgetBreakdownPresentation(content: content, language: language) {
                    BudgetBreakdownCards(presentation: breakdown)
                }
            }
        case .failed:
            messageCard {
                Text(WoniStrings.budgetLoadFailed(language))
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray60)
                    .accessibilityIdentifier("budget.loadFailed")
            }
        case .noIdentity:
            setBudgetCard
        }
    }

    /// 미설정 달·신원 없는 비회원.
    var setBudgetCard: some View {
        messageCard {
            Text(WoniStrings.budgetNotSetMessage(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray80)
            Button(action: onSetBudget) {
                Text(WoniStrings.budgetSetBudget(language))
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.base10)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(WoniColor.terracotta100)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("budget.setBudget")
        }
    }

    /// 총액 카드 자리의 메시지만 있는 카드. 카드 규격은 총액 카드와 같다.
    func messageCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(WoniColor.gray00)
                .woniShadow(.shadow1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.messageCard")
    }
}
