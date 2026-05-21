# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Third-party / AUR package builds for the `nemesis_repo` (Kiro Arch Linux distro). Each subdirectory is one package with its own `PKGBUILD` and `build.sh`. Built `.pkg.tar.zst` files land in `~/EDU/nemesis_repo/x86_64/`.

## Key scripts

| Script                         | Role                                                                                              |
|--------------------------------|---------------------------------------------------------------------------------------------------|
| `build.sh`                     | Shared per-package build template — copied into every package dir                                 |
| `1-build-all-packages.sh`      | Iterates all package dirs, runs each `build.sh`, then calls `~/EDU/nemesis_repo/up.sh` to publish |
| `copy-files-to-all-folders.sh` | Propagates the root `build.sh` to every package subdir that already has one                       |
| `up.sh`                        | Git pull → optional `chaotic.sh`/`repo.sh` → commit + push                                        |
| `setup.sh`                     | One-time git remote configuration (`git@github.com-edu:erikdubois/<project>`)                     |

## Per-package build flow (`build.sh`)

1. `git_pull_if_repo` — pulls if the package dir is itself a git repo
2. `bump_version` — only for date-versioned packages (`pkgver` matches `^[0-9]{2}\.[0-9]{2}$`); sets `pkgver=YY.MM`, increments `pkgrel` (resets to `01` on month change)
3. `create_current_version` / `check_version` — compares against `.previous-version`; skips build if nothing changed
4. `build_package` — copies package dir to `/tmp/tempbuild/`, then:
   - Default (CHOICE=1): `makechrootpkg -c -r ~/Documents/chroot-archlinux`
   - Override (CHOICE=2, add pkgname to `makepkglist`): `makepkg -s`
   - On success: copies `*.pkg.tar.zst` to `~/EDU/nemesis_repo/x86_64/`; flags packages with >2 files in dest to `/tmp/installed`
5. Copies `.current-version` → `.previous-version`

## Version schemes

- **Date-versioned** (`pkgver=YY.MM`, e.g. `26.05`): build.sh auto-bumps on each run. Used for in-house or static packages where upstream version is irrelevant.
- **Upstream-versioned** (any other format): bump step is skipped; pkgver/pkgrel must be updated manually in PKGBUILD when upstream releases.

## Adding a new package

1. Create a subdirectory named after the package.
2. Add `PKGBUILD` and `.previous-version` (copy from an existing package and zero the versions).
3. Copy `build.sh` from the root into the new dir, or run `./copy-files-to-all-folders.sh` to propagate it automatically.
4. Optionally add `.nvchecker.toml` for upstream version checking.

## Chroot location

`~/Documents/chroot-archlinux` — must be pre-created with `mkarchroot`. The build script updates it via `arch-nspawn ... pacman -Syu` before each build.

## Running builds

```bash
# Build a single package
cd <package-dir> && bash build.sh

# Build all packages and publish repo
bash 1-build-all-packages.sh

# Propagate shared build.sh to all package dirs
bash copy-files-to-all-folders.sh
```
