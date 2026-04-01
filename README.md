# Prowl

A native command center for terminal-based coding agents.  
This repository is a fork of [Supacode](https://github.com/supabitapp/supacode), with onevcat-specific customizations.

## Features

- Multi-repository and worktree oriented terminal workflow
- Built-in Ghostty-based terminal experience
- Canvas / parallel session workflow support
- Remote WebView integration for external terminal dashboards

## Remote H5 Embedding

Prowl supports embedding remote H5 pages directly in the right-side detail pane (WebView), including web terminals.

For example, you can embed:

- [mini-terminal (web terminal)](https://github.com/tyrad/mini-terminal)

Typical remote URL format:

```text
https://your-domain.example.com:9444/mini-terminal/
```

Current remote toolbar supports:

- Keep Alive (persist WebView when switching items)
- Force Refresh
- Open in Browser
- Centered status/time hint and notification bell

Authentication can be handled by the H5 page itself (for example via your own login flow or gateway strategy).

## Technical Stack

- [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
- [libghostty](https://github.com/ghostty-org/ghostty)

## Requirements

- macOS 26.0+
- [mise](https://mise.jdx.dev/) (for dependencies)

## Building

```bash
make build-ghostty-xcframework   # Build GhosttyKit from Zig source
make build-app                   # Build macOS app (Debug)
make run-app                     # Build and launch
```

## Development

```bash
make check     # Run swiftformat and swiftlint
make test      # Run tests
make format    # Run swift-format
```

## Recent Fork Updates

- Remote mini-terminal integration moved controls from in-page bar to the macOS window toolbar
- Restored centered toolbar status area (time hint) and notification bell for remote views
- Moved remote actions to the right side of toolbar: Keep Alive, Force Refresh, Open in Browser
- Reduced Keep Alive switch visual size for a cleaner toolbar layout
- Improved remote WebView behavior: endpoint switching, keep-alive reload policy, delegate rebinding for cached views, shared/persistent auth credentials, and resource caching

## Contributing

- A clear issue describing your feature/bug is preferred over a vibe-coded PR
- Every line will be reviewed and low-quality changes may be rejected
