#!/usr/bin/env bash

set -ex

LOCAL_BUILD_PREFIX="/sysroot"
LOCAL_MANIFEST="/io/.manifest"

cp -f /dev/null "${LOCAL_MANIFEST}"

libs=(
  libfdk-aac.a libfontconfig.a libfribidi.a libnuma.a
  libmp3lame.a libogg.a libopus.a libvorbis.a libvorbisenc.a libx264.a
  libbrotlidec.a libbrotlicommon.a libexpat.a libpng.a libpng16.a libuuid.a libz.a libbz2.a
)
mkdir -p "${LOCAL_BUILD_PREFIX}/lib"
for lib in "${libs[@]}"; do
  [[ ! -f "${LOCAL_BUILD_PREFIX}/lib/${lib}" ]] \
    && [[ -f "/usr/lib/x86_64-linux-gnu/${lib}" ]] \
    && ln -sf "/usr/lib/x86_64-linux-gnu/${lib}" "${LOCAL_BUILD_PREFIX}/lib/${lib}"
done

# for libass
(
  # for harfbuzz
  PKG_REPO="https://github.com/silnrsi/graphite"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/[0-9\.]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  cmake "../${PKG}" -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${LOCAL_BUILD_PREFIX}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF
  cmake --build . --parallel $(nproc) --target install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null

  # first stage build for harfbuz
  PKG_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/VER-[0-9\-]+$/ s#VER-(.*)#\1#p' | sort -t- -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "VER-${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  PKG_CONFIG_PATH=${LOCAL_BUILD_PREFIX}/lib/pkgconfig meson setup "../${PKG}" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --buildtype release --default-library=static \
    -Dtests=disabled
  ninja -j$(nproc) install

  # for libass
  PKG_REPO="https://github.com/harfbuzz/harfbuzz"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/[0-9\.]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  PKG_CONFIG_PATH=${LOCAL_BUILD_PREFIX}/lib/pkgconfig meson setup "../${PKG}" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --buildtype release --default-library=static \
    -Dtests=disabled -Dutilities=disabled -Dgraphite2=enabled -Dfreetype=enabled
  ninja -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null

  PKG_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/VER-[0-9\-]+$/ s#VER-(.*)#\1#p' | sort -t- -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "VER-${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  PKG_CONFIG_PATH=${LOCAL_BUILD_PREFIX}/lib/pkgconfig meson setup "../${PKG}" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --buildtype release --default-library=static \
    -Dtests=disabled -Dharfbuzz=enabled
  ninja -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null

  PKG_REPO="https://github.com/adah1972/libunibreak"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/libunibreak_[0-9\-_]+$/ s#libunibreak_(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "libunibreak_${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  PKG_CONFIG_PATH=${LOCAL_BUILD_PREFIX}/lib/pkgconfig "../${PKG}/autogen.sh" \
    --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --disable-shared --enable-static
  make -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null

  PKG_REPO="https://github.com/libass/libass"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/[0-9\.]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  ./autogen.sh && cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  PKG_CONFIG_PATH=${LOCAL_BUILD_PREFIX}/lib/pkgconfig "../${PKG}/configure" \
    --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --disable-shared --enable-static \
    --enable-fontconfig --enable-libunibreak --enable-harfbuzz
  make -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  PKG_REPO="https://code.videolan.org/videolan/dav1d"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/[0-9\.]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  meson setup "../${PKG}" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --buildtype release --default-library=static \
    -Denable_tools=false -Denable_tests=false
  ninja -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  PKG_REPO="https://aomedia.googlesource.com/aom"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/^v[0-9\.]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  cmake "../${PKG}" -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${LOCAL_BUILD_PREFIX}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_DOCS=OFF -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF -DENABLE_NASM=ON
  cmake --build . --parallel $(nproc) --target install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  PKG_REPO="https://gitlab.com/AOMediaCodec/SVT-AV1"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="v$(git tag | sed -En '/v[0-9\.]+$/ s#v(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  cmake "../${PKG}" -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${LOCAL_BUILD_PREFIX}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_DEC=OFF
  cmake --build . --parallel $(nproc) --target install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  PKG_REPO="https://github.com/Netflix/vmaf"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="v$(git tag | sed -En '/v[0-9\.]+$/ s#v(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  meson setup "../${PKG}/lib${PKG}" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" --buildtype release --default-library=static \
    -Denable_tests=false -Denable_docs=false
  ninja -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  PKG_REPO="https://chromium.googlesource.com/webm/libvpx"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="v$(git tag | sed -En '/v[0-9\.]+$/ s#v(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  "../${PKG}/configure" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="${LOCAL_BUILD_PREFIX}/lib" \
    --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm
  make -j$(nproc) install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  PKG_REPO="https://bitbucket.org/multicoreware/x265_git"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="$(git tag | sed -En '/^[0-9\.]+$/ s#(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  #https://github.com/rdp/ffmpeg-windows-build-helpers/issues/185
  cd .. && rm -rf "${PKG}_build_12bits" && mkdir "${PKG}_build_12bits" && cd "${PKG}_build_12bits"
  cmake "../${PKG}/source" -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${LOCAL_BUILD_PREFIX}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DSTATIC_LINK_CRT=ON -DEXPORT_C_API=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12=ON
  cmake --build . --parallel $(nproc)
  cd .. && rm -rf "${PKG}_build_10bits" && mkdir "${PKG}_build_10bits" && cd "${PKG}_build_10bits"
  cmake "../${PKG}/source" -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${LOCAL_BUILD_PREFIX}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DSTATIC_LINK_CRT=ON -DEXPORT_C_API=OFF -DHIGH_BIT_DEPTH=ON
  cmake --build . --parallel $(nproc)
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  ln -sf "../${PKG}_build_12bits/libx265.a" libx265_main12.a
  ln -sf "../${PKG}_build_10bits/libx265.a" libx265_main10.a
  cmake "../${PKG}/source" -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${LOCAL_BUILD_PREFIX}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DSTATIC_LINK_CRT=ON \
    -DEXTRA_LIB="x265_main10.a;x265_main12.a" -DEXTRA_LINK_FLAGS=-L. -DLINKED_10BIT=ON -DLINKED_12BIT=ON
  cmake --build . --parallel $(nproc)
  mv libx265.a libx265_main.a
  ar -M <<EOF
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
  cmake --install .
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null

  ## Remove -lstdc++ -lgcc -lgcc_s from x265.pc to honor --static-libstdc++ and --static-libgcc
  sed -i -E 's/(-lstdc\+\+)|(-lgcc)|(-lgcc_s)//g' "${LOCAL_BUILD_PREFIX}/lib/pkgconfig/x265.pc"
) &

(
  PKG_REPO="https://github.com/openssl/openssl"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="openssl-$(git tag | sed -En '/openssl-[0-9\.]+$/ s#openssl-(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  "../${PKG}/config" --prefix="${LOCAL_BUILD_PREFIX}" --libdir="lib" no-shared no-autoload-config no-engine no-dso no-deprecated no-legacy
  make -j$(nproc)
  make install_sw
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

(
  # for --enable-ffnvcodec
  PKG_REPO="https://git.videolan.org/git/ffmpeg/nv-codec-headers.git"
  PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
  cd /tmp
  [ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
  cd "${PKG}" && git clean -fd && git restore . && git fetch
  VER="n$(git tag | sed -En '/n[0-9\.]+$/ s#n(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
  git switch -C "${VER}"
  cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
  make -C "../${PKG}" PREFIX="${LOCAL_BUILD_PREFIX}" install
  echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null
) &

PKG_REPO="https://github.com/FFmpeg/FFmpeg"
PKG=$(echo ${PKG_REPO##*/} | sed -E 's/\.git$//')
pushd "/tmp" > /dev/null
[ ! -d "${PKG}" ] && git clone "${PKG_REPO}"
cd "${PKG}" && git clean -fd && git restore . && git fetch
VER="n$(git tag | sed -En '/n[0-9\.]+$/ s#n(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
git switch -C "${VER}"
#VER="$(git branch -a | sed -En '/\/[0-9\.]+$/ s#.*remotes/origin/release/(.*)#\1#p' | sort -t. -k 1,1n -k 2,2n -k 3,3n | sed '$!d')"
#git switch "release/${VER}"
sed -Ei \
  -e '/^[[:space:]]*int hide_banner = 0;$/ s#= 0#= 1#' \
  -e '/^[[:space:]]*hide_banner = 1;$/ s#= 1#= 0#' "../${PKG}/fftools/cmdutils.c"
cd .. && rm -rf "${PKG}_build" && mkdir "${PKG}_build" && cd "${PKG}_build"
wait

# --extra-cxxflags="" --extra-libs=""

PKG_CONFIG_PATH=${LOCAL_BUILD_PREFIX}/lib/pkgconfig "../${PKG}/configure" \
  --pkg-config-flags="--static" --disable-shared --enable-static \
  --enable-gpl --enable-nonfree --enable-version3 \
  --extra-version=$(date +%Y%m%d) \
  --disable-doc --enable-pic \
  --extra-cflags="-I${LOCAL_BUILD_PREFIX}/include" \
  --ld="c++" --extra-ldflags="-static-libgcc -static-libstdc++ -L${LOCAL_BUILD_PREFIX}/lib" \
  --enable-libass \
  --enable-libaom \
  --enable-libdav1d \
  --enable-libfdk-aac \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libsvtav1 \
  --enable-cuda-llvm --enable-ffnvcodec \
  --enable-libvmaf \
  --enable-libvorbis \
  --enable-libvpx \
  --enable-libx264 \
  --enable-libx265 \
  --enable-openssl
make -j$(nproc)

echo "${PKG}: ${VER}" | tee -a "${LOCAL_MANIFEST}" > /dev/null

popd > /dev/null

cp -av "/tmp/${PKG}_build/ffmpeg" .
cp -av "/tmp/${PKG}_build/ffprobe" .
