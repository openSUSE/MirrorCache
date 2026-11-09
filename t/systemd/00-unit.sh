#!../lib/test-in-container-systemd.sh

set -ex

# Ensure test packages are installed if reusing a previously cached container image
rpm -q perl-Mojolicious-Plugin-OAuth2 || zypper -n in perl-Mojolicious-Plugin-OAuth2

make test_unit
