#!/usr/bin/env bash

set -ex

builder=$(buildah from "docker.io/library/debian:latest")
buildah config --workingdir '/io' --env TERM="xterm-256color" "${builder}"
buildah run "${builder}" sh -c 'echo "export TERM=xterm-256color" >> ~/.bashrc'
buildah run "${builder}" sh -c 'echo "deb http://deb.debian.org/debian $(sed -En "/^VERSION_CODENAME/ s#.*=##p" /etc/os-release) contrib non-free non-free-firmware" > /etc/apt/sources.list'
buildah run "${builder}" sh -c 'apt update -qq && apt upgrade -qq -y && apt install -qq -y apt-utils whiptail'
buildah run "${builder}" sh -c 'DEBIAN_FRONTEND=noninteractive apt install -qq -y \
    build-essential clang autoconf libtool meson nasm pkg-config yasm \
    cmake curl git \
    libfribidi-dev libfontconfig-dev libnuma-dev \
    libvorbis-dev libmp3lame-dev libfdk-aac-dev libopus-dev libx264-dev libswscale-dev \
    > /dev/null'
buildah run "${builder}" sh -c 'apt clean'
buildah run -v "$(pwd):/io" "${builder}" sh -c './build-ffmpeg.sh'
buildah rm "${builder}"
