import Foundation
import Testing
@testable import woni_app

/// 게시본(`docs/legal/*.md`)과 앱 내 표시본(`TermsOfServiceText`)이 갈라지지 않는지 지킨다.
///
/// 약관은 웹에 공개한 문서와 앱이 보여주는 문서가 같아야 한다. 그런데 UITest 픽스처는 조 제목과
/// 문단 개수만 세므로 본문을 오기해도 통과한다(실제로 영문 제4조 2항이 한 번 어긋난 적이 있다).
/// 여기서 전문을 문자 단위로 대조해 그 공백을 메운다.
///
/// 마크다운을 리소스로 번들에 넣으면 `project.pbxproj`를 고쳐야 하므로, `#filePath`로 소스 트리를
/// 직접 읽는다. 테스트는 항상 체크아웃된 저장소에서 돌기 때문에 이 경로는 로컬·CI 모두에서 유효하다.
struct LegalTextParityTests {
    @Test("한국어 약관 앱 표시본이 게시본과 일치한다")
    func koreanTermsMatchPublishedMarkdown() throws {
        try assertParity(
            markdownFile: "terms-of-service.ko.md",
            articlePrefix: "제",
            clauses: TermsOfServiceText.korean
        )
    }

    @Test("영어 약관 앱 표시본이 게시본과 일치한다")
    func englishTermsMatchPublishedMarkdown() throws {
        try assertParity(
            markdownFile: "terms-of-service.en.md",
            articlePrefix: "Article",
            clauses: TermsOfServiceText.english
        )
    }
}

private extension LegalTextParityTests {
    /// 번호 붙은 조항만 대조한다. 게시본의 "문의처"·"부칙"은 값이 확정되면 앱에 들어갈 예정이라
    /// 지금은 한쪽에만 있는 것이 정상이고, 그 차이로 이 테스트가 깨지면 안 된다.
    func assertParity(
        markdownFile: String,
        articlePrefix: String,
        clauses: [LegalClause]
    ) throws {
        let published = try Self.articles(in: markdownFile, prefix: articlePrefix)
        let inApp = clauses
            .filter { $0.title.hasPrefix(articlePrefix) }
            .map { (title: $0.title, body: Self.normalizedLines($0.body)) }

        #expect(
            published.map(\.title) == inApp.map(\.title),
            "\(markdownFile): 조 제목과 순서가 앱 표시본과 다르다"
        )

        for (expected, actual) in zip(published, inApp) where expected.title == actual.title {
            #expect(
                expected.body == actual.body,
                "\(markdownFile) \(expected.title): \(Self.describeDifference(expected.body, actual.body))"
            )
        }
    }

    static func articles(in fileName: String, prefix: String) throws -> [(title: String, body: [String])] {
        let url = repositoryRoot
            .appendingPathComponent("docs/legal")
            .appendingPathComponent(fileName)
        let markdown = try String(contentsOf: url, encoding: .utf8)

        return markdown
            .components(separatedBy: "\n## ")
            .dropFirst()
            .compactMap { section in
                guard let newline = section.firstIndex(of: "\n") else { return nil }
                let title = String(section[section.startIndex ..< newline])
                guard title.hasPrefix(prefix) else { return nil }
                return (title, normalizedLines(String(section[newline...])))
            }
    }

    /// 마크다운 장식을 걷어내고 본문을 줄 배열로 만든다. `Text(clause.body)`는 `String` 오버로드라
    /// 마크다운을 해석하지 않으므로 앱 표시본에는 볼드 표기가 없고, 목록 기호도 " · "로 다르다.
    ///
    /// 줄을 하나로 합치지 않고 배열로 남기는 것이 요점이다. 전부 이어붙여 공백만 축약하면 문구가
    /// 같고 줄바꿈만 사라진 경우 — 앱에서는 여러 항이 한 문단으로 붙어 보인다 — 를 놓친다.
    /// Swift 본문의 줄 끝 `\`는 컴파일 시점에 이미 이어지므로, 남은 줄바꿈이 곧 화면의 줄바꿈이다.
    static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "**", with: "")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let listMarked = trimmed.hasPrefix("- ") ? "· " + trimmed.dropFirst(2) : trimmed
                return listMarked.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
    }

    /// 실패 메시지에 배열 전체를 쏟지 않고 처음 어긋난 지점만 짚어 준다.
    static func describeDifference(_ published: [String], _ inApp: [String]) -> String {
        for (index, (expected, actual)) in zip(published, inApp).enumerated() where expected != actual {
            return "\(index + 1)번째 줄이 다르다\n  게시본: \(expected)\n  앱: \(actual)"
        }
        return "줄 수가 다르다 (게시본 \(published.count)줄, 앱 \(inApp.count)줄)"
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // woni_appTests
            .deletingLastPathComponent() // 저장소 루트
    }
}
