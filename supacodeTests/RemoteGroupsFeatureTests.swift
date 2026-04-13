import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct RemoteGroupsFeatureTests {
  @Test func endpointNotificationRowStateUsesUnreadNotificationsOnly() {
    let endpointID = UUID()
    let readNotification = RemotePageNotification(
      id: UUID(),
      endpointID: endpointID,
      title: "Read",
      body: "done",
      isRead: true,
      createdAt: Date(timeIntervalSince1970: 10)
    )
    let unreadNotification = RemotePageNotification(
      id: UUID(),
      endpointID: endpointID,
      title: "Unread",
      body: "new",
      isRead: false,
      createdAt: Date(timeIntervalSince1970: 20)
    )

    var state = RemoteGroupsFeature.State()
    state.notificationsByEndpointID = [
      endpointID: [unreadNotification, readNotification]
    ]

    let rowState = state.notificationRowState(for: endpointID)

    #expect(rowState.showsNotificationIndicator == true)
    #expect(rowState.notifications == [unreadNotification, readNotification])
  }

  @Test func endpointNotificationRowStateHidesIndicatorWhenAllNotificationsAreRead() {
    let endpointID = UUID()
    let readNotification = RemotePageNotification(
      id: UUID(),
      endpointID: endpointID,
      title: "Read",
      body: "done",
      isRead: true,
      createdAt: Date(timeIntervalSince1970: 10)
    )

    var state = RemoteGroupsFeature.State()
    state.notificationsByEndpointID = [
      endpointID: [readNotification]
    ]

    let rowState = state.notificationRowState(for: endpointID)

    #expect(rowState.showsNotificationIndicator == false)
    #expect(rowState.notifications == [readNotification])
  }

  @Test(.dependencies) func submit_endpoint_adds_and_selects_endpoint() async throws {
    let state = RemoteGroupsFeature.State()
    state.$endpoints.withLock {
      $0 = []
    }
    state.$selection.withLock {
      $0 = .none
    }

    let store = TestStore(initialState: state) {
      RemoteGroupsFeature()
    }
    store.exhaustivity = .off

    await store.send(.submitEndpoint(urlText: "https://example.com/mini-terminal/"))

    let endpointID = try #require(store.state.endpoints.first?.id)
    #expect(store.state.selection == .overview(endpointID: endpointID))
  }

  @Test(.dependencies) func remove_endpoint_cleans_state_and_selection() async {
    let endpointID = UUID()
    let otherEndpointID = UUID()
    let notification = RemotePageNotification(
      id: UUID(),
      endpointID: endpointID,
      title: "Done",
      body: "Build succeeded",
      createdAt: Date(timeIntervalSince1970: 10)
    )

    var state = RemoteGroupsFeature.State()
    state.$endpoints.withLock {
      $0 = [
        RemoteEndpoint(id: endpointID, baseURL: URL(string: "https://example.com/mini-terminal/")!),
        RemoteEndpoint(id: otherEndpointID, baseURL: URL(string: "https://other.example.com/mini-terminal/")!),
      ]
    }
    state.$selection.withLock {
      $0 = .group(endpointID: endpointID, group: "alpha")
    }
    state.notificationsByEndpointID = [
      endpointID: [notification]
    ]

    let store = TestStore(initialState: state) {
      RemoteGroupsFeature()
    }

    store.exhaustivity = .off
    await store.send(.removeEndpoint(endpointID)) {
      $0.$endpoints.withLock {
        $0 = [
          RemoteEndpoint(
            id: otherEndpointID,
            baseURL: URL(string: "https://other.example.com/mini-terminal/")!
          ),
        ]
      }
      $0.$selection.withLock {
        $0 = .none
      }
      $0.notificationsByEndpointID = [:]
    }
  }

  @Test(.dependencies) func receive_remote_notification_inserts_unread_notification_and_emits_delegate() async throws {
    let endpointID = UUID()
    let now = Date(timeIntervalSince1970: 123)
    let state = RemoteGroupsFeature.State()
    state.$endpoints.withLock {
      $0 = [
        RemoteEndpoint(id: endpointID, baseURL: URL(string: "https://example.com/mini-terminal/")!)
      ]
    }

    let store = TestStore(initialState: state) {
      RemoteGroupsFeature()
    } withDependencies: {
      $0.uuid = .incrementing
      $0.date.now = now
    }

    await store.send(
      .receiveBridgeNotification(
        endpointID: endpointID,
        title: "  Task complete  ",
        body: "  Ready to review  ",
        tag: "  job-123  "
      )
    ) {
      $0.notificationsByEndpointID[endpointID] = [
        RemotePageNotification(
          id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
          endpointID: endpointID,
          title: "Task complete",
          body: "Ready to review",
          tag: "job-123",
          createdAt: now
        )
      ]
    }
    await store.receive(
      .delegate(
        .notificationReceived(
          endpointID: endpointID,
          title: "Task complete",
          body: "Ready to review"
        )
      )
    )

    let notification = try #require(store.state.notificationsByEndpointID[endpointID]?.first)
    #expect(notification.endpointID == endpointID)
    #expect(notification.title == "Task complete")
    #expect(notification.body == "Ready to review")
    #expect(notification.tag == "job-123")
    #expect(notification.isRead == false)
    #expect(notification.createdAt == now)
  }

  @Test(.dependencies) func mark_remote_notification_read_affects_only_matching_notification() async throws {
    let endpointID = UUID()
    let firstNotification = RemotePageNotification(
      id: UUID(),
      endpointID: endpointID,
      title: "First",
      body: "Unread",
      createdAt: Date(timeIntervalSince1970: 10)
    )
    let secondNotification = RemotePageNotification(
      id: UUID(),
      endpointID: endpointID,
      title: "Second",
      body: "Still unread",
      createdAt: Date(timeIntervalSince1970: 20)
    )
    var state = RemoteGroupsFeature.State()
    state.notificationsByEndpointID = [
      endpointID: [firstNotification, secondNotification]
    ]

    let store = TestStore(initialState: state) {
      RemoteGroupsFeature()
    }

    await store.send(.markNotificationRead(endpointID: endpointID, notificationID: secondNotification.id)) {
      $0.notificationsByEndpointID[endpointID] = [
        firstNotification,
        RemotePageNotification(
          id: secondNotification.id,
          endpointID: endpointID,
          title: "Second",
          body: "Still unread",
          isRead: true,
          createdAt: Date(timeIntervalSince1970: 20)
        ),
      ]
    }

    let notifications = try #require(store.state.notificationsByEndpointID[endpointID])
    #expect(notifications[0].isRead == false)
    #expect(notifications[1].isRead == true)
  }

  @Test(.dependencies) func dismiss_all_remote_notifications_clears_all_endpoints() async {
    let firstEndpointID = UUID()
    let secondEndpointID = UUID()
    var state = RemoteGroupsFeature.State()
    state.notificationsByEndpointID = [
      firstEndpointID: [
        RemotePageNotification(
          id: UUID(),
          endpointID: firstEndpointID,
          title: "One",
          body: "",
          createdAt: Date(timeIntervalSince1970: 10)
        )
      ],
      secondEndpointID: [
        RemotePageNotification(
          id: UUID(),
          endpointID: secondEndpointID,
          title: "Two",
          body: "",
          createdAt: Date(timeIntervalSince1970: 20)
        )
      ],
    ]

    let store = TestStore(initialState: state) {
      RemoteGroupsFeature()
    }

    await store.send(.dismissAllNotifications) {
      $0.notificationsByEndpointID = [:]
    }
  }

  @Test(.dependencies) func bridge_parser_accepts_same_origin_notify_payload_and_rejects_invalid_payloads() {
    let endpointURL = URL(string: "https://example.com/mini-terminal/")!

    let valid = RemoteWebViewBridge.notificationRequest(
      from: [
        "type": "notify",
        "title": "  Task complete  ",
        "body": "  Ready to review  ",
        "tag": "  job-123  ",
      ],
      originURL: URL(string: "https://example.com/tasks/42")!,
      endpointURL: endpointURL
    )
    #expect(
      valid
        == RemoteBridgeNotificationRequest(
          title: "Task complete",
          body: "Ready to review",
          tag: "job-123"
        )
    )

    let bodyOnly = RemoteWebViewBridge.notificationRequest(
      from: [
        "type": "notify",
        "title": "   ",
        "body": "  Body fallback  ",
      ],
      originURL: URL(string: "https://example.com/jobs/7")!,
      endpointURL: endpointURL
    )
    #expect(
      bodyOnly
        == RemoteBridgeNotificationRequest(
          title: "Body fallback",
          body: "",
          tag: nil
        )
    )

    let crossOrigin = RemoteWebViewBridge.notificationRequest(
      from: [
        "type": "notify",
        "title": "Ignored",
      ],
      originURL: URL(string: "https://other.example.com/jobs/7")!,
      endpointURL: endpointURL
    )
    #expect(crossOrigin == nil)

    let emptyMessage = RemoteWebViewBridge.notificationRequest(
      from: [
        "type": "notify",
        "title": "   ",
        "body": "   ",
      ],
      originURL: URL(string: "https://example.com/jobs/7")!,
      endpointURL: endpointURL
    )
    #expect(emptyMessage == nil)

    let unsupportedType = RemoteWebViewBridge.notificationRequest(
      from: [
        "type": "ping",
        "title": "Ignored",
      ],
      originURL: URL(string: "https://example.com/jobs/7")!,
      endpointURL: endpointURL
    )
    #expect(unsupportedType == nil)
  }
}
