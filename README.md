# edu-pkgbuild-3party

Third-party and AUR package builds for the [nemesis_repo](https://github.com/erikdubois/nemesis_repo) — the custom Arch Linux package repository used by the [Kiro](https://github.com/erikdubois/kiro-iso) distribution.

Each subdirectory is a self-contained package build: `PKGBUILD`, a `build.sh` wrapper, and version-tracking files.

---

## Packages

| Package                           | Description                                                               |
|-----------------------------------|---------------------------------------------------------------------------|
| `arc-gtk-theme`                   | Flat GTK 2/3/4 theme with transparency; also builds `arc-solid-gtk-theme` |
| `ckb-next-git`                    | Corsair keyboard and mouse input driver (git)                             |
| `flameshot-git`                   | Screenshot tool (git)                                                     |
| `gnome-bluetooth`                 | GNOME Bluetooth subsystem (legacy)                                        |
| `hardcode-fixer-git`              | Fixes hardcoded application icons (git)                                   |
| `lastpass`                        | Universal LastPass installer for Firefox, Chrome, and Opera               |
| `libpamac-aur`                    | Pamac package manager library (AUR variant)                               |
| `opera-ffmpeg-codecs-bin`         | Proprietary FFmpeg codecs for Opera                                       |
| `pacman-hook-kernel-install`      | Pacman hooks for kernel-install                                           |
| `pamac-aur`                       | GTK package manager with AUR and Appstream support                        |
| `sparklines-git`                  | Sparklines for the shell (git)                                            |
| `ttf-material-design-iconic-font` | Material Design Iconic Font                                               |
| `wttr`                            | Weather check script via wttr.in                                          |

---

## Build system

### Build a single package

```bash
cd <package-dir>
bash build.sh
```

Each `build.sh`:

1. Pulls latest git if the package dir is a repo
2. Auto-bumps `pkgver` (`YY.MM`) and `pkgrel` for date-versioned packages
3. Skips the build if `pkgver`/`pkgrel`/`epoch` haven't changed since last run
4. Builds in a clean chroot at `~/Documents/chroot-archlinux` via `makechrootpkg`
5. Copies the resulting `.pkg.tar.zst` to `~/EDU/nemesis_repo/x86_64/`

### Build all packages and publish

```bash
bash 1-build-all-packages.sh
```

Iterates every package directory, runs its `build.sh`, then calls `~/EDU/nemesis_repo/up.sh` to sign and update the repo database.

### Propagate the shared build template

```bash
bash copy-files-to-all-folders.sh
```

Copies the root `build.sh` into every package subdirectory that already has one.

---

## Adding a new package

1. Create a subdirectory named after the package.
2. Add a `PKGBUILD` (standard Arch format).
3. Create `.previous-version` with zeroed values:
   ```
   pkgver=
   pkgrel=
   epoch=
   ```
4. Copy `build.sh` from the repo root into the new directory.
5. Optionally add `.nvchecker.toml` to track upstream releases.

---

## Version schemes

- **Date-versioned** — `pkgver` matches `YY.MM` (e.g. `26.05`). `build.sh` bumps automatically on each run; `pkgrel` resets to `01` on a new month.
- **Upstream-versioned** — any other `pkgver` format. The bump step is skipped; update `pkgver`/`pkgrel` manually in `PKGBUILD` when upstream releases.

---

## Author

Erik Dubois — [https://www.erikdubois.be](https://www.erikdubois.be)
