#!/usr/bin/env bash

set -ex

builder=$(buildah from "docker.io/library/debian:${CNTR_VER:-stable-slim}")
buildah config --workingdir '/io' --env TERM="xterm-256color" "${builder}"
buildah run "${builder}" sh -c 'echo "\nexport TERM=xterm-256color\nexport PATH=\"\$HOME/.local/bin:\$PATH\"" >> ~/.profile'
buildah run "${builder}" sh -c 'echo "deb http://deb.debian.org/debian $(sed -En "/^VERSION_CODENAME/ s#.*=##p" /etc/os-release) contrib non-free non-free-firmware" > /etc/apt/sources.list'
buildah run "${builder}" sh -c 'apt update -qq && apt upgrade -qq -y && apt install -qq -y apt-utils whiptail'
buildah run "${builder}" sh -c 'DEBIAN_FRONTEND=noninteractive apt install -qq -y \
  build-essential autoconf libtool binutils pkg-config cmake ninja-build python3-minimal \
  curl nasm yasm xxd git
  > /dev/null'
buildah run "${builder}" sh -lc 'curl -fsSL https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh \
  && uv tool install meson'
[[ "${WITHOUT_CLANG}" != "yes" ]] && buildah run "${builder}" sh -c 'CLANG_VER=$(apt-cache search clang | sed -En "/^clang-[0-9]+/ s#^clang-([0-9]+)[[:space:]].*#\1#p" | sort | sed "\$!d") \
  && apt install -qq -y clang-"${CLANG_VER}" libc++-"${CLANG_VER}"-dev \
  && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-"${CLANG_VER}" 20 \
    --slave /usr/bin/clang++ clang++ /usr/bin/clang++-"${CLANG_VER}" \
  && update-alternatives --install /usr/bin/llvm-config llvm-config /usr/bin/llvm-config-"${CLANG_VER}" 20 \
    --slave /usr/bin/llvm-ar llvm-ar /usr/bin/llvm-ar-"${CLANG_VER}" \
    --slave /usr/bin/llvm-as llvm-as /usr/bin/llvm-as-"${CLANG_VER}" \
    --slave /usr/bin/llvm-link llvm-link /usr/bin/llvm-link-"${CLANG_VER}" \
    --slave /usr/bin/llvm-nm llvm-nm /usr/bin/llvm-nm-"${CLANG_VER}" \
    --slave /usr/bin/llvm-objdump llvm-objdump /usr/bin/llvm-objdump-"${CLANG_VER}" \
    --slave /usr/bin/llvm-ranlib llvm-ranlib /usr/bin/llvm-ranlib-"${CLANG_VER}" \
  > /dev/null'
buildah run "${builder}" sh -c 'apt clean'
buildah run -v "$(pwd):/io" "${builder}" sh -lc ' \
  GITHUB_TOKEN_READ="'"${GITHUB_TOKEN_READ}"'" \
  WITHOUT_BORINGSSL="'"${WITHOUT_BORINGSSL}"'" \
  WITHOUT_CLANG="'"${WITHOUT_CLANG}"'" \
  EXTRA_CFLAGS="'"${EXTRA_CFLAGS}"'" \
  ./build-ffmpeg.sh'
buildah rm "${builder}"
