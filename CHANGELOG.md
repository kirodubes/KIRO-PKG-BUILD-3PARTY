# Changelog

## 2026.09.18

### What Changed

- **Added `cpuid` to this repo.** Todd Allen's x86 CPUID dumper. An artifact
  (`cpuid-20260220-1`) was already sitting in `nemesis_repo/x86_64/`, but no source directory
  for it existed anywhere on the box — it had been built outside this flow and was four months
  stale against the AUR's `20260503-1`. It is now a first-class package dir here, so the normal
  sync/check/rebuild cycle keeps it current.

### Technical Details
- Class `aur-fixed`: `source=` is a plain `http://www.etallen.com/...src.tar.gz` tarball with a
  `sha256sums` pin — no `git+` line, so the AUR `pkgver` is the honest rebuild signal and no
  `PKG_UPSTREAM` entry is needed.
- The tree was pulled into `~/.cache/kiro-aur/cpuid` and rsynced in exactly as `aur-sync.sh`
  does it, so the cache is already warm and consistent for the next sync.
- `.build-state` deliberately left absent rather than seeded to the stale `20260220-1`: this repo
  has never built cpuid, and a plausible-but-false state file is worse than none — absent means
  "needs build", which is exactly true. `1-build-all-packages.sh --check` confirms:
  `cpuid: REBUILD NEEDED (version <none>-<none> -> 20260503-1)`.
- The new build will land as `cpuid-20260503-1-x86_64.pkg.tar.zst`, a **different filename** from
  the stale `20260220-1` artifact, so `build_package`'s overwrite does not replace it.
  `repo.sh` re-adds every file in `x86_64/`, leaving the superseded package orphaned in the repo
  and in git. It needs removing by hand, but only **after** a green build — deleting first would
  leave the repo with no cpuid at all if the build fails.
- **Not built in this session.** `build.sh` gets as far as the chroot update and stops there:
  `arch-nspawn`/`makechrootpkg` need interactive sudo, which a non-interactive run cannot answer.
  The package dir is complete and `--check` reports it correctly; the build itself is pending.

### Files Modified
- `packages.conf` — classified `cpuid` as `aur-fixed`
- `cpuid/PKGBUILD`, `cpuid/.SRCINFO` — new, synced from the AUR
- `cpuid/build.sh` — dropped in by `copy-files-to-all-folders.sh`
- `CHANGELOG.md`

## 2026.09.17

### What Changed

- **Rebuild detection now reads upstream instead of the local PKGBUILD.** The old flow compared
  the PKGBUILD literals against `.previous-version` — a local file-vs-file diff that only ever
  detects edits made by hand. Consequences: `lastpass` sat four releases behind (4.147.2 vs
  4.151.5), `pamac-aur` one (11.7.4-3 vs 11.7.5-1), `sway-scroll` six (1.12.15 vs 1.12.21), and
  **no `-git` package had rebuilt on an upstream push, ever**.
- **The `-git` packages were the real hole.** `makepkg`'s `pkgver()` rewrites the version in the
  `/tmp/tempbuild` copy, never in the source dir, so the literal being compared is frozen
  permanently. Evidence: `noctalia-git`'s PKGBUILD says `r1191` while the shipped artifact is
  `r4258` — that build only happened via an accidental manual `pkgrel` bump. The AUR's own
  `pkgver` is no help either, because it is frozen for VCS packages too; **the upstream git push
  is the only honest signal**, read live with `git ls-remote`.
- **New AUR sync.** `aur-sync.sh` clones each AUR repo into `~/.cache/kiro-aur/<pkg>` and rsyncs
  the whole tree into the package dir, so companion files (`.install` scripts, pacman hooks,
  `.json`, patches) travel with the PKGBUILD instead of drifting.
- **Chroot updated once per run, not once per package** — was eighteen `arch-nspawn pacman -Syu`
  calls per full run.
- **`--check` mode** on `1-build-all-packages.sh`: sync, report what would rebuild and why, then
  stop without building and **without calling `up.sh`**, which commits and pushes the live repo.

- **Adopted `mir`, `miracle-wm-git` and `wasmedge` from KIRO-PKG-BUILD-APPS.** All three are AUR
  clones and had no business in the APPS repo: they carry upstream versions rather than its `YY.MM`
  scheme, each held its own nested `.git` pointing at `aur.archlinux.org`, and they were the only
  three dirs there without a `build.sh` — so every APPS batch run listed them in its failure summary
  as `(no build script)`. This repo already models exactly what they need.

### Technical Details
- `packages.conf` classifies every package as `aur-fixed`, `aur-vcs` or `local`; a directory on
  disk that is absent from it is a **hard error**, so a new folder cannot slip through unnoticed.
  `gnome-bluetooth` is `aur-fixed` despite its `git+` source because it pins `#commit=$_commit`.
- **Kiro deltas are declared, never inferred.** An earlier draft auto-detected the local delta by
  diffing the package dir against the AUR tree; that is wrong, because for a package that is
  merely *stale* the diff **is** the staleness, and replaying it would revert the update that was
  just pulled in. Deltas now live as explicit `-p1` patches under `patches/<pkg>/`, re-applied
  after each rsync. Only `wlroots0.18` has one (`-D werror=false`). Verified: after a full sync
  its PKGBUILD is byte-identical to before, so the delta round-trips cleanly.
- `.previous-version`/`.current-version` are replaced by one `.build-state` per package holding
  `pkgver`/`pkgrel`/`epoch`/`upstream_commit`. It is written **only after a successful build**, so
  a failed build retries next run rather than being recorded as done. The old files were also
  quietly broken: `chwd`'s had captured a comment line (`pkgrel=# pkgrel: bump on every…`),
  `flameshot-git`'s had an empty `pkgrel=`, and `sway-scroll`/`tinty-git` had none — all four
  forced a needless rebuild on every single run.
- `seed-build-state.sh` bootstraps the state from the artifacts already in `nemesis_repo/x86_64/`,
  matching a `-git` package's `.g<sha>` suffix against upstream HEAD. Without it the first run had
  nothing to compare against and would have rebuilt all eighteen packages — the exact blind
  rebuilding this change exists to stop. Artifacts are matched on the trailing `-pkgrel-arch`
  shape rather than on the version, whose first character varies (`1.2`, `r2230`, `v1.0.1`, `1:140`).
- **Five orphaned gitlinks removed.** `noctalia-git`, `sway-scroll`, `tinty-git`, `wlroots0.18` and
  `dracula-colors-xfce4-terminal` were recorded as mode `160000` with **no `.gitmodules`**, so a
  fresh clone of this repo produced empty directories. All are now plain tracked files;
  `dracula-colors-xfce4-terminal` was a gitlink to a package that does not exist and is gone.
- A committed `makepkg` srcdir checkout (a bare clone under `gnome-bluetooth/gnome-bluetooth/`,
  24 files) is removed — it is regenerated at build time.
- `sway-scroll` had no `build.sh` at all, so it was skipped every run and logged to `/tmp/failed`.
  `copy-files-to-all-folders.sh` already copied to every subdirectory, so it simply had never been
  re-run since that package was added; it now also excludes `patches/`.
- `.nvchecker.toml` dropped from `arc-gtk-theme`, `gnome-bluetooth` and `sway-scroll` — redundant
  once versions come from the AUR, and no `local`-class package had one, so nvchecker leaves the repo.
- `--check` does not run `bump_version`, so a report-only run can never mutate a PKGBUILD.
- The artifact copy **overwrites** instead of `cp -n`. A VCS package can legitimately rebuild to
  the same filename (`hardcode-fixer-git` carries a static `pkgver=2.0` placeholder), and refusing
  the copy there would leave the stale binary in `nemesis_repo` while `.build-state` recorded a
  successful build. A replacement is logged rather than silent.
- Dropped `.aur-commit`: it was written by the sync and read by nothing.
- **Failed builds now keep their logs.** `makepkg` writes logs into the build dir (`/tmp/tempbuild`),
  which the next package in a full run wipes — so a mid-run failure left nothing to diagnose, as
  happened with `opera-ffmpeg-codecs-bin`. The failure path now copies them to
  `/tmp/kiro-build-logs/<pkg>/` and `/tmp/failed` names that directory. The whole `makechrootpkg`
  session is tee'd as well, not just makepkg's own logs, because the failure can occur *before*
  makepkg starts (a sudo prompt with no tty, a chroot that will not sync) — in which case there is
  no makepkg log to preserve at all. Verified against a deliberately failing PKGBUILD: exit 1, logs
  kept, reason captured, and no `.build-state` written.

### Build run results (first real exercise of the new flow)

- **9 of 10 flagged packages built and published.** Each VCS artifact matched the commit the new
  check predicted: `ckb-next-git` r161.g833ab509, `flameshot-git` r2369.3458585e, `noctalia-git`
  r5554.g8c52cb71b, `tinty-git` r326.475079f. Fixed-version: `lastpass` 4.151.5, `pamac-aur`
  11.7.5, `sway-scroll` 1.12.21.
- `flameshot-git` was rebuilt again the same day to `r2370.89861c4a` after upstream pushed past
  the morning's `3458585e` — the drift rate that keeps `aur-vcs` advisory rather than a release gate.
- **`hardcode-fixer-git` rebuilt to the identical filename** `2.0-1` — its `pkgver()` fell back to
  the static placeholder rather than a commit-embedded version. This is the exact case the `cp -n`
  → overwrite change was made for: the old behaviour would have kept the stale binary in
  `nemesis_repo` while `.build-state` recorded a successful build.
- **`opera-ffmpeg-codecs-bin` failed and correctly wrote no `.build-state`**, so it stayed flagged
  for retry instead of being recorded as done — the failure guard working as designed. The package
  has since been removed from the repo entirely and dropped from `packages.conf` (17 packages now).
  Its build log was lost: on failure the log lives in `/tmp/tempbuild`, which the next package
  overwrites.

  `2.28.0` pinned via `#tag=v${pkgver}`, and a `0.17.0` release tarball), `miracle-wm-git` as
  `aur-vcs` with `PKG_UPSTREAM` pointing at `github.com/miracle-wm-org/miracle-wm.git`. Its
  `source=` pins no branch, so it takes the default `HEAD` and gets no `PKG_UPSTREAM_REF` entry.
- The nested `.git` in each was deleted: `aur-sync.sh` owns syncing from here on, cloning to
  `~/.cache/kiro-aur/<pkg>` and rsyncing in with `--delete`.
- `wasmedge` arrived with `pkg/` (mode `d--x--x--x`, unreadable), `src/` and a stale
  `wasmedge-0.17.0.tar.gz` left over from an old local `makepkg` — 21M of debris that would have
  broken `build.sh`'s `cp -r "${SCRIPT_DIR}/"*` on the unreadable directory. Removed; the dir is
  now 224K.
- `build.sh` distributed via `copy-files-to-all-folders.sh`; all 21 copies verified byte-identical
  to the root template.
- `seed-build-state.sh` seeded `mir` as already built (`2.28.0-1` is in `nemesis_repo`) and left
  `miracle-wm-git` and `wasmedge` unseeded, so both rebuild on the next run.
- A note was added recording that `mir` is a build dependency of `miracle-wm-git`. `find | sort`
  orders them correctly, but `up.sh` regenerates the repo DB only at the *end* of a run, so a run
  that rebuilds both from scratch needs a second pass. Not an issue today — `mir 2.28.0-1` is
  already published.
- `--check` verified: 20 packages, none unclassified, `miracle-wm-git` (upstream `..8629b1a`) and
  `wasmedge` flagged for rebuild.
- **The first `aur-sync.sh` pass silently dropped a Kiro local delta from `miracle-wm-git`.** Its
  `build()` had symlinked a private `wasmedge/` include dir and passed `-DWASMEDGE_INCLUDE_DIR`,
  because `wasmedge-bin` ships headers flat in `/usr/include` with no `wasmedge/` subdir while
  miracle-wm does `#include <wasmedge/wasmedge.h>`. The rsync runs with `--delete`, so it went —
  the exact failure `packages.conf` already guards against for `wlroots0.18`, which `miracle-wm-git`
  had no note for. Keeping it dropped is correct now that this repo builds `wasmedge` from source
  (the AUR recipe's `depends=(wasmedge)` is then satisfied by a package with a normal header
  layout), so the note added to `packages.conf` records that the delta must **not** be re-added, and
  what to do if `wasmedge-bin` ever comes back. Recoverable from commit `a870254` either way.
- The same sync added `gtk4` and `gtk4-layer-shell` to miracle's `depends` — a genuine upstream
  change, not a local edit.

### Files Modified
- `packages.conf` (new), `aur-sync.sh` (new), `seed-build-state.sh` (new)
- `patches/wlroots0.18/0001-kiro-werror-false.patch` (new)
- `build.sh`, `1-build-all-packages.sh`, `copy-files-to-all-folders.sh`
- `build.sh` re-propagated to all 20 package dirs
- Removed: all `.current-version`/`.previous-version`, three `.nvchecker.toml`,
  `gnome-bluetooth/gnome-bluetooth/`, `dracula-colors-xfce4-terminal`
- Adopted: `mir/`, `miracle-wm-git/`, `wasmedge/`

## 2026.09.14

### What Changed
- **Back-ported upstream chwd `86a0dbd` into the pinned 1.23.0 build** (`chwd/PKGBUILD`,
  `pkgrel` 1 → 2). Upstream's "profiles: match NVIDIA PRIME profiles on convertibles" adds
  chassis type **31** to the laptop allowlist of the three NVIDIA PRIME profiles (open, 580xx,
  470xx). Without it a hybrid 2-in-1 matches the *desktop* profile and boots to a blank
  Plymouth/LUKS screen — Kiro ships both Plymouth and LUKS, so the failure mode is ours. It is
  latent rather than universal: Kiro only runs chwd on the `driver=nonfreechwd` boot-menu path.
- Taken as a **patch, not a pin bump.** `86a0dbd` sits past `1.24.0`, which is knowingly skipped
  because its `chwd-kernel` port hand-declares an FFI on `alpm_pkg_get_installed_db()` that does
  not exist in Arch's `libalpm.so.16`. Nothing in the eleven commits between `1.23.0` and master
  fixes that, so the pin stays.
- **Deliberately not back-ported: `6270759`** ("gracefully handle missing board_name DMI file",
  which prevents a fatal panic in QEMU/Proxmox VMs). The `.expect()` it repairs was introduced by
  `197a679`, which is itself inside `1.23.0..master` — 1.23.0 predates the bug, so this is a fix
  for a regression we do not carry.

### Technical Details
- The back-port is a third assert-sed-assert block in `prepare()`, after the existing nvidia-open
  DKMS rewrite. It anchors on `chassis_types = "8 9 10 11"` (three occurrences at 1.23.0, lines
  61/133/179) and asserts exactly 3 replacements afterwards, so a stale anchor fails the build
  rather than silently shipping an unpatched profile — same guard style as the nvidia-open patch.
  The two patches use disjoint anchors (the nvidia one rewrites the `modules=""` … `echo
  "$modules"` range), verified to coexist on the real 1.23.0 file.
- Kept **byte-identical to upstream** (`31` appended, nothing else) so the divergence stays
  trivial to re-check on the next pin bump; the resulting `chassis_types` lines diff clean against
  `86a0dbd`.
- `pkgrel` bump is load-bearing, not cosmetic: same `pkgver`+`pkgrel` with different binary content
  makes pacman clients reuse the stale `.pkg.tar.zst` by filename and report
  "invalid or corrupted package (checksum)".
- Verify after building by **extraction, not version**:
  `bsdtar -xOf chwd-1.23.0-2-x86_64.pkg.tar.zst profiles/pci/graphic_drivers/profiles.toml | grep -c 'chassis_types = "8 9 10 11 31"'` must return `3`.

### Files Modified
- `chwd/PKGBUILD`

## 2026.09.05

### What Changed
- **Added `wlroots0.18` (0.18.3-1), packaged from the AUR.** `kiro-dwl` stopped building:
  Arch dropped **both** `wlroots0.18` and `wlroots0.19` from `[extra]`, which now ships only
  `wlroots0.20`. dwl's `config.mk` resolves wlroots through pkg-config with the version in the
  *module name* (`wlroots-0.18.pc`), so a newer wlroots can never satisfy it — and upstream dwl,
  including the `main` branch, still pins `wlroots-0.19`. There is therefore no dwl release that
  builds against anything Arch currently ships.
- Chose to keep `kiro-dwl` on dwl 0.7 + `wlroots0.18` rather than follow the AUR `dwl` package to
  0.8 + `wlroots0.19`: 0.8 would need `wlroots0.19` packaged here anyway *and* both vendored
  patches rebased (dry-run against a clean 0.8 tarball: `ipc` fails 1/12 hunks, `vanitygaps` fails
  1/13 plus all of `config.def.h`; even the official `vanitygaps-0.8.patch` failed a hunk). Keeping
  0.7 needs no patch work and restores a known-good combination.

### Technical Details
- `wlroots0.18/` — straight AUR checkout (`https://aur.archlinux.org/wlroots0.18.git`), tracked as
  a gitlink like `sway-scroll` and `tinty-git`, plus a copy of the shared `build.sh`. Same pattern
  already used for `scenefx0.5`, another versioned wlroots-ecosystem library Arch does not ship.
- Its `source=` is a **signed git tag** (`#tag=${pkgver}?signed`), and the first build failed with
  `unknown public key 0FDE7BE0E88F5E48`. The checkout ships the three `validpgpkeys` (Simon Ser,
  Drew DeVault, the Sway signing key) under `keys/pgp/`, but **makepkg does not import them** —
  its only `keys/pgp/` handling (makepkg line ~836) copies keys *into a source package* when
  building one, never into a keyring for verification. And `makechrootpkg` verifies sources on the
  **host as the calling user** (`sudo -u "$makepkg_user" --preserve-env=GNUPGHOME`), not inside the
  chroot, so the chroot's keyring is irrelevant. Fix: `gpg --import keys/pgp/*.asc` once, into
  Erik's own keyring. Verified by re-running the exact step that failed —
  `makepkg --verifysource` now reports `wlroots0.18 git repo ... Passed`.
- That Passed line carries `WARNING: the key has expired`. Expired is a *warning* in makepkg, not
  an error, so the build proceeds — do not chase it.
- First build is not skipped: the shared `build.sh` compares against `.previous-version`, which
  does not exist yet, so `BUILD_NEEDED` becomes true.
- `kiro-dwl`'s PKGBUILD needs no dependency change — it already pins `wlroots0.18` in both
  `depends` and `makedepends`. Only its FIRST-BUILD ALIGNMENT GATE comment was corrected, which
  still claimed the wlroots comes from `[extra]`.

- **Second build failure: `-Werror` vs a newer libinput.** `LIBINPUT_SWITCH_KEYPAD_SLIDE` has been
  added to libinput since wlroots 0.18, and 0.18's `backend/libinput/switch.c` does not handle it;
  the project sets `werror=true` in its `default_options`, so `-Werror=switch` aborted the build at
  file 228 of 368. Fixed with a local delta: `arch-meson … -D werror=false`.
  Chosen over patching the single case because ~140 files were still unbuilt and any of them could
  trip the same class of new-header warning; one option covers them all. 0.18 is EOL (Arch dropped
  it, 0.18.3-1 is final) so upstream will never fix this.
  Runtime impact is nil: `wlr_event` is a designated initialiser, so an unmatched switch type reads
  as zero (LID) rather than uninitialised, and keypad-slide hardware does not exist on a Kiro desktop.
- The delta is **committed inside the AUR checkout** (and the parent gitlink bumped), not left as an
  uncommitted edit — `build.sh` runs `git pull` in the package dir before building, and a dirty
  tracked file would be at the mercy of any upstream change. Expect it to show as a local commit
  ahead of the AUR remote.

### Files Modified
- `wlroots0.18/` (new — AUR checkout + shared `build.sh`, plus the local werror delta)
- `../KIROTUX/KIROTUX-PKG-BUILD/kiro-dwl/PKGBUILD` (comment only; that tree is not a git repo)

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
