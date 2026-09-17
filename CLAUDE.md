# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Third-party / AUR package builds for the `nemesis_repo` (Kiro Arch Linux distro). Each subdirectory is one package with its own `PKGBUILD` and `build.sh`. Built `.pkg.tar.zst` files land in `~/EDU/nemesis_repo/x86_64/`.

## Key scripts

| Script                         | Role                                                                                              |
|--------------------------------|---------------------------------------------------------------------------------------------------|
| `build.sh`                     | Shared per-package build template — copied into every package dir                                 |
| `1-build-all-packages.sh`      | Iterates all package dirs, runs each `build.sh`, then calls `~/EDU/nemesis_repo/up.sh` to publish |
| `copy-files-to-all-folders.sh` | Propagates the root `build.sh` to every package subdir (excludes `patches/`)                      |
| `packages.conf`                | Classifies every package `aur-fixed` / `aur-vcs` / `local` — data, sourced by the other scripts    |
| `aur-sync.sh`                  | Syncs each AUR package dir from its AUR git tree; re-applies Kiro patches from `patches/<pkg>/`    |
| `seed-build-state.sh`          | One-time bootstrap of `.build-state` from artifacts already in `nemesis_repo/x86_64/`             |
| `up.sh`                        | Git pull → optional `chaotic.sh`/`repo.sh` → commit + push                                        |
| `setup.sh`                     | One-time git remote configuration (`git@github.com-edu:erikdubois/<project>`)                     |

## Package classes (`packages.conf`)

Every package dir must be classified, or the sync aborts. The class decides what "needs a rebuild" means:

| Class | Rebuild signal |
|-------|----------------|
| `aur-fixed` | AUR `pkgver`/`pkgrel`/`epoch` changed |
| `aur-vcs`   | **upstream git HEAD moved** (`git ls-remote`) — the AUR pkgver is frozen for VCS packages and tells you nothing |
| `local`     | local `pkgver`/`pkgrel` changed (not on the AUR) |

`gnome-bluetooth` is `aur-fixed` despite a `git+` source because it pins `#commit=$_commit`.

## Per-package build flow (`build.sh`)

1. `bump_version` — only for `local` date-versioned packages (`pkgver` matches `^[0-9]{2}\.[0-9]{2}$`). AUR-backed packages have their version owned by the AUR and are never auto-bumped. Skipped entirely under `--check`.
2. `check_version` — compares against `.build-state` using the class signal above.
3. `build_package` — copies the package dir to `/tmp/tempbuild/`, builds with `makechrootpkg -c -r ~/Documents/chroot-archlinux`, then **overwrites** any same-named artifact in `~/EDU/nemesis_repo/x86_64/` (a VCS package can rebuild to an identical filename; refusing the copy would ship a stale binary while state recorded success).
4. `.build-state` is written **only after a successful build**, so a failure retries on the next run.

Flags: `--check` (report only, never mutates), `--no-chroot-update` (the full run updates the chroot once centrally).

## Kiro local deltas

Downstream patches are **explicit** `-p1` patches under `patches/<pkg>/`, re-applied after each sync. They are never inferred by diffing against the AUR: for a package that is merely stale, that diff *is* the staleness, and replaying it would revert the update just pulled in. Only `wlroots0.18` has one today.

## Version schemes

- **Date-versioned** (`pkgver=YY.MM`, e.g. `26.05`): auto-bumped on each run, but **only for `local`-class packages**. Used for in-house or static packages where the upstream version is irrelevant.
- **AUR-backed** (`aur-fixed` / `aur-vcs`): never auto-bumped and never hand-edited — `aur-sync.sh` pulls whatever the AUR currently ships. Edit these only via a patch in `patches/<pkg>/`, or the next sync silently reverts you.
- **Upstream-versioned `local`** (any other format): bump is skipped; pkgver/pkgrel are updated by hand when upstream releases.

## Adding a new package

1. Create a subdirectory named after the package.
2. Add its `PKGBUILD` (or let `aur-sync.sh` pull the whole tree from the AUR).
3. **Classify it in `packages.conf`** — an unclassified dir is a hard error, so this is not optional.
4. Run `./copy-files-to-all-folders.sh` to drop `build.sh` in.
5. Leave `.build-state` absent; the first run builds it and records state.

## Chroot location

`~/Documents/chroot-archlinux` — must be pre-created with `mkarchroot`. A full run updates it **once** via `arch-nspawn ... pacman -Syu` in `1-build-all-packages.sh`; a single-package `build.sh` run updates it itself unless given `--no-chroot-update`.

## Running builds

```bash
# Report what would rebuild and why — no builds, no push
bash 1-build-all-packages.sh --check

# Build a single package
cd <package-dir> && bash build.sh

# Build all packages and publish repo
bash 1-build-all-packages.sh

# Propagate shared build.sh to all package dirs
bash copy-files-to-all-folders.sh
```
