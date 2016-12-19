%define rpmrelease %{nil}
%define bindir /opt/ncsbin/lnxutils

Summary: Linux Utilities
Name: lnxutils
Version: 2.0
Release: 1%{?rpmrelease}%{?dist}
License: GPLv3
Group: Applications/File
URL: https://github.com/gdha/lnxutils

Source: https://github.com/gdha/lnxutils/downloads/lnxutils-%{version}.tar.gz
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

#BuildArchitectures: i386 x86_64

### Dependencies on all distributions
# 20120801-22.el7_1.2 or higher
#Requires: ksh >= 20120801-22%{?dist}_1.2

%description
A collection of various Linux utilities

%prep
%setup -q

%build

%install
%{__rm} -rf %{buildroot}
# create directories
mkdir -vp \
        %{buildroot}%{_mandir}/man8 \
        %{buildroot}%{bindir}

# copy components into directories
#cp -av .%{bindir}/*.sh %{buildroot}%{bindir}
%{__make} install DESTDIR="%{buildroot}"

#%post
# check for /usr/bin/ksh on Linux (probably only /bin/ksh)
#if [ ! -f /usr/bin/ksh ] && [ -f /bin/ksh ]; then
        #ln -s /bin/ksh /usr/bin/ksh
#fi

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root, 0755)
#%doc %{_mandir}/man8/adhocr.8*
%{bindir}/*.sh

%changelog
* Tue Dec 13 2016 Gratien D'haese ( gratien.dhaese at gmail.com ) -  2.0-1
- Added some new scripts

* Mon Feb 02 2015 Gratien D'haese ( gratien.dhaese at gmail.com ) - 1.0-1
- Initial package.

