# Packaging

Native distro packages for notetux++ 1.0.0. No AppImage, Flatpak, or Snap.

## Install layout (all formats)

| Path | Content |
|------|---------|
| `/usr/bin/notetux++` | Compiled binary |
| `/usr/share/notetux/` | Runtime resources (themes, localization, icons, XML configs) |
| `/usr/share/pixmaps/notetux++.png` | Application icon |
| `/usr/share/applications/notetux++.desktop` | Desktop integration |

## .deb — Debian / Ubuntu / Mint

**Build dependencies:** `debhelper cmake libgtk-3-dev libglib2.0-dev`

```sh
# Install build deps (Debian/Ubuntu)
sudo apt-get install debhelper cmake libgtk-3-dev libglib2.0-dev libstdc++-dev

# From the repository root:
dpkg-buildpackage -b -us -uc

# Output: ../notetux++_1.0.0-1_amd64.deb
sudo dpkg -i ../notetux++_1.0.0-1_amd64.deb
```

## .rpm — Fedora / RHEL / openSUSE

**Build dependencies:** `cmake gcc gcc-c++ gtk3-devel glib2-devel rpm-build`

```sh
# Install build deps (Fedora)
sudo dnf install cmake gcc gcc-c++ gtk3-devel glib2-devel rpm-build desktop-file-utils

# Create the source tarball
git archive --format=tar.gz --prefix=notetux++-1.0.0/ HEAD \
    > ~/rpmbuild/SOURCES/notetux++-1.0.0.tar.gz

# Copy the spec and build
cp packaging/notetux++.spec ~/rpmbuild/SPECS/
rpmbuild -bb ~/rpmbuild/SPECS/notetux++.spec

# Output: ~/rpmbuild/RPMS/x86_64/notetux++-1.0.0-1.<dist>.x86_64.rpm
sudo rpm -i ~/rpmbuild/RPMS/x86_64/notetux++-1.0.0-1.*.x86_64.rpm
```

## .pkg.tar.zst — Arch / Manjaro

**Build dependencies:** `base-devel cmake`

```sh
# From packaging/ directory
cd packaging/
makepkg -s --noconfirm

# Output: notetux++-1.0.0-1-x86_64.pkg.tar.zst
sudo pacman -U notetux++-1.0.0-1-x86_64.pkg.tar.zst
```

> **Note:** update the `sha256sums` field in `PKGBUILD` once you have the release tarball URL.

## .apk — Alpine Linux

**Build dependencies:** `alpine-sdk cmake gtk+3.0-dev glib-dev`

```sh
# Install build deps
sudo apk add alpine-sdk cmake gtk+3.0-dev glib-dev samurai

# Set up abuild (once per machine)
abuild-keygen -a -i

# Copy the APKBUILD to abuild's expected location
mkdir -p ~/packages/notetux++
cp packaging/alpine/APKBUILD ~/packages/notetux++/
cd ~/packages/notetux++
abuild -r

# Output: ~/packages/notetux++/x86_64/notetux++-1.0.0-r0.apk
sudo apk add --allow-untrusted ~/packages/notetux++/x86_64/notetux++-1.0.0-r0.apk
```

## Spell checking (optional runtime dependency)

The spell checker uses `dlopen("libenchant-2.so.2", ...)` at runtime — it is
**not** a hard dependency. The app starts and runs normally without it.
Install `libenchant-2-2` (Debian), `enchant2` (Fedora/Arch), or `enchant`
(Alpine) to enable spell checking.
