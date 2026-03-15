import SwiftUI

struct DashboardView: View {
  let terminalManager: WorktreeTerminalManager
  @State private var layoutStore = DashboardLayoutStore()

  @State private var canvasOffset: CGSize = .zero
  @State private var lastCanvasOffset: CGSize = .zero
  @State private var canvasScale: CGFloat = 1.0
  @State private var lastCanvasScale: CGFloat = 1.0
  @State private var focusedWorktreeID: Worktree.ID?
  @State private var dragOffset: [Worktree.ID: CGSize] = [:]
  @State private var activeResize: [Worktree.ID: ActiveResize] = [:]

  private let minCardWidth: CGFloat = 300
  private let minCardHeight: CGFloat = 200
  private let maxCardWidth: CGFloat = 1200
  private let maxCardHeight: CGFloat = 900
  private let titleBarHeight: CGFloat = 28

  var body: some View {
    GeometryReader { geometry in
      let activeStates = terminalManager.activeWorktreeStates

      // Background layer: handles canvas pan and tap-to-unfocus.
      // Placed first so cards are on top for hit testing.
      Color.clear
        .contentShape(.rect)
        .accessibilityAddTraits(.isButton)
        .onTapGesture { unfocusAll() }
        .gesture(canvasPanGesture)

      // Cards layer: each card is scaled and positioned individually.
      ForEach(activeStates, id: \.worktreeID) { state in
        if let surfaceView = state.activeSurfaceView {
          let baseLayout = resolvedLayout(for: state.worktreeID, canvasSize: geometry.size)
          let computed = computedFrame(for: state.worktreeID, baseLayout: baseLayout)
          DashboardCardView(
            repositoryName: Repository.name(for: state.repositoryRootURL),
            worktreeName: state.worktreeName,
            surfaceView: surfaceView,
            isFocused: focusedWorktreeID == state.worktreeID,
            hasUnseenNotification: state.hasUnseenNotification,
            cardSize: computed.size,
            onTap: { focusCard(state.worktreeID, states: activeStates) },
            onDragPosition: { translation in dragOffset[state.worktreeID] = translation },
            onDragPositionEnd: { commitDrag(for: state.worktreeID) },
            onResize: { edge, translation in
              activeResize[state.worktreeID] = ActiveResize(edge: edge, translation: translation)
            },
            onResizeEnd: { commitResize(for: state.worktreeID, surfaceView: surfaceView) }
          )
          .scaleEffect(canvasScale, anchor: .center)
          .position(screenPosition(for: computed.center))
          .zIndex(focusedWorktreeID == state.worktreeID ? 1 : 0)
        }
      }
    }
    .contentShape(.rect)
    .simultaneousGesture(canvasZoomGesture)
    .task { activateDashboard() }
    .onDisappear { deactivateDashboard() }
  }

  // MARK: - Canvas Gestures

  private var canvasPanGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        canvasOffset = CGSize(
          width: lastCanvasOffset.width + value.translation.width,
          height: lastCanvasOffset.height + value.translation.height
        )
      }
      .onEnded { _ in
        lastCanvasOffset = canvasOffset
      }
  }

  private var canvasZoomGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        canvasScale = max(0.25, min(2.0, lastCanvasScale * value.magnification))
      }
      .onEnded { _ in
        lastCanvasScale = canvasScale
      }
  }

  // MARK: - Layout

  private func resolvedLayout(for worktreeID: Worktree.ID, canvasSize: CGSize) -> DashboardCardLayout {
    if let existing = layoutStore.cardLayouts[worktreeID] {
      return existing
    }
    let position = autoPosition(for: worktreeID, canvasSize: canvasSize)
    let layout = DashboardCardLayout(position: position)
    layoutStore.cardLayouts[worktreeID] = layout
    return layout
  }

  private func autoPosition(for worktreeID: Worktree.ID, canvasSize: CGSize) -> CGPoint {
    let existingCount = layoutStore.cardLayouts.count
    let cardW = DashboardCardLayout.defaultSize.width
    let cardH = DashboardCardLayout.defaultSize.height + titleBarHeight
    let spacing: CGFloat = 20
    let columns = max(1, Int(canvasSize.width / (cardW + spacing)))
    let row = existingCount / columns
    let col = existingCount % columns
    return CGPoint(
      x: spacing + (cardW + spacing) * CGFloat(col) + cardW / 2,
      y: spacing + (cardH + spacing) * CGFloat(row) + cardH / 2
    )
  }

  /// Compute effective center and size for a card, accounting for drag and resize.
  private func computedFrame(
    for worktreeID: Worktree.ID,
    baseLayout: DashboardCardLayout
  ) -> (center: CGPoint, size: CGSize) {
    var centerX = baseLayout.position.x
    var centerY = baseLayout.position.y
    var width = baseLayout.size.width
    var height = baseLayout.size.height

    // Apply drag offset (in canvas space)
    let drag = dragOffset[worktreeID] ?? .zero
    centerX += drag.width
    centerY += drag.height

    // Apply resize with proper edge anchoring
    if let resize = activeResize[worktreeID] {
      let translationX = resize.translation.width
      let translationY = resize.translation.height

      switch resize.edge {
      case .trailing:
        let newW = clampWidth(width + translationX)
        centerX += (newW - width) / 2
        width = newW

      case .leading:
        let newW = clampWidth(width - translationX)
        centerX -= (newW - width) / 2
        width = newW

      case .bottom:
        let newH = clampHeight(height + translationY)
        centerY += (newH - height) / 2
        height = newH

      case .bottomTrailing:
        let newW = clampWidth(width + translationX)
        let newH = clampHeight(height + translationY)
        centerX += (newW - width) / 2
        centerY += (newH - height) / 2
        width = newW
        height = newH

      case .bottomLeading:
        let newW = clampWidth(width - translationX)
        let newH = clampHeight(height + translationY)
        centerX -= (newW - width) / 2
        centerY += (newH - height) / 2
        width = newW
        height = newH
      }
    }

    return (CGPoint(x: centerX, y: centerY), CGSize(width: width, height: height))
  }

  /// Convert canvas-space center to screen-space position for SwiftUI `.position()`.
  private func screenPosition(for canvasCenter: CGPoint) -> CGPoint {
    CGPoint(
      x: canvasCenter.x * canvasScale + canvasOffset.width,
      y: canvasCenter.y * canvasScale + canvasOffset.height
    )
  }

  private func clampWidth(_ width: CGFloat) -> CGFloat {
    max(minCardWidth, min(maxCardWidth, width))
  }

  private func clampHeight(_ height: CGFloat) -> CGFloat {
    max(minCardHeight, min(maxCardHeight, height))
  }

  // MARK: - Drag

  private func commitDrag(for worktreeID: Worktree.ID) {
    guard let drag = dragOffset[worktreeID] else { return }
    if var layout = layoutStore.cardLayouts[worktreeID] {
      layout.position.x += drag.width
      layout.position.y += drag.height
      layoutStore.cardLayouts[worktreeID] = layout
    }
    dragOffset[worktreeID] = nil
  }

  // MARK: - Resize

  private func commitResize(for worktreeID: Worktree.ID, surfaceView: GhosttySurfaceView) {
    guard let resize = activeResize[worktreeID] else { return }
    if var layout = layoutStore.cardLayouts[worktreeID] {
      let computed = computedFrame(for: worktreeID, baseLayout: layout)
      layout.position = computed.center
      layout.size = computed.size
      layoutStore.cardLayouts[worktreeID] = layout
    }
    activeResize[worktreeID] = nil
    surfaceView.needsLayout = true
    surfaceView.needsDisplay = true
  }

  // MARK: - Focus

  private func focusCard(_ worktreeID: Worktree.ID, states: [WorktreeTerminalState]) {
    let previousID = focusedWorktreeID
    focusedWorktreeID = worktreeID

    if let previousID, previousID != worktreeID,
      let previousState = states.first(where: { $0.worktreeID == previousID }),
      let previousSurface = previousState.activeSurfaceView
    {
      previousSurface.focusDidChange(false)
    }

    if let currentState = states.first(where: { $0.worktreeID == worktreeID }),
      let currentSurface = currentState.activeSurfaceView
    {
      currentSurface.focusDidChange(true)
      currentSurface.requestFocus()
    }
  }

  private func unfocusAll() {
    guard let previousID = focusedWorktreeID else { return }
    focusedWorktreeID = nil
    if let state = terminalManager.activeWorktreeStates.first(where: { $0.worktreeID == previousID }),
      let surface = state.activeSurfaceView
    {
      surface.focusDidChange(false)
    }
  }

  // MARK: - Occlusion

  private func activateDashboard() {
    // First occlude and unfocus ALL surfaces across all worktrees
    for state in terminalManager.activeWorktreeStates {
      state.setAllSurfacesOccluded()
    }
    // Then make dashboard surfaces visible (not focused until clicked)
    for state in terminalManager.activeWorktreeStates {
      state.activeSurfaceView?.setOcclusion(true)
    }
  }

  private func deactivateDashboard() {
    focusedWorktreeID = nil
    for state in terminalManager.activeWorktreeStates {
      state.activeSurfaceView?.setOcclusion(false)
      state.activeSurfaceView?.focusDidChange(false)
    }
  }
}

private struct ActiveResize {
  let edge: DashboardCardView.CardResizeEdge
  var translation: CGSize
}
