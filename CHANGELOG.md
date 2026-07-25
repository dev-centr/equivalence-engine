# Changelog

## [1.3.2] - 2026-04-10

### Added

- `libequivalence` is published at [github.com/dev-centr/libequivalence](https://github.com/dev-centr/libequivalence). The engine pins it with a **git commit hash** in `dub.sdl` (required by DUB 1.41+ for `repository` dependencies). Tags `v1.0.0` / `1.0.0` mark that revision for humans; bump the hash when you release a new library version.

### Changed

- Renamed branding and docs from Evolution Engine to **Equivalence Engine**; updated ecosystem links, release artifact names, Homebrew formula (`equivalence-engine`), and Winget identifier (`AMDphreak.EquivalenceEngine`). See [2026-04-10 - Rename to Equivalence Engine](changelog-details/2026-04-10%20-%20Rename%20to%20Equivalence%20Engine.md).

## [1.1.1] - 2026-03-27

### Changed

- Changed the "Publish Packages" job name to "Publish Winget Package" for clarity.
- See details in [2026-03-27 - Clarify Winget Publishing Job](changelog-details/2026-03-27%20-%20Clarify%20Winget%20Publishing%20Job.md).

## [1.1.0] - 2026-03-21

### Added

- Complete rewrite in D Lang for zero-bloat and high performance.
- Support for SDL rulesets (`rules/qt5_to_qt6.sdl`).
- GitHub Action updated to use DUB.

## [1.0.0] - 2026-03-21

### Added

- Initial Python implementation of `qt-upgrader`.
- JSON5 ruleset support.
- GitHub Action wrapper.
- Supporting common PyQt5/PyQt6 differences.
- CLI interface.
