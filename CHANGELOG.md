# Changelog

## 2026.06.02

### What Changed
- Added new `kiro-arc-kde` package, replacing the old externally-built `edu-arc-kde`.
  Its build recipe was previously not on this box; it now lives here, sourced from
  our own fork `kirodubes/kiro-arc-kde` instead of the upstream AUR clone.
- Switched the package to the date-versioned scheme (`pkgver=26.06`, `pkgrel=01`)
  driven by `build.sh`'s auto-bump, dropping the AUR `pkgver()`/`git describe` logic.
- Wired `kiro-arc-kde` into the build flow (shared `build.sh`, `.previous-version`,
  regenerated `.SRCINFO`) and removed the raw AUR `kiro-arc-kde-git` clone.
- Updated the three build-critical package lists from `edu-arc-kde` to `kiro-arc-kde`
  (both ISOs + ATT). Built, published, and tested.

### Technical Details
- `source=("kiro-arc-kde::git+https://github.com/kirodubes/kiro-arc-kde.git")` — a plain
  git fetch of latest `master`; no `pkgver()` since the package is date-versioned.
- `conflicts` and `replaces` both list `edu-arc-kde arc-kde arc-kde-git kvantum-theme-arc`,
  so installed systems swap over on upgrade and the old names can't coexist.
- `prepare()` still strips `konversation/themes/papirus{,-dark}/src` (matched the fork's layout).
- Dropped the AUR `.git` and `epoch=2`; this is a fresh Kiro-named package, no upgrade path
  from the AUR `arc-kde-git` to preserve.

### Files Modified
- kiro-arc-kde/PKGBUILD (new, rewritten from the AUR clone)
- kiro-arc-kde/.SRCINFO (regenerated)
- kiro-arc-kde/build.sh, kiro-arc-kde/.previous-version (added)
- kiro-arc-kde-git/ (removed)
- ~/KIRO/kiro-iso/archiso/packages.x86_64 (edu-arc-kde → kiro-arc-kde)
- ~/KIRO/kiro-iso-next/archiso/packages.x86_64 (edu-arc-kde → kiro-arc-kde)
- ~/KIRO/archlinux-tweak-tool-gtk4/usr/share/archlinux-tweak-tool/data/nemesis_packages.txt (edu-arc-kde → kiro-arc-kde)
