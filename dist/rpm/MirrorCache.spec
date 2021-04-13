#
# spec file for package MirrorCache
#
# Copyright (c) 2020 SUSE LLC
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

%define mirrorcache_services mirrorcache.service mirrorcache-backstage.service

%define assetpack_requires perl(CSS::Minifier::XS) >= 0.01 perl(JavaScript::Minifier::XS) >= 0.11 perl(Mojolicious::Plugin::AssetPack) >= 1.36 perl-IO-Socket-SSL
%define main_requires %assetpack_requires perl(Carp) perl(DBD::Pg) >= 3.7.4 perl(DBI) >= 1.632 perl(DBIx::Class) >= 0.082801 perl(DBIx::Class::DynamicDefault) perl(DateTime) perl(DateTime::Format::Pg) perl(Exporter) perl(File::Basename) perl(LWP::UserAgent) perl(Mojo::Base) perl(Mojo::ByteStream) perl(Mojo::IOLoop) perl(Mojo::JSON) perl(Mojo::Pg) perl(Mojo::URL) perl(Mojo::Util) perl(Mojolicious::Commands) perl(Mojolicious::Plugin) perl(Mojolicious::Plugin::RenderFile) perl(Mojolicious::Static) perl(Net::OpenID::Consumer) perl(POSIX) perl(URI::Encode) perl(URI::Escape) perl(XML::Writer) perl(base) perl(constant) perl(diagnostics) perl(strict) perl(warnings) shadow rubygem(sass) perl-Net-DNS perl-LWP-Protocol-https
%define build_requires %assetpack_requires rubygem(sass) tidy

Name:           MirrorCache
Version:        0.1
Release:        0
Summary:        WebApp to redirect and manage mirrors
License:        GPL-2.0-or-later
Group:          Productivity/Networking/Web/Servers
URL:            https://github.com/andrii-suse/MirrorCache
Source:         %{name}-%{version}.tar.xz
BuildRequires:  %build_requires
Requires:       perl(Minion) >= 10.0
Requires:       %{main_requires}
BuildArch:      noarch

%description
Mirror redirector web service, which automatically scans the main server and mirrors

%prep
%setup -q

%build
# make {?_smp_mflags}

%check

%install
%make_install
# DEST_DIR={_datadir}
mkdir -p %{buildroot}%{_sbindir}
ln -s ../sbin/service %{buildroot}%{_sbindir}/rcmirrorcache
ln -s ../sbin/service %{buildroot}%{_sbindir}/rcmirrorcache-backstage

%pre
getent group nogroup > /dev/null || groupadd nogroup
getent passwd mirrorcache > /dev/null || %{_sbindir}/useradd -r -g nogroup -c "MirrorCache user" -d %{_localstatedir}/lib/mirrorcache mirrorcache || :
if [ ! -e %{_localstatedir}/lib/mirrorcache ]; then
    mkdir -p %{_localstatedir}/lib/mirrorcache
    chown mirrorcache %{_localstatedir}/lib/mirrorcache || :
fi
%service_add_pre %{mirrorcache_services}

%post
chown mirrorcache %{_datadir}/mirrorcache/assets/cache
%service_add_post %{mirrorcache_services}

%preun
%service_del_preun %{mirrorcache_services}

%postun
%service_del_postun %{mirrorcache_services}

%files
%doc README.asciidoc
%{_sbindir}/rcmirrorcache
%{_sbindir}/rcmirrorcache-backstage
# init
%dir %{_unitdir}
%{_unitdir}/mirrorcache.service
%{_unitdir}/mirrorcache-backstage.service
# web libs
%{_datadir}/mirrorcache

%changelog
