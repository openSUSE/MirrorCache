FROM opensuse/leap:15.2
ENV container docker

ENV LANG en_US.UTF-8

RUN sed -i 's,http://download.opensuse.org,http://mirrorcache.opensuse.org/download,g' /etc/zypp/repos.d/*repo
RUN zypper --gpg-auto-import-keys ref

RUN zypper -vvvv -n in curl salt-minion sudo # test

# optimization RUN zypper ar -f http://mirrorcache.opensuse.org/repositories/devel:/languages:/perl/openSUSE_Leap_15.2 perl
# optimization RUN zypper --gpg-auto-import-keys ref

# optimization RUN zypper -vvv -n install perl-DBIx-Class perl-Data-Dumper-Concise perl-Digest-MD5 perl-Mojolicious perl-Mojo-Pg sudo vim postgresql postgresql-server \
# optimization             apache2 perl-Mojolicious-Plugin-RenderFile perl-Minion perl-DateTime perl-DBIx-Class-DynamicDefault perl-DateTime-Format-Pg tidy perl-Net-DNS \
# optimization             perl-Mojolicious-Plugin-AssetPack perl-Net-OpenID-Consumer perl-LWP-Protocol-https perl-URI

# optimization RUN zypper -vvv -n install perl-App-cpanminus
# optimization RUN zypper -vvv -n install gzip gcc make
# optimization RUN cpanm Mojolicious::Plugin::ClientIP --sudo
# optimization RUN cpanm MaxMind::DB::Reader --sudo || :


ADD test/dbus.service /etc/systemd/system/dbus.service

VOLUME ["/sys/fs/cgroup"]
VOLUME ["/run"]

RUN systemctl enable dbus.service
RUN mkdir -p /srv/salt/
RUN sed -i 's^\#?\s*file_client: .*$^file_client: local^' /etc/salt/minion

ADD profile /srv/salt/profile
ADD role /srv/salt/role

EXPOSE 3000

ENTRYPOINT ["/usr/lib/systemd/systemd"]
