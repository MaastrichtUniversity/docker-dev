## Instructions RPM build

0. Make sure the contents of /root/rpmbuild are chowned by `root:root`
1. Download source tarball
```
cd /root/rpmbuild/SOURCES
wget https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-6.7.tar.bz2
```

2. Build from `.spec` file
```
cd /root/rpmbuild/SPECS
rpmbuild -ba cifs-utils-6.7.spec
```

3. Find the created RPM's in `/root/rpmbuild/RPMS/x86_64/`
4. To install the package
```
sudo rpm -Uvh /root/rpmbuild/RPMS/x86_64/cifs-utils-6.7-1.el7.centos.x86_64.rpm
```
