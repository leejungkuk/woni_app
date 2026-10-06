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

    /// 달 피커는 루트가 탭바보다 위에 그린다 — 이 화면은 무엇을 띄울지만 알린다.
    let overlays: RootOverlayModel
    let onEdit: () -> Void
    let onSetBudget: () -> Void

    init(
        viewModel: BudgetTabViewModel,
        overlays: RootOverlayModel,
        onEdit: @escaping () -> Void,
        onSetBudget: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.overlays = overlays
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
                .tint(WoniColor.olive100)
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
