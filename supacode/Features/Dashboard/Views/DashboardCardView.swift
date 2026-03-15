import AppKit
import SwiftUI

struct DashboardCardView: View {
  let repositoryName: String
  let worktreeName: String
  let surfaceView: GhosttySurfaceView
  let isFocused: Bool
  let hasUnseenNotification: Bool
  let cardSize: CGSize
  let onTap: () -> Void
  let onDragPosition: (CGSize) -> Void
  let onDragPositionEnd: () -> Void
  let onResize: (CardResizeEdge, CGSize) -> Void
  let onResizeEnd: () -> Void

  enum CardResizeEdge {
    case leading, trailing, bottom
    case bottomLeading, bottomTrailing
  }

  private let titleBarHeight: CGFloat = 28
  private let edgeThickness: CGFloat = 6
  private let cornerSize: CGFloat = 12
  private let cornerRadius: CGFloat = 8

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      terminalContent
    }
    .frame(width: cardSize.width, height: cardSize.height + titleBarHeight)
    .clipShape(.rect(cornerRadius: cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius)
        .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isFocused ? 2 : 1)
    }
    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    .overlay { resizeHandles }
    .contentShape(.rect)
    .accessibilityAddTraits(.isButton)
    .onTapGesture { onTap() }
  }

  private var titleBar: some View {
    HStack(spacing: 6) {
      if hasUnseenNotification {
        Circle()
          .fill(Color.orange)
          .frame(width: 6, height: 6)
      }
      Text(repositoryName)
        .font(.caption.bold())
        .lineLimit(1)
      Text("/ \(worktreeName)")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
    }
    .padding(.horizontal, 8)
    .frame(height: titleBarHeight)
    .frame(maxWidth: .infinity)
    .background(.bar)
    .gesture(
      DragGesture()
        .onChanged { value in onDragPosition(value.translation) }
        .onEnded { _ in onDragPositionEnd() }
    )
  }

  private var terminalContent: some View {
    GhosttyTerminalView(surfaceView: surfaceView)
      .frame(width: cardSize.width, height: cardSize.height)
      .allowsHitTesting(isFocused)
  }

  // MARK: - Resize Handles

  private var resizeHandles: some View {
    ZStack {
      // Edge handles
      edgeHandle(.resizeLeftRight, alignment: .leading) { translation in
        onResize(.leading, translation)
      }
      edgeHandle(.resizeLeftRight, alignment: .trailing) { translation in
        onResize(.trailing, translation)
      }
      edgeHandle(.resizeUpDown, alignment: .bottom) { translation in
        onResize(.bottom, translation)
      }

      // Corner handles
      cornerHandle(alignment: .bottomLeading) { translation in
        onResize(.bottomLeading, translation)
      }
      cornerHandle(alignment: .bottomTrailing) { translation in
        onResize(.bottomTrailing, translation)
      }
    }
  }

  private func edgeHandle(
    _ cursor: NSCursor,
    alignment: Alignment,
    onChange: @escaping (CGSize) -> Void
  ) -> some View {
    let isVertical = alignment == .leading || alignment == .trailing
    return ResizeCursorView(cursor: cursor) {
      Color.clear
        .frame(
          width: isVertical ? edgeThickness : nil,
          height: isVertical ? nil : edgeThickness
        )
        .frame(
          maxWidth: isVertical ? nil : .infinity,
          maxHeight: isVertical ? .infinity : nil
        )
        .contentShape(.rect)
        .gesture(
          DragGesture()
            .onChanged { value in onChange(value.translation) }
            .onEnded { _ in onResizeEnd() }
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }

  private func cornerHandle(
    alignment: Alignment,
    onChange: @escaping (CGSize) -> Void
  ) -> some View {
    ResizeCursorView(cursor: .crosshair) {
      Color.clear
        .frame(width: cornerSize, height: cornerSize)
        .contentShape(.rect)
        .gesture(
          DragGesture()
            .onChanged { value in onChange(value.translation) }
            .onEnded { _ in onResizeEnd() }
        )
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }
}

private struct ResizeCursorView<Content: View>: View {
  let cursor: NSCursor
  @ViewBuilder let content: Content
  @State private var isHovered = false

  var body: some View {
    content
      .onHover { hovering in
        guard hovering != isHovered else { return }
        isHovered = hovering
        if hovering {
          cursor.push()
        } else {
          NSCursor.pop()
        }
      }
      .onDisappear {
        if isHovered {
          isHovered = false
          NSCursor.pop()
        }
      }
  }
}
