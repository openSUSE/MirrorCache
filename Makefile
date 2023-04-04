SBIN_DIR ?= /usr/sbin
USR_DIR ?= /usr
MC_SRV_USER ?= mirrorcache
MC_SRV_GROUP ?= mirrorcache
MIRRORCACHE_DNS ?= 'DBI:Pg:database=mirrorcache'

mkfile_path := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

test_local:
	( for f in $$(ls -t t/environ/*.sh); do bash -x $$f && continue; echo FAIL $$f; exit 1 ; done )

test_docker:
	( cd t/environ; for f in *.sh; do ./$$f && continue; echo FAIL $$f; exit 1 ; done )

test_docker_mariadb:
	( cd t/environ; for f in *.sh; do MIRRORCACHE_DB_PROVIDER=mariadb ./$$f && continue; echo FAIL $$f; exit 1 ; done )

test_docker_mariadb_experimental:
	( cd t/environ; for f in *.sh; do MIRRORCACHE_DB_PROVIDER=mariadb T_EXPERIMENTAL=1 ./$$f && continue; echo FAIL $$f; exit 1 ; done )

test_systemd:
	( cd t/systemd; for f in *.sh; do ./$$f && continue; echo FAIL $$f; exit 1 ; done )

test_stress:
	( for f in $$(ls -t t/stress/*.sh); do bash $$f |& tee log/stress/$$(basename $$f).log && continue; echo FAIL $$f; exit 1 ; done )

tar.xz:
	git archive --format=tar HEAD | xz > mirrorcache-0.1.tar.xz

install:
	for i in lib script templates assets sql; do \
		mkdir -p "${DESTDIR}"/usr/share/mirrorcache/$$i ;\
		[ ! -e $$i ] || cp -a $$i/* "${DESTDIR}"/usr/share/mirrorcache/$$i ;\
	done
	chmod +x "${DESTDIR}"/usr/share/mirrorcache/script/*
	install -d -m 755 "${DESTDIR}"/usr/lib/systemd/system
	for i in dist/systemd/*.service; do \
		install -m 644 $$i "${DESTDIR}"/usr/lib/systemd/system ;\
	done
	install -D -m 755 -d "${DESTDIR}"/etc/mirrorcache

setup_system_user:
	getent group ${MC_SRV_GROUP} > /dev/null || groupadd ${MC_SRV_GROUP}
	getent passwd ${MC_SRV_USER} > /dev/null || ${SBIN_DIR}/useradd -r -g ${MC_SRV_GROUP} -c "MirrorCache user" \
	       -d ${USR_DIR}/lib/ ${MC_SRV_USER} 2>/dev/null || :
	mkdir -p "${DESTDIR}"/usr/share/mirrorcache/assets/cache
	chown ${MC_SRV_USER} "${DESTDIR}"/usr/share/mirrorcache/assets/cache
	mkdir -p "${DESTDIR}"/run/mirrorcache
	chown ${MC_SRV_USER} "${DESTDIR}"/run/mirrorcache

setup_system_db:
	sudo -u postgres createuser mirrorcache
	sudo -u postgres createdb mirrorcache

setup_production_assets:
	cd "${DESTDIR}"/usr/share/mirrorcache/ && \
	    MOJO_MODE=production ${mkfile_path}/tools/generate-packed-assets
