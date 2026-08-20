# Changelog

## 2026.07.23

### What Changed
- Bumped `chwd` from the pinned `1.22.1` to upstream `1.23.0` (`pkgrel` stays `1`).
  Triggered by the `/kiro-start-session` upstream-drift heartbeat, which reported
  "UPSTREAM MOVED". The report was misleading: master HEAD (`e99ec339`) *is* tag
  `1.24.1`, so there was no unreleased drift — the pin was simply three tags behind.
- **1.24.x is knowingly skipped, not pending.** Upstream `1.24.0` ported
  `scripts/chwd-kernel` to a hand-declared FFI on `alpm_pkg_get_installed_db()`, a libalpm
  symbol that does not exist in Arch's `libalpm.so.16` (checked on this box and in
  `~/Documents/chroot-archlinux`, both `pacman 7.1.0.r9`). A `1.24.1` build fails at link
  time with `ld.lld: error: undefined symbol: alpm_pkg_get_installed_db`. Upstream evidently
  builds against a patched pacman. Recorded as a comment in the PKGBUILD header so the next
  drift alert on 1.24.x reads as expected, not as a to-do.
- Catch-up note: the previous pin `1.22.1` was never built or published. The repo and
  this box both still carry `chwd-1.22.0-1`, and no CHANGELOG entry exists for 1.22.0
  or 1.22.1 (last chwd entry was 1.21.1). The `1.23.0` build supersedes both.
- Kept the nvidia-open → DKMS patch unchanged: `profiles/pci/graphic_drivers/profiles.toml`
  is byte-identical across `1.22.0..1.24.1`, so all three `prepare()` grep guards still match.

### Technical Details
- Real gain in this bump is upstream #260: `scripts/chwd`'s `pacman_handle` now shell-quotes
  every argument (`pacman` became a table instead of a concatenated string). Our injected
  `conditional_packages` snippet emits bare package names one per line, so it still passes
  cleanly through the new `split` + `shell_quote` path. Rest is clippy/rustfmt passes,
  Bulgarian i18n, and dependency churn. No new system dependencies — the `depends` array
  (pciutils, libusb, lua, pacman) is unchanged.
- The 1.24.1 `board_name` panic fix (#264) is **not** a reason to chase 1.24.x. The
  `.expect()` on `/sys/devices/virtual/dmi/id/board_name` only executes for profiles that
  carry a `board_name_pattern` key — and that key was *introduced* in 1.24.0, where
  `[handheld.rog-ally]` and `[handheld.msi-claw]` set `hwd_product_name_pattern = '.*'` and
  filter on board_name instead. So 1.24.0 is what would expose every machine (VMs included,
  where the DMI file is absent) to the panic; 1.24.1 only repairs its own regression.
  At 1.22.x/1.23.0 no profile has the key, the read never runs, and we are not exposed.
- Out-of-band tag audit (required because our PKGBUILD drops the `?signed` source qualifier):
  the `1.23.0` tag is GPG-signed by issuer fingerprint
  `B1B70BB1CD56047DEF31DE2EB62C3D10C54D5DA9` — the same key upstream pins in `validpgpkeys`.

### Files Modified
- `chwd/PKGBUILD`

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
