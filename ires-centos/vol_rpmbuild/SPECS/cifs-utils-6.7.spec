Name:           cifs-utils
Version:        6.7
Release:        1%{?dist}
Summary:        CIFS utils for RedHat / CentOS

Group:          Applications
License:        BSD
URL:            https://git.samba.org/cifs-utils.git
Source0:        https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-6.7.tar.bz2

Requires:       libtalloc libwbclient

%description
CIFS utils, a package of utilities for doing and managing mounts of the Linux CIFS filesystem.

%prep
%setup -q


%build
autoreconf -i
%configure --enable-cifsacl
make

%install
%make_install


%clean
rm -rf %{buildroot}

%files
%defattr(-,root,root,-)
/usr/bin/cifscreds
/usr/bin/getcifsacl
/usr/bin/setcifsacl
/usr/include/cifsidmap.h
/usr/lib64/cifs-utils/idmapwb.so
/usr/share/man/man1/cifscreds.1.gz
/usr/share/man/man1/getcifsacl.1.gz
/usr/share/man/man1/setcifsacl.1.gz
/usr/share/man/man8/mount.cifs.8.gz
/usr/share/man/man8/cifs.upcall.8.gz
/usr/share/man/man8/cifs.idmap.8.gz
/usr/share/man/man8/idmapwb.8.gz
/usr/sbin/cifs.idmap
/usr/sbin/cifs.upcall
/sbin/mount.cifs


%changelog
* Tue Apr 25 2017 Maarten Coonen <m.coonen@maastrichtuniversity.nl>
* DataHub cifs-utils rpm release version 6.7.0
