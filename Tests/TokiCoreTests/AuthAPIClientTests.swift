import Foundation
import XCTest
@testable import TokiCore

final class AuthAPIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.requestHandler = nil
        super.tearDown()
    }

    func testMagicLinkRequestPostsEmailToAuthEndpoint() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/magic-link")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBodyStreamData())
            let decoded = try JSONDecoder().decode(MagicLinkRequest.self, from: body)
            XCTAssertEqual(decoded.email, "alice@example.com")

            return Self.jsonResponse(#"{ "token": "dev-magic-token" }"#)
        }

        let response = try await client.requestMagicLink(email: "alice@example.com")

        XCTAssertEqual(response.token, "dev-magic-token")
    }

    func testSessionExchangePostsTokenAndDeviceNameThenDecodesSession() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/auth/session")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBodyStreamData())
            let decoded = try JSONDecoder().decode(SessionRequest.self, from: body)
            XCTAssertEqual(decoded.token, "magic-token")
            XCTAssertEqual(decoded.deviceName, "Alice Mac")

            return Self.jsonResponse(
                """
                {
                  "sessionToken": "session-token",
                  "user": { "id": "user-1", "email": "alice@example.com", "displayName": "Alice" },
                  "teamMemberships": [
                    {
                      "id": "membership-1",
                      "team": { "id": "team-1", "displayName": "Design" },
                      "role": "member"
                    }
                  ],
                  "device": { "id": "device-1", "name": "Alice Mac" }
                }
                """
            )
        }

        let response = try await client.createSession(token: "magic-token", deviceName: "Alice Mac")

        XCTAssertEqual(response.sessionToken, "session-token")
        XCTAssertEqual(response.user.id, UserID("user-1"))
        XCTAssertEqual(response.teamMemberships.first?.team.id, TeamID("team-1"))
        XCTAssertEqual(response.device.id, DeviceID("device-1"))
    }

    func testAuthenticatedFetchesAttachBearerTokenAndDecodeCurrentUserAndConversations() async throws {
        var requestedPaths: [String] = []
        let client = makeClient { request in
            requestedPaths.append(request.url?.path ?? "")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")

            if request.url?.path == "/v1/me" {
                return Self.jsonResponse(
                    """
                    {
                      "user": { "id": "user-1", "email": "alice@example.com", "displayName": "Alice" },
                      "teamMemberships": [],
                      "devices": [{ "id": "device-1", "name": "Alice Mac" }]
                    }
                    """
                )
            }

            return Self.jsonResponse(
                """
                {
                  "conversations": [
                    {
                      "id": "conversation-1",
                      "type": "group",
                      "displayName": "Design",
                      "members": [
                        {
                          "user": { "id": "user-1", "email": "alice@example.com", "displayName": "Alice" },
                          "role": "member"
                        }
                      ],
                      "lastPresence": { "onlineUserIds": ["user-1"], "activeSpeakerId": null }
                    }
                  ]
                }
                """
            )
        }

        let currentUser = try await client.currentUser(sessionToken: "session-token")
        let conversations = try await client.conversations(sessionToken: "session-token")

        XCTAssertEqual(requestedPaths, ["/v1/me", "/v1/conversations"])
        XCTAssertEqual(currentUser.devices.first?.name, "Alice Mac")
        XCTAssertEqual(conversations.conversations.first?.id, ConversationID("conversation-1"))
        XCTAssertEqual(conversations.conversations.first?.lastPresence.onlineUserIDs, [UserID("user-1")])
    }

    func testCreateConversationPostsTypeMembersAndDisplayName() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/conversations")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
            let body = try XCTUnwrap(request.httpBodyStreamData())
            let decoded = try JSONDecoder().decode(CreateConversationRequest.self, from: body)
            XCTAssertEqual(decoded.type, .group)
            XCTAssertEqual(decoded.memberIDs, [UserID("user-2"), UserID("user-3")])
            XCTAssertEqual(decoded.displayName, "Launch")

            return Self.jsonResponse(
                """
                {
                  "conversation": {
                    "id": "conversation-2",
                    "type": "group",
                    "displayName": "Launch",
                    "members": [],
                    "lastPresence": { "onlineUserIds": [], "activeSpeakerId": null }
                  }
                }
                """
            )
        }

        let response = try await client.createConversation(
            type: .group,
            memberIDs: [UserID("user-2"), UserID("user-3")],
            displayName: "Launch",
            sessionToken: "session-token"
        )

        XCTAssertEqual(response.conversation.id, ConversationID("conversation-2"))
        XCTAssertEqual(response.conversation.type, .group)
    }

    func testAddConversationMembersPostsMembersToConversationEndpoint() async throws {
        let client = makeClient { request in
            XCTAssertEqual(request.url?.path, "/v1/conversations/conversation-2/members")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
            let body = try XCTUnwrap(request.httpBodyStreamData())
            let decoded = try JSONDecoder().decode(AddConversationMembersRequest.self, from: body)
            XCTAssertEqual(decoded.memberIDs, [UserID("user-4")])

            return Self.jsonResponse(
                """
                {
                  "conversation": {
                    "id": "conversation-2",
                    "type": "group",
                    "displayName": "Launch",
                    "members": [
                      {
                        "user": { "id": "user-4", "email": "dana@example.com", "displayName": "Dana" },
                        "role": "member"
                      }
                    ],
                    "lastPresence": { "onlineUserIds": [], "activeSpeakerId": null }
                  }
                }
                """
            )
        }

        let response = try await client.addConversationMembers(
            conversationID: ConversationID("conversation-2"),
            memberIDs: [UserID("user-4")],
            sessionToken: "session-token"
        )

        XCTAssertEqual(response.conversation.members.first?.user.id, UserID("user-4"))
    }

    private func makeClient(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> TokiAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        URLProtocolStub.requestHandler = handler

        return TokiAPIClient(
            baseURL: URL(string: "https://api.example.com")!,
            urlSession: URLSession(configuration: configuration)
        )
    }

    private static func jsonResponse(_ json: String) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: URL(string: "https://api.example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func httpBodyStreamData() -> Data? {
        if let httpBody {
            return httpBody
        }

        guard let stream = httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}
