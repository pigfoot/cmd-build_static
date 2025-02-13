#!/usr/bin/env bash

set -ex

builder=$(buildah from "docker.io/library/debian:stable-slim")
buildah config --workingdir '/io' --env TERM="xterm-256color" "${builder}"
buildah run "${builder}" sh -c 'echo "export TERM=xterm-256color" >> ~/.bashrc'
buildah run "${builder}" sh -c 'echo "deb http://deb.debian.org/debian $(sed -En "/^VERSION_CODENAME/ s#.*=##p" /etc/os-release) contrib non-free non-free-firmware" > /etc/apt/sources.list'
buildah run "${builder}" sh -c 'apt update -qq && apt upgrade -qq -y && apt install -qq -y apt-utils whiptail'
buildah run "${builder}" sh -c 'DEBIAN_FRONTEND=noninteractive apt install -qq -y \
    clang automake autoconf libtool binutils pkg-config cmake meson \
    curl
    > /dev/null'
buildah run "${builder}" sh -c 'apt clean'
buildah run -v "$(pwd):/io" "${builder}" sh -c './build-curl.sh'
buildah rm "${builder}"
