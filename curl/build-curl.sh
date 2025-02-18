#!/usr/bin/env bash

set -ex

function init_env() {
  export ROOT_DIR="${ROOTDIR:-/sysroot}"
  export WORKING_PATH="${WORKING_PATH:-$(pwd)}"
  export TMP_DIR="${TMP_DIR:-/tmp}"

  if [[ "${WITHOUT_CLANG}" != "yes" ]]; then
    export CC="${CC:clang}"
    export CXX="${CXX:clang++}"
  else
    export CC="${CC:gcc}"
    export CXX="${CXX:g++}"
  fi
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

# zstd
function build_zstd() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/facebook/zstd"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}/build/cmake" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_LEGACY_SUPPORT=OFF -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF
  cmake --build . --parallel $(nproc) --target install
}

# libunistring
function build_libunistring() {
  change_dir "${TMP_DIR}"
  PKG="libunistring"
  URL="https://mirrors.kernel.org/gnu/libunistring/libunistring-latest.tar.gz"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH=${ROOT_DIR}/lib/pkgconfig "../${PKG}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static \
    --disable-rpath --disable-dependency-tracking --enable-year2038
  make -j$(nproc) install
}

# libidn2
function build_libidn2() {
  change_dir "${TMP_DIR}"
  PKG="libidn2"
  URL="https://mirrors.kernel.org/gnu/libidn/libidn2-latest.tar.gz"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static \
    --with-libunistring-prefix="${ROOT_DIR}"
  make -j$(nproc) install
  sed -i -E '/Libs:/ s#-lidn2$#-lidn2 -lunistring#' "${ROOT_DIR}/lib/pkgconfig/libidn2.pc"
}

# libpsl
function build_libpsl() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/rockdaboot/libpsl"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${PKG}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Dbuiltin=true -Druntime=no -Dtests=false
  ninja -j$(nproc) install
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

  # no-deprecated would cause TLS-SRP ntlm disable in curl
  # [optional] enable-weak-ssl-ciphers enable-ssl3 enable-ssl3-method
  "../${PKG}/Configure" --prefix="${ROOT_DIR}" --libdir="lib" \
    enable-tls1_3 enable-ktls \
    no-shared no-autoload-config no-engine no-dso no-tests no-legacy
  make -j$(nproc)
  make install_sw
}

# ngtcp2
function build_ngtcp2() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/ngtcp2/ngtcp2"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  BORINGSSL_LIBS="-L/sysroot/lib -lssl -lcrypto" \
    BORINGSSL_CFLAGS="-I/sysroot/include" \
    PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static \
    --with-boringssl
  make -j$(nproc) install
}

# nghttp3
function build_nghttp3() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/ngtcp2/nghttp3"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED_LIB=OFF -DENABLE_STATIC_LIB=ON \
    -DBUILD_TESTING=OFF -DENABLE_LIB_ONLY=ON
  cmake --build . --parallel $(nproc) --target install
}

# nghttp2
function build_nghttp2() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/nghttp2/nghttp2"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DENABLE_DOC=OFF -DENABLE_HTTP3=OFF -DENABLE_LIB_ONLY=ON
  cmake --build . --parallel $(nproc) --target install
}

# libssh2
function build_libssh2() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/libssh2/libssh2"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DCRYPTO_BACKEND=OpenSSL -DLIBSSH2_NO_DEPRECATED=ON
  cmake --build . --parallel $(nproc) --target install
}

function build_curl() {
  change_dir "${TMP_DIR}"
  url_from_git_server "https://github.com/curl/curl"
  download_and_extract "${PKG}" "${URL}"
  change_clean_dir "${PKG}_build"

  ## cmake still cannot build static library for curl with boringssl && libc++
  #LDFLAGS="-stdlib=libc++ -static-libgcc -static-libstdc++ -lc++" \
  #  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${PKG}" \
  #  -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  #  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_STATIC_CURL=ON -DOPENSSL_USE_STATIC_LIBS=ON\
  #  -DUSE_ECH=ON -DCURL_USE_LIBPSL=OFF
  #cmake --build . --parallel $(nproc) -v

  if [[ "${WITHOUT_CLANG}" != "yes" ]]; then
    _LIBS="-l:libc++.a"
    _LDFLAGS="-stdlib=libc++ -static-libgcc -static-libstdc++"
  else
    _LIBS="-l:libstdc++.a"
    _LDFLAGS="-static-libgcc -static-libstdc++"
  fi

  if [[ "${WITHOUT_BORINGSSL}" != "yes" ]]; then
    _ECH="--enable-ech"
    _QUIC="--without-openssl-quic"
    _NGTCP2="--with-ngtcp2"
  else
    _ECH="--disable-ech"
    _QUIC="--with-openssl-quic"
    _NGTCP2="--without-ngtcp2"
  fi

  LIBS="${_LIBS}" LDFLAGS="${_LDFLAGS}" \
    PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${PKG}/configure" \
    --disable-shared --enable-static \
    --disable-docs \
    --enable-alt-svc \
    --enable-basic-auth \
    --enable-bearer-auth \
    --enable-digest-auth \
    --enable-kerberos-auth \
    --enable-negotiate-auth \
    --enable-aws \
    --enable-dict \
    "${_ECH}" \
    "${_NGTCP2}" \
    --enable-file \
    --enable-ftp \
    --disable-gopher \
    --enable-hsts \
    --enable-http \
    --enable-imap \
    --enable-ntlm \
    --enable-pop3 \
    --enable-rt \
    --enable-rtsp \
    --with-libssh2 \
    --enable-smb \
    --enable-smtp \
    --enable-telnet \
    --enable-tftp \
    --enable-tls-srp \
    --disable-ares \
    --enable-cookies \
    --enable-dateparse \
    --enable-dnsshuffle \
    --enable-doh \
    --enable-symbol-hiding \
    --enable-http-auth \
    --enable-ipv6 \
    --enable-largefile \
    --enable-manual \
    --enable-mime \
    --enable-netrc \
    --enable-progress-meter \
    --enable-proxy \
    --enable-socketpair \
    --disable-sspi \
    --enable-threaded-resolver \
    --disable-versioned-symbols \
    --without-amissl \
    --without-bearssl \
    --with-brotli \
    --with-nghttp2 \
    --without-libgsasl \
    --without-msh3 \
    --with-nghttp3 \
    "${_QUIC}" \
    --without-quiche \
    --without-schannel \
    --without-secure-transport \
    --without-test-caddy \
    --without-test-httpd \
    --without-test-nghttpx \
    --enable-websockets \
    --with-libidn2 \
    --without-wolfssl \
    --with-zlib \
    --with-zstd \
    --with-ssl=${ROOT_DIR} \
    --with-default-ssl-backend=openssl
  make -j$(nproc)

  cp -av "./src/curl" "${WORKING_PATH}"/curl && strip --strip-all "${WORKING_PATH}"/curl
}

function main() {
  export WITHOUT_BORINGSSL="${WITHOUT_BORINGSSL:-no}"
  export WITHOUT_CLANG="${WITHOUT_CLANG:-no}"

  init_env;

  (build_libunistring && build_libidn2) &
  build_libpsl &

  if [[ "${WITHOUT_BORINGSSL}" != "yes" ]]; then
    (build_boringssl && build_nghttp3 && build_ngtcp2 && build_nghttp2 && build_libssh2) &
  else
    (build_openssl && build_nghttp3 && build_nghttp2 && build_libssh2) &
  fi

  build_zlib &
  build_brotli &
  build_zstd &
  wait

  build_curl
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
  main "$@";
fi
