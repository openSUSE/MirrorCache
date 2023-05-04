FROM opensuse/leap
ENV container docker

ENV LANG en_US.UTF-8
# packages needed for test
RUN zypper -vvv -n install vim curl sudo salt-minion git

RUN mkdir -p /srv/salt/
RUN sed -i 's^\#*\s*file_client: .*$^file_client: local\nsystemd.scope: False\nenable_fqdns_grains: False^' /etc/salt/minion

WORKDIR /opt
ADD mirrors-eu.sql /opt
RUN git clone https://github.com/andrii-suse/mirrorcache-formula
RUN ln -s /opt/mirrorcache-formula/mirrorcache /srv/salt/mirrorcache

ENV MIRRORCACHE_DB_PROVIDER postgresql

EXPOSE 3000

ENTRYPOINT ["/usr/lib/systemd/systemd"]
