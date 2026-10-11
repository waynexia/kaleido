# Repository conventions

- Build a native macOS application with Swift and AppKit; keep deterministic behavior in `KaleidoCore`.
- Read [README.md](README.md) for commands, [behavior-baseline.md](docs/behavior-baseline.md) for scope, [architecture.md](docs/architecture.md) for implementation boundaries, [code-signing.md](docs/code-signing.md) for signing, and [validation.md](docs/validation.md) for completed and pending checks. Distinguish observed reference settings, implemented behavior, and verified behavior.
- Product UI contains window information, controls, and actionable runtime status only. Keep task descriptions and implementation goals in documentation.
- Do not collect or persist real window titles, usage history, screenshots, or full machine preference exports.
- Keep AX calls off the main thread and out of the keyboard event tap. Centralize platform compatibility code in `Accessibility.swift`.
- Never silently change another window manager's preferences or user-granted system permissions.
- Preserve the bundle ID `dev.waynexia.Kaleido`, the existing signing certificate, and the authorized installation path. Reuse `Kaleido Local Development` by default; do not recreate its key, fall back to ad-hoc signing, or weaken the designated requirement to avoid authorization prompts. Ad-hoc signing is an explicit opt-in for disposable CI/preview builds only; never overwrite the authorized everyday build with it.
- Keep AltTab running during coexistence validation and use Control + Option + K / J for Kaleido. A fresh install defaults to the standard shortcut profile; preserve the user's saved profile and menu-bar visibility. The menu-bar icon defaults to visible and opens settings directly.
- Run `make check` for code or build-script changes; it rebuilds `build/Kaleido.app` and checks signing continuity. Quit Kaleido before replacing its bundle, then relaunch through LaunchServices when validating runtime behavior. Do not treat a shell-launched `--diagnose` result as the running app's permission state.
- Use `scripts/preview.sh` for visual changes. The Debug-only global integration driver changes system focus and sends keys: run it only within the user's authorized test scope, target destructive actions exclusively at Window Fixture, and preserve AltTab. Detailed prerequisites and commands are in the validation record.
- Documentation-only changes need link/path and `git diff --check` validation; they do not require rebuilding or driving the desktop. Preserve pending checks as pending unless new evidence verifies them.
- Update documentation when behavior, permissions, build commands, or limitations change.
- Make small, coherent commits with descriptive Conventional Commit messages. Do not commit build output, generated previews, certificates, private keys, or signing credentials.
