import Foundation
import Testing

@testable import supacode

struct RemoteWebViewLoadPolicyTests {
  @Test func first_load_requires_navigation() {
    let target = URL(string: "https://example.com/mini-terminal/")!

    #expect(
      RemoteWebViewLoadPolicy.shouldLoad(
        currentURL: nil,
        targetURL: target,
        keepAlive: false
      )
    )
  }

  @Test func keep_alive_disabled_reloads_when_url_differs() {
    let current = URL(string: "https://example.com/mini-terminal/session/abc")!
    let target = URL(string: "https://example.com/mini-terminal/")!

    #expect(
      RemoteWebViewLoadPolicy.shouldLoad(
        currentURL: current,
        targetURL: target,
        keepAlive: false
      )
    )
  }

  @Test func keep_alive_enabled_preserves_existing_page_state() {
    let current = URL(string: "https://example.com/mini-terminal/session/abc")!
    let target = URL(string: "https://example.com/mini-terminal/")!

    #expect(
      !RemoteWebViewLoadPolicy.shouldLoad(
        currentURL: current,
        targetURL: target,
        keepAlive: true
      )
    )
  }
}
