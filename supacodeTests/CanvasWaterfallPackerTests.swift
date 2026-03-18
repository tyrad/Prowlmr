import CoreGraphics
import Testing

@testable import supacode

struct CanvasWaterfallPackerTests {
  private let packer = CanvasWaterfallPacker(spacing: 20, titleBarHeight: 28)

  private func card(_ key: String, width: CGFloat = 800, height: CGFloat = 550) -> CanvasWaterfallPacker.CardInfo {
    CanvasWaterfallPacker.CardInfo(key: key, size: CGSize(width: width, height: height))
  }

  // MARK: - Single column

  @Test func singleCardSingleColumn() {
    let result = packer.pack(cards: [card("a")], columns: 1, columnWidth: 800)

    let layout = try! #require(result.layouts["a"])
    // centerX = spacing + columnWidth / 2 = 20 + 400 = 420
    #expect(layout.position.x == 420)
    // centerY = spacing + (height + titleBar) / 2 = 20 + (550 + 28) / 2 = 20 + 289 = 309
    #expect(layout.position.y == 309)
    #expect(layout.size == CGSize(width: 800, height: 550))
    // totalHeight = spacing + (height + titleBar) + spacing = 20 + 578 + 20 = 618
    #expect(result.totalHeight == 618)
  }

  @Test func multipleCardsSingleColumnStackVertically() {
    let cards = [card("a", height: 400), card("b", height: 300)]
    let result = packer.pack(cards: cards, columns: 1, columnWidth: 800)

    let a = try! #require(result.layouts["a"])
    let b = try! #require(result.layouts["b"])

    // Card "a" starts at spacing (20)
    let aCardHeight: CGFloat = 400 + 28
    #expect(a.position.y == 20 + aCardHeight / 2)

    // Card "b" starts after "a" + spacing
    let bCardHeight: CGFloat = 300 + 28
    let bStartY = 20 + aCardHeight + 20
    #expect(b.position.y == bStartY + bCardHeight / 2)

    // Both in same column → same centerX
    #expect(a.position.x == b.position.x)

    // totalHeight = spacing + aCardH + spacing + bCardH + spacing
    #expect(result.totalHeight == 20 + aCardHeight + 20 + bCardHeight + 20)
  }

  // MARK: - Multiple columns

  @Test func twoCardsTwoColumnsPlaceSideBySide() {
    let cards = [card("a"), card("b")]
    let result = packer.pack(cards: cards, columns: 2, columnWidth: 800)

    let a = try! #require(result.layouts["a"])
    let b = try! #require(result.layouts["b"])

    // Same Y (both start at top)
    #expect(a.position.y == b.position.y)
    // Different X (different columns)
    #expect(a.position.x != b.position.x)
    // Column 0 centerX = 20 + 800/2 = 420
    #expect(a.position.x == 420)
    // Column 1 centerX = 20 + (800 + 20) + 800/2 = 20 + 820 + 400 = 1240
    #expect(b.position.x == 1240)
  }

  // MARK: - Waterfall distribution

  @Test func thirdCardGoesToShorterColumn() {
    let cards = [
      card("a", height: 600),
      card("b", height: 300),
      card("c", height: 200),
    ]
    let result = packer.pack(cards: cards, columns: 2, columnWidth: 800)

    let a = try! #require(result.layouts["a"])
    let b = try! #require(result.layouts["b"])
    let c = try! #require(result.layouts["c"])

    // "a" → col 0, "b" → col 1 (both start at same height)
    // After placing: col0 = 20+628+20 = 668, col1 = 20+328+20 = 368
    // "c" → col 1 (shorter)
    #expect(a.position.x == c.position.x || b.position.x == c.position.x)
    // "c" should be in col 1 (same x as "b")
    #expect(c.position.x == b.position.x)
  }

  // MARK: - Size preservation

  @Test func preservesOriginalCardSizes() {
    let cards = [
      card("a", width: 600, height: 400),
      card("b", width: 800, height: 300),
    ]
    let result = packer.pack(cards: cards, columns: 2, columnWidth: 800)

    #expect(result.layouts["a"]?.size == CGSize(width: 600, height: 400))
    #expect(result.layouts["b"]?.size == CGSize(width: 800, height: 300))
  }

  // MARK: - Edge cases

  @Test func emptyCardsReturnsSpacingHeight() {
    let result = packer.pack(cards: [], columns: 1, columnWidth: 800)
    #expect(result.layouts.isEmpty)
    #expect(result.totalHeight == 20)
  }

  @Test func moreColumnsThanCards() {
    let cards = [card("a")]
    let result = packer.pack(cards: cards, columns: 5, columnWidth: 800)

    #expect(result.layouts.count == 1)
    // Card should be in the first column
    #expect(result.layouts["a"]?.position.x == 420)
  }

  @Test func totalHeightIsMaxColumnHeight() {
    let cards = [
      card("a", height: 600),
      card("b", height: 200),
      card("c", height: 400),
    ]
    // 2 cols: a→col0, b→col1, c→col1 (shorter after b)
    // col0 = 20 + 628 + 20 = 668
    // col1 = 20 + 228 + 20 + 428 + 20 = 716
    let result = packer.pack(cards: cards, columns: 2, columnWidth: 800)
    #expect(result.totalHeight == 716)
  }
}
