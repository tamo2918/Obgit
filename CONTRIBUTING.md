# Contributing to Obgit

Thank you for your interest in contributing!

---

## Reporting Bugs

Open an issue using the **Bug Report** template at [GitHub Issues](../../issues/new/choose) and include:

- iOS version and device model (e.g. iPhone 16 Pro, iOS 18.3)
- Steps to reproduce
- Expected behaviour vs. actual behaviour
- Error message or crash log if available (Settings → Privacy & Security → Analytics & Improvements → Analytics Data)

## Requesting Features

Open an issue using the **Feature Request** template. Describe the use-case — what problem it solves and who benefits.

## Submitting a Pull Request

1. Fork the repository.
2. Create a feature branch from `main`:
   ```
   git checkout -b feat/short-description
   ```
3. Make your changes (see [Code Guidelines](#code-guidelines) below).
4. Build and test on a **physical device** (see [Build Requirements](#build-requirements)).
5. Open a PR targeting `main` with a clear description of what changed and why.

> Small, focused PRs are easier to review. Split large changes into multiple PRs when possible.

---

## Build Requirements

| Tool | Version |
|------|---------|
| Xcode | 26.0+ |
| iOS deployment target | 18.0+ |
| Swift | 6 (strict concurrency) |

> **Important — Simulator limitation:**
> `Clibgit2.xcframework` ships device-arm64 slices only.
> Build for a connected iPhone or iPad when testing any Git operation (clone, pull, commit, push, branch switch).
> Non-Git UI changes can be prototyped in Simulator.

### Dependencies (resolved automatically by Xcode)

| Package | Branch | Purpose |
|---------|--------|---------|
| [light-tech/SwiftGit2](https://github.com/light-tech/SwiftGit2) | `spm` | HTTPS `git clone` |
| [light-tech/Clibgit2](https://github.com/light-tech/Clibgit2) | `master` | `git fetch` / `git merge` / `git push` / SSH clone (C API) |
| [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | `main` | Markdown rendering |

---

## Architecture Overview

```
Obgit/
├── Models/
│   ├── RepositoryModel.swift          # Repository metadata (persisted in UserDefaults)
│   ├── VaultFileNode.swift            # File-tree node + recursive builder
│   ├── CommitEntry.swift              # Commit history entry
│   ├── DiffModels.swift               # Diff display models (DiffLineKind, DiffHunk, FileDiff)
│   └── ConflictFile.swift             # Merge conflict model + section-level resolution
├── Services/
│   ├── GitService.swift               # All Git operations via libgit2 C API (~1200 lines)
│   ├── GitError.swift                 # Typed Git error enum (24 cases) with localized messages
│   ├── KeychainService.swift          # PAT / SSH key / passphrase storage (iOS Keychain)
│   ├── DiffEngine.swift               # Myers O(ND) diff algorithm (pure Swift, nonisolated)
│   ├── MarkdownProcessor.swift        # YAML frontmatter stripper + [[WikiLink]] converter
│   └── CommitMessageGenerator.swift   # Apple Intelligence commit message generation (iOS 26+)
├── Stores/
│   └── RepositoryStore.swift          # CRUD + UserDefaults persistence for repositories
├── ViewModels/
│   ├── CloneRepositoryViewModel.swift # Clone screen state + clone execution
│   ├── VaultWorkspaceViewModel.swift  # Workspace state: file tree, viewer, pull, edit, commit
│   ├── RepositoryDetailViewModel.swift# Repository detail / settings management
│   ├── RepositoryListViewModel.swift  # Repository list
│   └── SearchViewModel.swift          # Full-text search (280 ms debounce, background thread)
└── Views/
    ├── VaultHomeView.swift            # Root view + Clone screen + Workspace shell + sidebar
    ├── CommitDialogView.swift         # Commit & push sheet (AI message generation)
    ├── ConflictResolutionSheet.swift  # Section-by-section merge conflict resolution UI
    ├── DiffSheet.swift                # Unified diff viewer
    ├── BranchSwitchSheet.swift        # Remote branch list + switch
    ├── CommitHistorySheet.swift       # Commit log viewer
    ├── SearchView.swift               # Full-text search sheet
    └── ObgitLiquidStyle.swift         # Design system (color palette, shared styles)
```

---

## Key Design Decisions

| Area | Decision | Reason |
|------|----------|--------|
| Git library | `SwiftGit2` for HTTPS clone; `Clibgit2` C API for everything else | SwiftGit2 cannot pass credentials during fetch/push and does not support SSH; C API gives full control |
| SSH clone | `git_clone()` via Clibgit2 C API with `gitCredentialCallback` | SwiftGit2 wraps clone but cannot inject SSH credentials |
| Pull strategy | `git_merge_analysis` → UP_TO_DATE / FASTFORWARD / NORMAL branching | Mirrors standard Git behaviour; conflicts surface cleanly as `GitError.mergeConflicts` |
| Merge conflict resolution | `ConflictFile` parses conflict markers into typed sections; UI lets users pick ours/theirs per section | Avoids raw text editing; keeps the resolution model independent of the View layer |
| SSH credential callback | `@convention(c)` file-scope closure + `Unmanaged<CredentialContext>` | Required by libgit2's C callback contract; Unmanaged prevents ARC from releasing the context |
| Concurrency | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; Git ops on `DispatchQueue.global` via `withCheckedThrowingContinuation` | Keeps Swift 6 strict concurrency clean without scattering `@MainActor` everywhere |
| DiffEngine | Pure-Swift Myers O(ND) implementation, fully `nonisolated` | Runnable on any thread; no dependency on the UI layer |
| Security | PAT and SSH keys stored in Keychain (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) | Never persisted in UserDefaults or on disk |
| Markdown processing | Frontmatter stripped + `[[WikiLink]]` converted before MarkdownUI renders | Keeps MarkdownUI stateless; processing is a pure string transform |
| Commit message AI | `SystemLanguageModel` (Apple Intelligence) with 10-template fallback | Gracefully degrades on devices or OS versions that do not support Apple Intelligence |

---

## Code Guidelines

- **Language:** Swift 6, strict concurrency enforced by the project settings (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- **Architecture:** MVVM. Views own no business logic; ViewModels own no UIKit types.
- **Concurrency:** Mark functions `nonisolated` when they do not touch the UI. Run blocking Git ops on `DispatchQueue.global` and resume on the main actor via `withCheckedThrowingContinuation`.
- **No new dependencies** without prior discussion in an issue.
- **UI strings:** Japanese (the primary target audience). English is acceptable in code comments and commit messages.
- **No force-unwraps** (`!`) in production paths. Use `guard let` or `if let`.
- **C API memory management:** Always pair `git_*_free()` calls with `defer` to prevent leaks. Use `Unmanaged<T>` for objects passed through C callbacks.
- **Tests:** The project has no automated test suite. Manual testing on a physical device is required for any Git operation.

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
