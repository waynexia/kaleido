# Repository conventions

- Build a native macOS application with Swift and AppKit; keep deterministic behavior in `KaleidoCore`.
- The current scope is recorded in `docs/behavior-baseline.md`. Distinguish observed settings, implemented behavior, and verified behavior.
- Product UI contains window information, controls, and actionable runtime status only. Keep task descriptions and implementation goals in documentation.
- Do not collect or persist real window titles, usage history, screenshots, or full machine preference exports.
- Keep AX calls off the main thread and out of the keyboard event tap. Centralize platform compatibility code in `Accessibility.swift`.
- Never silently change another window manager's preferences or user-granted system permissions.
- Run `make check` for code changes. Use `scripts/preview.sh` for visual changes and disposable fixture windows for destructive action tests.
- Update documentation when behavior, permissions, build commands, or limitations change.
- Make small, coherent commits with descriptive Conventional Commit messages. Do not commit build output or generated previews.
