import SwiftUI

struct WindowCommands: Commands {
  let ghosttyShortcuts: GhosttyShortcutManager
  @FocusedValue(\.closeSurfaceAction) private var closeSurfaceAction
  @FocusedValue(\.selectPreviousTerminalTabAction) private var selectPreviousTerminalTabAction
  @FocusedValue(\.selectNextTerminalTabAction) private var selectNextTerminalTabAction

  var body: some Commands {
    let closeSurfaceHotkey = ghosttyShortcuts.keyboardShortcut(for: "close_surface")
    let isCloseSurfaceOverlapping = closeSurfaceHotkey?.key == "w" && closeSurfaceHotkey?.modifiers == .command

    CommandGroup(replacing: .saveItem) {
      Button("Close Window", systemImage: "xmark") {
        NSApplication.shared.keyWindow?.performClose(nil)
      }
      .modifier(
        KeyboardShortcutModifier(
          shortcut: !isCloseSurfaceOverlapping || closeSurfaceAction == nil ? .init("w") : nil
        )
      )
    }

    CommandGroup(after: .windowSize) {
      Divider()
      Button("Select Previous Tab") {
        selectPreviousTerminalTabAction?()
      }
      .modifier(
        KeyboardShortcutModifier(shortcut: ghosttyShortcuts.keyboardShortcut(for: "previous_tab"))
      )
      .disabled(selectPreviousTerminalTabAction == nil)

      Button("Select Next Tab") {
        selectNextTerminalTabAction?()
      }
      .modifier(
        KeyboardShortcutModifier(shortcut: ghosttyShortcuts.keyboardShortcut(for: "next_tab"))
      )
      .disabled(selectNextTerminalTabAction == nil)
    }
  }
}

struct KeyboardShortcutModifier: ViewModifier {
  let shortcut: KeyboardShortcut?

  func body(content: Content) -> some View {
    if let shortcut {
      content.keyboardShortcut(shortcut)
    } else {
      content
    }
  }
}

private struct SelectPreviousTerminalTabActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectPreviousTerminalTabAction: (() -> Void)? {
    get { self[SelectPreviousTerminalTabActionKey.self] }
    set { self[SelectPreviousTerminalTabActionKey.self] = newValue }
  }
}

private struct SelectNextTerminalTabActionKey: FocusedValueKey {
  typealias Value = () -> Void
}

extension FocusedValues {
  var selectNextTerminalTabAction: (() -> Void)? {
    get { self[SelectNextTerminalTabActionKey.self] }
    set { self[SelectNextTerminalTabActionKey.self] = newValue }
  }
}
