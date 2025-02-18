#!/usr/bin/env bash

set -ex

function init_env() {
  export ROOT_DIR="${ROOTDIR:-/sysroot}"
  export WORKING_PATH="${WORKING_PATH:-$(pwd)}"
  export TMP_DIR="${TMP_DIR:-/tmp}"

  if [[ "${WITHOUT_CLANG}" != "yes" ]]; then
    export CC="${CC:-clang}"
    export CXX="${CXX:-clang++}"
  else
    export CC="${CC:-gcc}"
    export CXX="${CXX:-g++}"
  fi

  libs=(
    libfdk-aac.a libfontconfig.a libfribidi.a libnuma.a
    libvorbisenc.a libmp3lame.a libogg.a libopus.a libvorbis.a libx264.a
    libexpat.a libuuid.a
  )
  mkdir -p "${ROOT_DIR}/lib"
  for lib in "${libs[@]}"; do
    if [[ ! -f "${ROOT_DIR}/lib/${lib}" ]] && [[ -f "/usr/lib/x86_64-linux-gnu/${lib}" ]]; then
      ln -sf "/usr/lib/x86_64-linux-gnu/${lib}" "${ROOT_DIR}/lib/${lib}"
    fi
  done
}

function change_dir() {
  local dir="${1}"
  mkdir -p "${dir}"
  pushd "${dir}" > /dev/null
}

function change_clean_dir() {
  local dir="${1}"
  rm -rf "${dir}" && change_dir "${dir}"
}

function enable_trace() {
  set -o xtrace
}

function disable_trace() {
  set +o xtrace
}

function _get_tag() {
  disable_trace

  local ver_exp content tag_verion_map tag_name
  local version="${1}"
  content=$(cat -)

  ## search releases result from github

  ## build a pair of version numbers as tagname__major.minor.patch
  ## for example: curl-8_12_0__8.12.0 or v1.3__1.3. (without patch)
  ver_exp="(([^0-9]*|[^0-9]+[0-9][^0-9])([0-9]+)[^0-9]([0-9]+)([^0-9]([0-9]+))?([^0-9]([0-9]+))?)"
  tag_verion_map=$(echo "${content}" \
    | sed -En 's#'"${ver_exp}"'#\1__\3.\4.\6.\8#p'
  )

  if [ -z "${tag_verion_map}" ]; then
    echo ","
    return
  fi

  ## also hard code for aomedia
  ## https://aomedia.googlesource.com/aom/+refs/tags?format=JSON
  ## "3gpp-2021-10-15-2__2021.10.15.2"
  ## alos procedd the patch version is not integer, like 1.7.0.beta88
  tag_verion_map=$(echo "${tag_verion_map}" \
  | sed -E '/^3gpp-/d' \
  | sed -E '/__[0-9]+\.[0-9]+\.[0-9]+\.[^0-9]+/d')

  if [ -z "${version}" ]; then
    version=$(echo "${tag_verion_map%x}" \
      | sed 's#.*__##' \
      | sort -t. -k 1,1n -k 2,2n -k 3,3n -k 4,4n\
      | sed '$!d'
    )
  fi

  enable_trace

  tag_name="$(echo "${tag_verion_map%x}" | sed -En '/__'"${version}"'\.*$/ s#__.*##p')"

  ## remove redundant dot, for example 4.1,4.1.. -> v4.1,4.1
  version=$(echo "${version}" | sed -E '/\.+$/ s###')

  echo "${tag_name},${version}"
}

function url_from_git_server() {
  local repo git_srv git_type srv_content srv_rel_url srv_tag_url rel_tag_key rel_dl_key tag_tag_key tag_dl_url
  local browser_download_urls browser_download_url url result ret_tag ret_ver
  local repo_url="${1}"
  local version="${2}"

  git_srv=$(echo "${repo_url}" | sed -E 's#.*//([^/]+)/.*#\1#' | tr '[:upper:]' '[:lower:]')
  repo=$(echo "${repo_url}" | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's#\.git$##')
  PKG=$(echo "${repo##*/}")

  if [[ "${git_srv}" == "github.com" ]]; then
    git_type="github"
    srv_rel_url="https://api.github.com/repos/${repo}/releases"
    srv_tag_url="https://api.github.com/repos/${repo}/tags"
    rel_tag_key="tag_name"
    rel_dl_key="browser_download_url"
    tag_tag_key="name"
    tag_dl_url="https://github.com/${repo}/archive"
  elif [[ "${git_srv}" == "bitbucket.org" ]]; then
    git_type="bitbucket"
    srv_rel_url="" # "https://api.bitbucket.org/2.0/repositories/${repo}/downloads"
    srv_tag_url="https://api.bitbucket.org/2.0/repositories/${repo}/refs/tags?&sort=-target.date&pagelen=100"
    rel_tag_key=""
    rel_dl_key=""
    tag_tag_key="name"
    tag_dl_url="https://bitbucket.org/${repo}/get"
  elif [[ "${git_srv}" =~ ".googlesource.com" ]]; then
    git_type="googlesource"
    srv_rel_url=""
    srv_tag_url="${repo_url}/+refs/tags?format=JSON"
    rel_tag_key=""
    rel_dl_key=""
    tag_tag_key="name"
    tag_dl_url="${repo_url}/+archive"
  else
    # gitlab has too many subdomains, so the rest of git server is gitlab
    # https://code.videolan.org/videolan/dav1d
    # https://gitlab.freedesktop.org/freetype/freetype
    git_type="gitlab"
    srv_rel_url="https://${git_srv}/api/v4/projects/${repo/\//%2F}/releases"
    srv_tag_url="https://${git_srv}/api/v4/projects/${repo/\//%2F}/repository/tags"
    rel_tag_key="tag_name"
    rel_dl_key="url"
    tag_tag_key="name"
    tag_dl_url="https://${git_srv}/${repo}/-/archive"
  fi

  ## search release page
  if [ -n "${srv_rel_url}" ]; then
    disable_trace
    srv_content=$(curl -fsSL "${srv_rel_url}")
    if [ "${git_type}" = "gitlab" ]; then
      srv_content=$(echo "${srv_content}" | sed -E 's#,#,\n#g')
    fi

    result=$(echo "${srv_content%x}" \
      | sed -En '/"'"${rel_tag_key}"'":/ s#.*:[[:blank:]]*"([^"]*)",#\1#p' \
      | _get_tag "${version}")
    enable_trace

    ret_tag=$(echo "$result" | cut -d ',' -f 1)
    ret_ver=$(echo "$result" | cut -d ',' -f 2)

    disable_trace
    if [ -n "${ret_tag}" ]; then
      browser_download_urls=$(echo "${srv_content%x}" \
        | sed -En '/"'"${rel_dl_key}"'":/ s#.*"'"${rel_dl_key}"'":[[:blank:]]*"([^"]+(\.gz|\.tgz|\.bz2|\.xz|\.zstd|\.zst))".*#\1#p' \
        | sed -En '/\/'"${ret_tag}"'\//p' \
        || true)
    fi
    enable_trace
  fi

  ## search release page failed, search tag page
  if [ -n "${srv_tag_url}" ] && [ -z "${browser_download_urls}" ]; then
    disable_trace
    echo "curl -fsSL ${srv_tag_url}"
    srv_content=$(curl -fsSL "${srv_tag_url}")
    if [ "${git_type}" = "bitbucket" ] || [ "${git_type}" = "gitlab" ]; then
      srv_content=$(echo "${srv_content}" | sed -E 's#,#,\n#g')
    elif [ "${git_type}" = "googlesource" ]; then
      # "v3.1.0": {   ->  "tag_name": "v3.1.0",
      srv_content=$(echo "${srv_content}" | sed -En '/[[:blank:]]*"[^"]+": \{/ s#.*("[^"]+").*#"'"${tag_tag_key}"'": \1,#p')
    fi

    result=$(echo "${srv_content%x}" \
      | sed -En '/"'"${tag_tag_key}"'":/ s#.*:[[:blank:]]*"([^"]*)",#\1#p' \
      | _get_tag "${version}")
    enable_trace

    ret_tag=$(echo "$result" | cut -d ',' -f 1)
    ret_ver=$(echo "$result" | cut -d ',' -f 2)

    disable_trace
    if [ -n "${ret_tag}" ]; then
      browser_download_urls="${tag_dl_url}/${ret_tag}.tar.gz"
    fi
    enable_trace
  fi

  if [ -z "${browser_download_urls}" ]; then
    # in case of no browser_download_url in release, try to use the tag name
    # like google/brotli, only contain binary but not source code
    ret_ver="$([ -n "${version}" ] && echo "${version}" || echo "master")"
    browser_download_urls="${tag_dl_url}/${ret_ver}.tar.gz"
  fi

  #suffixes="tar.zst tar.zstd tar.xz tar.bz2 tar.gz tgz"
  suffixes="tar.xz tar.bz2 tar.gz tgz"
  for suffix in ${suffixes}; do
    browser_download_url=$(printf "%s" "${browser_download_urls}" \
      | sed -En '/'"${suffix}"'$/p' \
      | sed '$!d' \
      || true)
    [ -n "$browser_download_url" ] && break
  done

  URL="${browser_download_url}"
  VER="${ret_ver}"
}

function download_and_extract() {
  local url pkg uncompressed_flag

  pkg="${1}"
  url="${2}"
  strip_level="${3:-1}"

  # googlesource.com doesn't contain root folder
  if [[ "${url}" =~ "googlesource.com/" ]]; then
    strip_level=0
  fi

  case "${url}" in
    *.tar.gz|*.tgz) uncompressed_flag=z ;;
    *.tar.xz) uncompressed_flag=J ;;
    *.tar.bz2) uncompressed_flag=j ;;
    *.tar.zst|*.tar.zstd) uncompressed_flag="-I zstd -" ;;
    *) uncompressed_flag= ;;
  esac

  rm -rf "${pkg}" && mkdir -p "${pkg}" &&
    curl -fsSL "${url}" | tar ${uncompressed_flag}xf - --strip-components=${strip_level} -C "${pkg}"
}

# zlib
function build_zlib() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/madler/zlib"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  # cmake still not support for static library yet (1.3.1)
  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --static
  make -j$(nproc) install
}

# brotli
function build_brotli() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/google/brotli"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBROTLI_DISABLE_TESTS=ON
  cmake --build . --parallel $(nproc) --target install
  sed -i -E '/Libs:/ s#-lbrotlidec$#-lbrotlidec -lbrotlicommon#' "${ROOT_DIR}/lib/pkgconfig/libbrotlidec.pc"
  sed -i -E '/Libs:/ s#-lbrotlienc$#-lbrotlienc -lbrotlicommon#' "${ROOT_DIR}/lib/pkgconfig/libbrotlienc.pc"
}

# libbz2
function build_libbz2() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://gitlab.com/federicomenaquintero/bzip2"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED_LIB=OFF -DENABLE_STATIC_LIB=ON \
    -DENABLE_LIB_ONLY=ON -DENABLE_DEBUG=OFF -DENABLE_APP=OFF -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF
  cmake --build . --parallel $(nproc) --target install
  ln -sf libbz2_static.a "${ROOT_DIR}/lib/libbz2.a"
}

# libpng
function build_libpng() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/pnggroup/libpng" "v1.6.46"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DPNG_SHARED=OFF -DPNG_STATIC=ON \
    -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DZLIB_ROOT="${ROOT_DIR}"
  cmake --build . --parallel $(nproc) --target install
}

# graphite
function build_graphite() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/silnrsi/graphite"
  # rename graphite2-minimal-1.3.14.tgz -> graphite2-1.3.14.tgz
  URL=$(echo "${URL}" | sed -E 's#graphite2-minimal-([0-9.]+)#graphite2-\1#')
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF
  cmake --build . --parallel $(nproc) --target install
}

# freetype
function build_freetype() {
  local harfbuzz="${1:-disabled}"
  change_dir "${TMP_DIR}"
  url_from_git_server "https://gitlab.freedesktop.org/freetype/freetype"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${PKG}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Dtests=disabled -Dharfbuzz=${harfbuzz}
  ninja -j$(nproc) install
}

# harfbuzz
function build_harfbuzz() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/harfbuzz/harfbuzz"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${PKG}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Dtests=disabled -Dutilities=disabled -Dgraphite2=enabled -Dfreetype=enabled
  ninja -j$(nproc) install
}

# libunibreak
function build_libunibreak() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/adah1972/libunibreak"
  download_and_extract "${PKG}" "${URL}"
  pushd "${PKG}" > /dev/null && autoreconf -fi && popd > /dev/null
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static
  make -j$(nproc) install
}

# libass
function build_libass() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/libass/libass"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${PKG}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Dtest=false -Dfontconfig=enabled -Dlibunibreak=enabled
  ninja -j$(nproc) install
}

# dav1d
function build_dav1d() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://code.videolan.org/videolan/dav1d"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${PKG}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Denable_tools=false -Denable_tests=false
  ninja -j$(nproc) install
}

# aom
function build_aom() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://aomedia.googlesource.com/aom"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_DOCS=OFF -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF
  cmake --build . --parallel $(nproc) --target install
}

# svt-av1
function build_svtav1() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://gitlab.com/AOMediaCodec/SVT-AV1"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  # With LTO enabled, Clang generates LLVM IR bitcode rather than native object files
  [[ "${WITHOUT_CLANG}" != "yes" ]] && _LTO="OFF" || _LTO="ON"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF -DBUILD_APPS=OFF -DSVT_AV1_LTO=${_LTO}
  cmake --build . --parallel $(nproc) --target install
}

# vmaf
function build_vmaf() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/Netflix/vmaf"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${PKG}/lib${PKG}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Denable_tests=false -Denable_docs=false
  ninja -j$(nproc) install
}

# libvpx
function build_libvpx() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://chromium.googlesource.com/webm/libvpx"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static \
    --disable-examples --disable-unit-tests --enable-vp9-highbitdepth --as=yasm
  make -j$(nproc) install
}

# libx265
function build_libx265() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://bitbucket.org/multicoreware/x265_git"
  download_and_extract "${PKG}" "${URL}"

  #https://github.com/rdp/ffmpeg-windows-build-helpers/issues/185

  ## first stage for 12-bit
  change_clean_dir "${PKG}_build_12bits"
  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}/source" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DSTATIC_LINK_CRT=ON -DEXPORT_C_API=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12=ON
  cmake --build . --parallel $(nproc) && cd ..

  ## second stage for 10-bit
  change_clean_dir "${PKG}_build_10bits"
  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}/source" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED=OFF -DENABLE_CLI=OFF -DSTATIC_LINK_CRT=ON -DEXPORT_C_API=OFF -DHIGH_BIT_DEPTH=ON -DMAIN12=OFF
  cmake --build . --parallel $(nproc) && cd ..

  # final stage to merge 12-bit and 10-bit
  change_clean_dir "${PKG}_build"
  ln -sf "../${PKG}_build_12bits/libx265.a" libx265_main12.a
  ln -sf "../${PKG}_build_10bits/libx265.a" libx265_main10.a
  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}/source" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
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

  ## Remove -lstdc++ -lgcc -lgcc_s from x265.pc to honor --static-libstdc++ and --static-libgcc
  sed -i -E '/Libs\.private:/ s#(-lstdc\+\+)|(-lgcc)|(-lgcc_s)##g' "${ROOT_DIR}/lib/pkgconfig/x265.pc"
}

# nv-codec-headers
function build_nv-codec-headers() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/FFmpeg/nv-codec-headers"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" make -C "../${PKG}" \
    PREFIX="${ROOT_DIR}" install
}

# boringssl
function build_boringssl() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://boringssl.googlesource.com/boringssl" "chromium-stable"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  [[ "${WITHOUT_CLANG}" != "yes" ]] && _CXX_FLAGS="-std=c++17 -stdlib=libc++" || _CXX_FLAGS=""

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_CXX_FLAGS="${_CXX_FLAGS}" \
    -DBUILD_SHARED_LIBS=OFF
  cmake --build . --parallel $(nproc) --target install
}

# openssl
function build_openssl() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/openssl/openssl"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  "../${PKG}/Configure" --prefix="${ROOT_DIR}" --libdir="lib" \
    enable-tls1_3 enable-ktls \
    no-shared no-autoload-config no-engine no-dso no-tests no-legacy no-deprecated
  make -j$(nproc)
  make install_sw
}

function build_ffmpeg() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/FFmpeg/FFmpeg" "master"
  download_and_extract "${PKG}" "${URL}"

  sed -Ei \
    -e '/^[[:space:]]*int hide_banner = 0;$/ s#= 0#= 1#' \
    -e '/^[[:space:]]*hide_banner = 1;$/ s#= 1#= 0#' "./${PKG}/fftools/cmdutils.c"
  #patch -p1 < <(curl -fsSL https://gitlab.com/AOMediaCodec/SVT-AV1/-/raw/master/.gitlab/workflows/linux/ffmpeg_n7_fix.patch)

  change_clean_dir "${PKG}_build"
#   --ld="c++" --extra-ldflags="-static-libgcc -static-libstdc++ -L${ROOT_DIR}/lib" \
#  --cc="clang" --cxx="clang++" --ar="llvm-ar" --ranlib="llvm-ranlib" --ld="clang++"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --pkg-config-flags="--static" --disable-shared --enable-static \
    --enable-gpl --enable-nonfree --enable-version3 \
    --extra-version=$(date +%Y%m%d) \
    --disable-doc --enable-pic \
    --extra-cflags="-I${ROOT_DIR}/include" \
    --ld="${CXX}" --extra-ldflags="-static-libgcc -static-libstdc++ -L${ROOT_DIR}/lib" \
    --enable-libass \
    --enable-libaom \
    --enable-libdav1d \
    --enable-libfdk-aac \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-cross-compile \
    --enable-libsvtav1 \
    --disable-cuda-llvm --enable-ffnvcodec \
    --enable-libvmaf \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    --enable-openssl
  make -j$(nproc)

  cp -av "./ffmpeg" "${WORKING_PATH}"/ffmpeg && strip --strip-all "${WORKING_PATH}"/ffmpeg
  cp -av "./ffprobe" "${WORKING_PATH}"/ffprobe && strip --strip-all "${WORKING_PATH}"/ffprobe
}

function main() {
  export WITHOUT_BORINGSSL="${WITHOUT_BORINGSSL:-no}"
  export WITHOUT_CLANG="${WITHOUT_CLANG:-no}"

  init_env;

  (build_zlib && build_libpng) &
  build_libbz2 &
  build_brotli &
  wait

  (build_graphite && build_freetype && build_harfbuzz && build_freetype "enabled") &
  build_libunibreak &
  wait
  build_libass

  build_dav1d &
  build_aom &
  build_svtav1 &
  build_vmaf &
  build_libvpx &
  build_libx265 &
  build_nv-codec-headers &

  if [[ "${WITHOUT_BORINGSSL}" != "yes" ]]; then
    build_boringssl &
  else
    build_openssl &
  fi

  wait
  build_ffmpeg
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
  main "$@";
fi
