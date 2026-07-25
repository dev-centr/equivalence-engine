# [2026-04-10] - Rename to Equivalence Engine

The project and binary were renamed from **Evolution Engine** to **Equivalence Engine** to match the `equivalence-engine` DUB package and the GitHub repository `dev-centr/equivalence-engine`.

## Documentation and packaging
- README, walkthrough, and changelog detail files now use Equivalence naming and updated repository links.
- Release artifacts use the `equivalence-engine-*` filename prefix (aligned with `dub.sdl` `targetPath` output).
- Homebrew formula name is `equivalence-engine`; Winget identifier is `AMDphreak.EquivalenceEngine`.

## Related repositories
Ecosystem docs and default URLs now point to `equivalence-engine-action`, `equivalence-rules-code`, and `equivalence-rules-filesystem`.

## Operational note
If you use Winget or Homebrew, migrate installs to the new names when you cut the next release. The first Winget publish under `AMDphreak.EquivalenceEngine` may require an initial manifest submission to [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) if the new identifier is not yet listed.
