SBIN_DIR ?= /usr/sbin
USR_DIR ?= /usr
MC_SRV_USER ?= mirrorcache
MIRRORCACHE_DNS ?= 'DBI:Pg:database=mirrorcache'

mkfile_path := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

install:
	for i in lib script templates assets; do \
		mkdir -p "${DESTDIR}"/usr/share/mirrorcache/$$i ;\
		cp -a $$i/* "${DESTDIR}"/usr/share/mirrorcache/$$i ;\
	done
	chmod +x "${DESTDIR}"/usr/share/mirrorcache/script/*
	install -d -m 755 "${DESTDIR}"/usr/lib/systemd/system
	for i in dist/systemd/*.service; do \
		install -m 644 $$i "${DESTDIR}"/usr/lib/systemd/system ;\
	done

setup_system_user:
	getent group nogroup > /dev/null || groupadd nogroup
	getent passwd ${MC_SRV_USER} > /dev/null || ${SBIN_DIR}/useradd -r -g nogroup -c "MirrorCache user" \
	       -d ${USR_DIR}/lib/ ${MC_SRV_USER} 2>/dev/null || :

setup_system_db:
	sudo -u postgres createuser mirrorcache
	sudo -u postgres createdb mirrorcache
	sudo -u mirrorcache psql -f sql/schema.sql mirrorcache

setup_production_assets:
	cd "${DESTDIR}"/usr/share/mirrorcache/ && \
	    MOJO_MODE=production ${mkfile_path}/tools/generate-packed-assets 
