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

ADD mirrorcache-01*.sls /srv/salt/
RUN salt-call --local state.apply -l debug mirrorcache-01*
ADD mirrorcache-02*.sls /srv/salt/
RUN salt-call --local state.apply -l debug mirrorcache-02*
ADD mirrorcache-030*.sls /srv/salt/
RUN salt-call --local state.apply -l debug mirrorcache-030*
ADD mirrorcache-031*.sls /srv/salt/
RUN mkdir -p /srv/salt/files
ADD files/* /srv/salt/files/
ADD mirrorcache-031*.sls /srv/salt/
RUN salt-call --local state.apply -l debug mirrorcache-031*
ADD mirrorcache-1*.sls /srv/salt/

RUN mkdir -p /var/run/postgresql && \
    chown postgres /var/run/postgresql && \
    sudo -u postgres /usr/share/postgresql/postgresql-script start && \
    salt-call --local state.apply -l debug mirrorcache-1* && \
    sudo -u postgres /usr/share/postgresql/postgresql-script stop

ADD mirrorcache-2*.sls /srv/salt/

EXPOSE 80
EXPOSE 3000

ENTRYPOINT ["/usr/lib/systemd/systemd"]
