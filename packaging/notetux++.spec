Name:           notetux++
Version:        1.0.0
Release:        1%{?dist}
Summary:        Feature-rich text editor for Linux

License:        GPL-3.0-or-later
URL:            https://github.com/andreacos/notetux
# Create the tarball with:
#   git archive --format=tar.gz --prefix=notetux++-1.0.0/ HEAD \
#       > ~/rpmbuild/SOURCES/notetux++-1.0.0.tar.gz
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  cmake >= 3.20
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  gtk3-devel
BuildRequires:  glib2-devel
BuildRequires:  desktop-file-utils

Requires:       gtk3
Requires:       glib2
Requires:       libstdc++
Requires:       libatomic
Recommends:     enchant2

%description
notetux++ is a native Linux port of Notepad++, built with GTK3 and
the Scintilla editing component. It provides syntax highlighting for
over 80 languages, a tabbed interface, find-in-files, macros,
a plugin system, and extensive customisation via XML themes and
Notepad++ compatible localization files.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DRESOURCES_DIR=%{_datadir}/notetux
%cmake_build

%install
# Binary
install -D -m 0755 %{_vpath_builddir}/notetux++ \
    %{buildroot}%{_bindir}/notetux++

# Resources tree
install -d %{buildroot}%{_datadir}/notetux
cp -r resources/. %{buildroot}%{_datadir}/notetux/

# Pixmap icon
install -D -m 0644 resources/icons/standard/icon.png \
    %{buildroot}%{_datadir}/pixmaps/notetux++.png

# .desktop file
install -D -m 0644 packaging/notetux++.desktop \
    %{buildroot}%{_datadir}/applications/notetux++.desktop
desktop-file-validate %{buildroot}%{_datadir}/applications/notetux++.desktop

%files
%license LICENSE
%{_bindir}/notetux++
%{_datadir}/notetux/
%{_datadir}/pixmaps/notetux++.png
%{_datadir}/applications/notetux++.desktop

%changelog
* Fri May 16 2026 Andrea Coi <acandry90@gmail.com> - 1.0.0-1
- Initial release
