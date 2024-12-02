#!/usr/bin/bash

# requirements:
# bzip2 cpio perl-IO-Socket-SSL perl-Mojolicious
# perl-Mojolicious-Plugin-AssetPack ruby3.3-rubygem-sass

set -e

export LC_ALL='en_US.UTF-8'
export LANG='en_US.UTF-8'

mkdir -p MirrorCache-update-cache
rm -rf MirrorCache-update-cache/*
pushd MirrorCache-update-cache

cpio -id < ../MirrorCache-*.obscpio
pushd MirrorCache-*

./tools/generate-packed-assets
tar cvjf ../../cache.tar.xz assets/cache assets/assetpack.db

popd
popd
rm -rf MirrorCache-update-cache/*
