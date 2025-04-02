FROM registry.opensuse.org/opensuse/leap
ENV container podman

ENV LANG en_US.UTF-8
# packages needed for test
RUN zypper -vvv -n install vim curl sudo salt-minion git

RUN mkdir -p /srv/salt/ && \
  sed -i 's^\#*\s*file_client: .*$^file_client: local\nsystemd.scope: False\nenable_fqdns_grains: False^' /etc/salt/minion && \
  sed -i '/pam_systemd.so/d' /etc/pam.d/common-session-pc # delete pam_systemd , otherwise sudo will hang

RUN mkdir -p /srv/pillar/

RUN echo "{{ saltenv }}:" > /srv/pillar/top.sls
RUN echo '  "*":'        >> /srv/pillar/top.sls
RUN echo "    - repo"    >> /srv/pillar/top.sls

RUN echo mirrorcache_formula_enable_repository: True > /srv/pillar/repo.sls

WORKDIR /opt
ADD mirrors-eu.sql /opt
RUN git clone https://github.com/andrii-suse/mirrorcache-formula
RUN cp -r /opt/mirrorcache-formula/mirrorcache /srv/salt/mirrorcache

ENV MIRRORCACHE_DB_PROVIDER postgresql

EXPOSE 3000

ENTRYPOINT ["/usr/lib/systemd/systemd"]
