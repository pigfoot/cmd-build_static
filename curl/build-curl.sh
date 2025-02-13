#!/usr/bin/env bash

set -ex

ROOT_DIR="${ROOTDIR:-/sysroot}"
WORKING_PATH="${WORKING_PATH:-$(pwd)}"
TMP_DIR="${TMP_DIR:-/tmp}"

export CC="${CC:-clang}"
export CXX="${CC:-clang++}"

function change_dir() {
  local dir="${1}"
  mkdir -p "${dir}"
  pushd "${dir}" > /dev/null
}

function change_clean_dir() {
  local dir="${1}"
  rm -rf "${dir}" && change_dir "${dir}"
}

function _get_github() {
  local release_file auth_header status_code size_of

  local repo=$1
  release_file="github-${repo#*/}.json"

  # GitHub API has a limit of 60 requests per hour, cache the results.

  # get token from github settings
  auth_header=""
  set +o xtrace
  if [ -n "${TOKEN_READ}" ]; then
    auth_header="token ${TOKEN_READ}"
  fi

  status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/releases" \
    -w "%{http_code}" \
    -o "${release_file}" \
    -H "Authorization: ${auth_header}" \
    -s -L --compressed)

  set -o xtrace
  size_of=$(stat -c "%s" "${release_file}")
  if [ "${size_of}" -lt 200 ] || [ "${status_code}" -ne 200 ]; then
    echo "The release of ${repo} is empty, download tags instead."
    set +o xtrace
    status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/tags" \
      -w "%{http_code}" \
      -o "${release_file}" \
      -H "Authorization: ${auth_header}" \
      -s -L --compressed)
    set -o xtrace
  fi
  auth_header=""

  if [ "${status_code}" -ne 200 ]; then
    echo "ERROR. Failed to download ${repo} releases from GitHub, status code: ${status_code}"
    cat "${release_file}"
    exit 1
  fi
}

function _get_latest_tag() {
  set +o xtrace

  local ver_exp content tag_verion_map tag_name
  local version="${1}"
  local tag_type="release"
  content=$(cat -)

  ## search releases result from github

  ## build a pair of version numbers as tagname__major.minor.patch
  ## for example: curl-8_12_0__8.12.0 or v1.3__1.3. (without patch)
  ## ver_exp="([^0-9]*([0-9]+)[^0-9]([0-9]+)([^0-9]([0-9]+))?)"
  ver_exp="(([^0-9]*|[^0-9]+[0-9][^0-9])([0-9]+)[^0-9]([0-9]+)([^0-9]([0-9]+))?)"
  tag_verion_map=$(echo "${content}" \
    | sed -En '/"tag_name":/ s#.*: "'"${ver_exp}"'",#\1__\3.\4.\6#p'
  )
  if [ -n "${tag_verion_map}" ]; then
    tag_type="release"
  else
    ## search tag result from github
    tag_verion_map=$(echo "${content}" \
      | sed -En '/"name":/ s#.*: "'"${ver_exp}"'",#\1__\3.\4.\6#p'
    )

    if [ -n "${tag_verion_map}" ]; then
      tag_type="tag"
    else
      ## search tag result from git tag
      tag_verion_map=$(echo "${content}" \
        | sed -En 's#'"${ver_exp}"'#\1__\3.\4.\6#p'
      )

      if [ -n "${tag_verion_map}" ]; then
        tag_type="git"
      else
        echo ",,"
        return
      fi
    fi
  fi

  if [ -z "${version}" ]; then
    version=$(echo "${tag_verion_map%x}" \
      | sed 's#.*__##' \
      | sort -t. -k 1,1n -k 2,2n -k 3,3n \
      | sed '$!d'
    )
  fi

  tag_name="$(echo "${tag_verion_map%x}" | sed -En '/'"${version}"'/ s#__.*##p')"
  echo "${tag_type},${tag_name},${version}"

  set -o xtrace
}

function url_from_github() {
  local browser_download_urls browser_download_url url tag_type tag_name version release_file
  repo="${1}"
  version="${2}"
  release_file="github-${repo#*/}.json"

  if [ ! -f "${release_file}" ]; then
    _get_github "${repo}"
  fi

  result=$(cat "${release_file}" | _get_latest_tag "${version}")
  tag_type=$(echo "$result" | cut -d ',' -f 1)
  tag_name=$(echo "$result" | cut -d ',' -f 2)
  version=$(echo "$result" | cut -d ',' -f 3)

  if [ -z "${tag_name}" ]; then
    tag_name="${version}"
  fi

  if [ "${tag_type}" = "release" ]; then
    browser_download_urls=$(cat "${release_file}" \
      | sed -En '/"browser_download_url":/ s#.*"browser_download_url": "([^"]+(\.gz|\.tgz|\.bz2|\.xz|\.zstd|\.zst))".*#\1#p' \
      | sed -En '/\/'"${tag_name}"'\//p' \
      || true)
  else
    browser_download_urls="https://github.com/${repo}/archive/${tag_name}.tar.gz"
  fi

  if [ -n "${browser_download_urls}" ]; then
    suffixes="tar.gz tgz"
    for suffix in ${suffixes}; do
      browser_download_url=$(printf "%s" "${browser_download_urls}" \
        | sed -En '/'"${suffix}"'$/p' \
        | sed '$!d' \
        || true)
      [ -n "$browser_download_url" ] && break
    done

    url=$(printf "%s" "${browser_download_url}")
  else
    # in case of no browser_download_url in release, try to use the tag name
    # like google/brotli, only contain binary but not source code
    url="https://github.com/${repo}/archive/${tag_name}.tar.gz"
  fi

  URL="${url}"
}

function download_and_extract() {
  local url pkg

  pkg="${1}"
  url="${2}"

  rm -rf "${pkg}" && mkdir -p "${pkg}" &&
    curl -fsSL "${url}" | tar zxf - --strip-components=1 -C "${pkg}"
}

# libunistring
function build_libunistring() {
  pkg="libunistring"
  change_dir "${TMP_DIR}"

  url="https://mirrors.kernel.org/gnu/libunistring/libunistring-latest.tar.gz"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH=${ROOT_DIR}/lib/pkgconfig "../${pkg}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static \
    --disable-rpath --disable-dependency-tracking --enable-year2038
  make -j$(nproc) install
}

# libidn2
function build_libidn2() {
  pkg="libidn2"
  change_dir "${TMP_DIR}"

  url="https://mirrors.kernel.org/gnu/libidn/libidn2-latest.tar.gz"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${pkg}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --disable-shared --enable-static \
    --with-libunistring-prefix="${ROOT_DIR}"
  make -j$(nproc) install
  sed -i -E '/Libs:/ s#-lidn2$#-lidn2 -lunistring#' "${ROOT_DIR}/lib/pkgconfig/libidn2.pc"
}

# libpsl
function build_libpsl() {
  repo_url="https://github.com/rockdaboot/libpsl"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" meson setup "../${pkg}" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --buildtype release --default-library=static \
    -Dbuiltin=true -Druntime=no -Dtests=false
  ninja -j$(nproc) install
}

# openssl
function build_openssl() {
  repo_url="https://github.com/openssl/openssl"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  # no-deprecated would cause TLS-SRP ntlm disable in curl
  # [optional] enable-weak-ssl-ciphers enable-ssl3 enable-ssl3-method
  "../${pkg}/Configure" --prefix="${ROOT_DIR}" --libdir="lib" \
    enable-tls1_3 enable-ktls \
    no-shared no-autoload-config no-engine no-dso no-tests no-legacy
  make -j$(nproc)
  make install_sw
}

# nghttp3
function build_nghttp3() {
  repo_url="https://github.com/ngtcp2/nghttp3"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${pkg}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DENABLE_SHARED_LIB=OFF -DENABLE_STATIC_LIB=ON \
    -DBUILD_TESTING=OFF -DENABLE_LIB_ONLY=ON
  cmake --build . --parallel $(nproc) --target install
}

# nghttp2
function build_nghttp2() {
  repo_url="https://github.com/nghttp2/nghttp2"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${pkg}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DENABLE_DOC=OFF -DENABLE_HTTP3=OFF -DENABLE_LIB_ONLY=ON
  cmake --build . --parallel $(nproc) --target install
}


# libssh2
function build_libssh2() {
  repo_url="https://github.com/libssh2/libssh2"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${pkg}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
    -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF -DCRYPTO_BACKEND=OpenSSL -DLIBSSH2_NO_DEPRECATED=ON
  cmake --build . --parallel $(nproc) --target install
}

# zlib
function build_zlib() {
  repo_url="https://github.com/madler/zlib"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  # cmake still not support for static library yet (1.3.1)
  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${pkg}/configure" \
    --prefix="${ROOT_DIR}" --libdir="${ROOT_DIR}/lib" --static
  make -j$(nproc) install
}

# brotli
function build_brotli() {
  repo_url="https://github.com/google/brotli"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${pkg}" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBROTLI_DISABLE_TESTS=ON
  cmake --build . --parallel $(nproc) --target install
  sed -i -E '/Libs:/ s#-lbrotlidec$#-lbrotlidec -lbrotlicommon#' "${ROOT_DIR}/lib/pkgconfig/libbrotlidec.pc"
  sed -i -E '/Libs:/ s#-lbrotlienc$#-lbrotlienc -lbrotlicommon#' "${ROOT_DIR}/lib/pkgconfig/libbrotlienc.pc"
}

# zstd
function build_zstd() {
  repo_url="https://github.com/facebook/zstd"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" cmake "../${pkg}/build/cmake" \
    -G"Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${ROOT_DIR}" -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_LEGACY_SUPPORT=OFF -DZSTD_BUILD_PROGRAMS=OFF -DZSTD_BUILD_TESTS=OFF
  cmake --build . --parallel $(nproc) --target install
}

function build_curl() {
  repo_url="https://github.com/curl/curl"
  repo=$(echo ${repo_url} | sed -En 's#.*//[^/]+/(.*)#\1#p' | sed 's/\.git$//')
  pkg=$(echo ${repo##*/})
  change_dir "${TMP_DIR}"

  url_from_github "${repo}" && url="${URL}"
  download_and_extract "${pkg}" "${url}"
  change_clean_dir "${pkg}_build"

  PKG_CONFIG_PATH="${ROOT_DIR}/lib/pkgconfig" "../${pkg}/configure" \
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
    --disable-ech \
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
    --with-openssl-quic \
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
    --with-ssl \
    --with-default-ssl-backend=openssl
  make -j$(nproc) install
}

function main() {
  (build_libunistring && build_libidn2) &
  build_libpsl &
  (build_openssl && build_nghttp3 && build_nghttp2 && build_libssh2) &
  build_zlib &
  build_brotli &
  build_zstd &
  wait

  build_curl

  change_dir "${WORKING_PATH}"
  cp -av /usr/local/bin/curl . && strip --strip-all ./curl
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi