#!/usr/bin/env bash

set -ex

LOCAL_BUILD_PREFIX="/sysroot"

LOCAL_CFLAGS=""
LOCAL_LDFLAGS="-s -static -static-libstdc++ -static-libgcc"
if [ $# -ge 1 ] && [ "${1}" == "x86" ]; then
  LOCAL_CFLAGS="${LOCAL_CFLAGS} -m32"
  LOCAL_LDFLAGS="${LOCAL_LDFLAGS} -m32"
fi

## Build library parallelly

# zlib
(
  PKG_REPO="https://github.com/madler/zlib"
  PKG=${PKG_REPO##*/}
  pushd "/tmp" > /dev/null
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="v$(git tag | sed -En '/v[0-9\.]+$/ s#v(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}" "tags/${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  CFLAGS="${LOCAL_CFLAGS}" LDFLAGS="${LOCAL_LDFLAGS}" "../${PKG}/configure" \
    --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" \
    --static
  make -j$(nproc) install
) &

# openssl
(
  PKG_REPO="git://git.openssl.org/openssl"
  PKG=${PKG_REPO##*/}
  pushd "/tmp" > /dev/null
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="openssl-$(git tag | sed -En '/openssl-[0-9\.]+$/ s#openssl-(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}" "tags/${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
 #"../${PKG}/config" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="lib" no-shared no-autoload-config no-engine no-dso no-tests no-deprecated no-legacy
  "../${PKG}/config" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="lib" no-shared no-autoload-config no-engine no-dso no-tests linux-x86
  make -j$(nproc)
  make install_sw
) &

## Pull main program
PKG_REPO="https://github.com/openssh/openssh-portable"
PKG=${PKG_REPO##*/}
pushd "/tmp" > /dev/null
[ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
cd "${PKG}" && git clean -fd && git restore . && git fetch
VER="$(git tag | sed -En '/V_[0-9_]+_P[0-9]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
git switch -C "${VER}" "tags/${VER}"
cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"

wait

  #--with-cflags="-I${LOCAL_BUILD_PREFIX}/include" \
  #--with-ldflags="-static -static-libstdc++ -static-libgcc -L${LOCAL_BUILD_PREFIX}/lib" \
## Build main program
autoreconf ../${PKG}
CFLAGS="${LOCAL_CFLAGS}" LDFLAGS="${LOCAL_LDFLAGS}" "../${PKG}/configure" \
  --with-ssl-dir=${LOCAL_BUILD_PREFIX} --with-zlib=${LOCAL_BUILD_PREFIX} \
  --without-pie --with-privsep-user=nobody
make -j$(nproc) ssh

popd > /dev/null

cp -av "/tmp/${PKG}_build/ssh" .
