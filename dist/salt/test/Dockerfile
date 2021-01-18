FROM opensuse/leap:15.2
ENV container docker

ENV LANG en_US.UTF-8

RUN sed -i 's,http://download.opensuse.org,http://mirrorcache.opensuse.org/download,g' /etc/zypp/repos.d/*repo
RUN zypper --gpg-auto-import-keys ref

RUN zypper -n in curl salt-minion sudo

ADD test/dbus.service /etc/systemd/system/dbus.service

VOLUME ["/sys/fs/cgroup"]
VOLUME ["/run"]

RUN systemctl enable dbus.service
RUN mkdir -p /srv/salt/
RUN sed -i 's^\#?\s*file_client: .*$^file_client: local^' /etc/salt/minion

ADD profile /srv/salt/profile
ADD role /srv/salt/role

EXPOSE 80
EXPOSE 3000

ENTRYPOINT ["/usr/lib/systemd/systemd"]
