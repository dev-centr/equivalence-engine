# Walkthrough — ≡quivalence ≡ngine

The `equivalence-engine` binary is a multi-domain adaptation toolkit. It handles both **source code migrations** (version-to-version) and **filesystem equivalence mapping**, with a safety-first non-destructive default.

## 1. Safety First: Non-Destructive by Default

The engine now defaults to a **dry-run** mode. No files are modified unless explicitly requested.

```powershell
# This will only print what WOULD happen
equivalence-engine --path ./src --rules-dir ./rules/qt --from 5.15 --to 6.0
```

### Destructive/Output Options

- **`--in-place` (`-i`)**: Overwrite files in the source directory.
- **`--out-dir` (`-o`)**: Write transformed files to a separate directory (preferred for CI).

---

## 2. Domain: `code` (Default)

This is the original functionality of the engine, used for migrating between library/framework versions.

- Consolidates the functionality of the formerly separate `qt-upgrader`.
- Uses SDL rulesets to rename modules, move classes, and transform APIs.

```powershell
# Upgrade Qt5 to Qt6 in-place
equivalence-engine --path ./src --rules-dir ./rules/qt --from 5.15 --to 6.0 --in-place
```

---

## 3. Domain: `filesystem` (New)

A new intent-based mapping system for cross-distro path resolution.

- **Intent-based**: Query an abstract "intent" (e.g., `lib_dir`).
- **Context-aware**: Resolve for a specific distro/version.
- **Fallback Logic**: If `ubuntu-24.04` is missing a mapping, it automatically falls back to `ubuntu/default` or `debian/default`.

```powershell
# Resolve where libraries are on Ubuntu Jammy
equivalence-engine --domain filesystem --to linux/ubuntu/22.04 lib_dir
# Output: lib_dir -> /usr/lib/x86_64-linux-gnu
```

### Inheritance Metadata

Each context directory can contain a `context.sdl` file for UI-layer DAG visualization:

```sdl
name = "ubuntu"
inherits = ["debian"]
family = "linux"
```

---

## 4. Ecosystem Architecture

The Equivalence Adaptation Ecosystem is organized into three distinct tiers to separate logic, execution, and content:

1. **The Engine** ([`equivalence-engine`](https://github.com/dev-centr/equivalence-engine)):
   - **Role**: Core logic and binary.
   - **Responsibility**: Resolves shortest migration paths, parses SDL rules, and performs file transformations.
   - **Usage**: CLI tool for local development and base for CI.

2. **The Action** ([`equivalence-engine-action`](https://github.com/dev-centr/equivalence-engine-action)):
   - **Role**: CI/CD Wrapper.
   - **Responsibility**: Facilitates running the engine in GitHub Actions. Automates D-language setup and ruleset checkouts.
   - **Usage**: Included in `.github/workflows/*.yml`.

3. **Content Repositories** (e.g., [`equivalence-rules-code`](https://github.com/dev-centr/equivalence-rules-code)):
   - **Role**: Rule Definitions.
   - **Responsibility**: Contains the specific SDL files for a domain (Qt, Linux Filesystem, etc.).
   - **Usage**: Passed to the engine via `--rules-repo` or `--rules-dir`.

---

## 5. Consolidation Notice

The specialized `qt-upgrader` project is now obsolete as all its features have been absorbed into the core `equivalence-engine`. You can now use a single binary for migrations and equivalence tasks.

---

## 6. Design Evolution & Research

### Filesystem Equivalence Mapping
The expansion into filesystem mappings was researched to solve the "intent -> actual path" problem across fragmented Linux/UNIX families.

#### Key Architectural Decisions:
- **Linear migrations vs. DAG**: While distros form a taxonomy (Debian -> Ubuntu), the engine treats them as versioned rule sets in a specific domain.
- **Fallback Resolution**: Instead of complex inheritance, the engine uses a directory-based fallback (e.g., `ubuntu/22.04` -> `ubuntu/default` -> `debian/default`) to maintain simplicity and clarity.
- **Intent Vocabulary**: Abstract intents (like `log_dir`) are defined as schemas, while distros provide concrete implementations.

### Domain Generalization
The engine was generalized by introducing a **domain discriminator**. This allows the same traversal mechanism to handle both time-based code migrations and environment-based variation (distros), without increasing conceptual complexity.

---

## Verification Summary

I verified the following:

- [x] **Dry-run default**: Confirmed the engine does not modify files without `-i` or `-o`.
- [x] **Output Redirect**: Confirmed `--out-dir` correctly reconstructs the project tree in the target folder.
- [x] **Filesystem Fallback**: Confirmed `lib_dir` resolves correctly by walking up the distro hierarchy.
- [x] **Qt Migration**: Confirmed `PyQt5` -> `PyQt6` rules still apply correctly under the new architecture.
- [x] **Repository Cleanup**: Removed tracked `bin/`, redundant rules, and organized tests into a dedicated suite.
