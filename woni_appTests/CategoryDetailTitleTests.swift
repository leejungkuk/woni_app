//
//  CategoryDetailTitleTests.swift
//  woni_appTests
//
//  카테고리 상세 머리 제목. 상세를 연 채 설정 탭에서 언어를 바꿀 수 있어, 제목을 고르는 식을 유닛으로 지킨다.
//

import Testing
@testable import woni_app

struct CategoryDetailTitleTests {
    @Test("제목은 새 언어 이름을 따르고, 새 이름을 구할 수 없으면(nil·빈 문자열) 보관한 이름을 둔다")
    func detailTitleFollowsLanguageButKeepsNameWhenUnresolved() {
        #expect(CategoryDetailView.detailTitle(stored: "식비", resolved: "Food") == "Food")
        #expect(CategoryDetailView.detailTitle(stored: "식비", resolved: nil) == "식비")
        #expect(CategoryDetailView.detailTitle(stored: "식비", resolved: "") == "식비")
    }
}
