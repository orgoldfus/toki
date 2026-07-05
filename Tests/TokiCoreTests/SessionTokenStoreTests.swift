import XCTest
@testable import TokiCore

final class SessionTokenStoreTests: XCTestCase {
    func testInMemorySessionTokenStoreSavesLoadsAndClearsToken() throws {
        let store = InMemorySessionTokenStore()

        XCTAssertNil(try store.loadToken())

        try store.saveToken("session-token")

        XCTAssertEqual(try store.loadToken(), "session-token")

        try store.clearToken()

        XCTAssertNil(try store.loadToken())
    }

    func testLocalSettingsStoreDoesNotPersistSessionTokensInUserDefaults() throws {
        let suiteName = "TokiCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalSettingsStore(defaults: defaults)

        store.save(.default)

        let keys = Set(defaults.dictionaryRepresentation().keys)
        XCTAssertFalse(keys.contains("sessionToken"))
        XCTAssertFalse(keys.contains("authToken"))
    }
}
