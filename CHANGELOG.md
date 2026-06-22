# Changelog

## 2026.06.19

### What Changed
- Bumped `chwd` to upstream `1.21.1` (`pkgver=1.21.1`, `pkgrel` reset to `1`).
- Dropped the Kiro `[virtualbox]`/`[vmware]` vendor_id swap patch: upstream merged
  the fix in `1.21.1` (`profiles.toml` now ships `[virtualbox] = 80EE`,
  `[vmware] = 15AD` correctly), so the downstream sed + grep guards were not only
  redundant but would have failed the build (the guards grep for the old broken
  `15AD`/`80ee` state, which no longer exists).
- Kept the nvidia-open → DKMS patch: that `conditional_packages` block is byte-identical
  in `1.21.1`, still prefers per-kernel prebuilt `${kernel}-nvidia-open` modules from the
  cachyos repo, and still needs rewriting to a kernel-/repo-agnostic DKMS form.
- Added then removed `chwd/.nvchecker.toml`: settled on tracking upstream by **commit hash**
  (catches `profiles.toml` edits that land without a version/tag bump) rather than version,
  so the check became a `git ls-remote` comparison of our pinned tag's commit vs upstream
  `master` HEAD — which needs no nvchecker config. The drift check now lives as a read-only
  heartbeat in the `/kiro-start-session` and `/kiro-ready` skills (kept deliberately out of
  `1-build-all-packages.sh` and the ISO build / KIB). Hard patch breakage stays covered by
  the `prepare()` grep guards.

### Technical Details
- Verified by cloning both `1.21.0` and `1.21.1` tags and diffing
  `profiles/pci/graphic_drivers/profiles.toml`: the vendor_ids are fixed upstream; the
  nvidia-open `conditional_packages` snippet is unchanged, so the Fix #2 sed anchors
  (`^    modules=""$` … `^    echo "$modules"$`) still match.
- Trimmed `pkgdesc` to drop the virtualbox/vmware clause; rewrote the PKGBUILD header
  rationale to a one-line historical note and removed the entire Fix #1 block from
  `prepare()` while keeping the shared `local profiles=` line for Fix #2.

### Files Modified
- `chwd/PKGBUILD`
- `~/.claude/commands/kiro-start-session.md` (new step 11 — chwd upstream-drift heartbeat)
- `~/.claude/commands/kiro-ready.md` (new step 6b — chwd upstream drift, advisory)

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
