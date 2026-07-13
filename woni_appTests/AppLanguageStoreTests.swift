import Foundation
import Testing
@testable import woni_app

@Suite(.serialized)
@MainActor
struct AppLanguageStoreTests {
    @Test("override가 없으면 시스템 locale에서 초기 언어를 해석한다")
    func defaultsToResolvedSystemLocaleWithoutOverride() throws {
        try Self.withUserDefaultsSuite { userDefaults in
            let korean = AppLanguageStore(
                userDefaults: userDefaults,
                systemLocale: Locale(identifier: "ko_KR")
            )
            #expect(korean.language == .ko)
        }

        try Self.withUserDefaultsSuite { userDefaults in
            let english = AppLanguageStore(
                userDefaults: userDefaults,
                systemLocale: Locale(identifier: "en_US")
            )
            #expect(english.language == .en)
        }

        try Self.withUserDefaultsSuite { userDefaults in
            let japanese = AppLanguageStore(
                userDefaults: userDefaults,
                systemLocale: Locale(identifier: "ja_JP")
            )
            #expect(japanese.language == .en)
        }
    }

    @Test("language 세팅은 동일 suite의 새 인스턴스에도 override로 유지된다")
    func settingLanguagePersistsOverrideInSuite() throws {
        try Self.withUserDefaultsSuite { userDefaults, suiteName in
            let store = AppLanguageStore(
                userDefaults: userDefaults,
                systemLocale: Locale(identifier: "ko_KR")
            )
            #expect(store.language == .ko)

            store.language = .en

            let nextUserDefaults = try #require(UserDefaults(suiteName: suiteName))
            let nextStore = AppLanguageStore(
                userDefaults: nextUserDefaults,
                systemLocale: Locale(identifier: "ko_KR")
            )
            #expect(nextStore.language == .en)
        }
    }

    @Test("AppLanguage.resolved는 ko만 한국어로, 그 외는 영어로 해석한다")
    func appLanguageResolvedUsesKoreanOnlyRule() {
        #expect(AppLanguage.resolved(from: Locale(identifier: "ko_KR")) == .ko)
        #expect(AppLanguage.resolved(from: Locale(identifier: "en_US")) == .en)
        #expect(AppLanguage.resolved(from: Locale(identifier: "ja_JP")) == .en)
    }
}

private extension AppLanguageStoreTests {
    static func withUserDefaultsSuite(
        _ body: (UserDefaults) throws -> Void
    ) throws {
        try withUserDefaultsSuite { userDefaults, _ in
            try body(userDefaults)
        }
    }

    static func withUserDefaultsSuite(
        _ body: (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "woni_appTests.AppLanguageStoreTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        try body(userDefaults, suiteName)
    }
}
