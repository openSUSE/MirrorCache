FROM opensuse/leap:15.3
ENV container docker

ENV LANG en_US.UTF-8

RUN sed -i 's,http://download.opensuse.org,https://mirrorcache.opensuse.org/download,g' /etc/zypp/repos.d/*repo
RUN zypper ar -f https://mirrorcache.opensuse.org/repositories/openSUSE:infrastructure:MirrorCache/openSUSE_Leap_15.3 mc
RUN zypper --gpg-auto-import-keys ref

RUN zypper -vvv -n install MirrorCache perl-MaxMind-DB-Reader perl-Mojolicious-Plugin-ClientIP vim postgresql postgresql-server curl sudo salt-minion

ADD test/dbus.service /etc/systemd/system/dbus.service

VOLUME ["/sys/fs/cgroup"]
VOLUME ["/run"]

RUN systemctl enable dbus.service
RUN mkdir -p /srv/salt/
RUN sed -i 's^\#?\s*file_client: .*$^file_client: local^' /etc/salt/minion

ADD profile /srv/salt/profile

EXPOSE 3000

ENTRYPOINT ["/usr/lib/systemd/systemd"]
