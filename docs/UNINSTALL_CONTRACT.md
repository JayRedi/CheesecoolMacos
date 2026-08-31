# Uninstall Contract

`CheeseCool Uninstaller.app` is a separate native target. Phase 1 implements a confirmation shell, cleanup manifest, exact cleanup-path calculation, and mandatory dry-run preview. It performs no deletion.

The eventual cleanup boundary is manifest-driven plus these bundle-specific standard locations:

- `/Applications/CheeseCool.app`
- `~/Library/Application Support/CheeseCool`
- `~/Library/Caches/org.cheesecool.CheeseCool`
- `~/Library/Logs/CheeseCool`
- `~/Library/Preferences/org.cheesecool.CheeseCool.plist`
- `~/Library/Saved Application State/org.cheesecool.CheeseCool.savedState`
- CheeseCool-owned runtime diagnostics beneath Application Support
- the `org.cheesecool.CheeseCool` login-item registration

The manifest tracks only CheeseCool-owned resources. It never infers broad parent directories, uses wildcards, deletes arbitrary Library content, or mutates shell initialization files. Persistent shell environment variables created by CheeseCool are expected to remain exactly zero.

Any future destructive implementation and its tests must resolve exact manifest entries first. Tests must substitute a temporary sandbox root and must never target the development project or installed applications.
