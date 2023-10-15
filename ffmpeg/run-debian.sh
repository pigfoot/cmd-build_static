#!/usr/bin/env bash

set -ex

builder=$(buildah from "docker.io/library/debian:latest")
buildah config --workingdir '/io' --env DEBIAN_FRONTEND="noninteractive" --env TERM="xterm-256color" "${builder}"
buildah run "${builder}" sh -c 'echo "export TERM=xterm-256color" >> ~/.bashrc'
buildah run "${builder}" sh -c 'echo "deb http://deb.debian.org/debian $(sed -En "/^VERSION_CODENAME/ s#.*=##p" /etc/os-release) contrib non-free non-free-firmware" > /etc/apt/sources.list'
buildah run "${builder}" sh -c 'apt update -qq && apt upgrade -qq -y && apt install -qq -y apt-utils'
buildah run "${builder}" sh -c 'apt install -qq -y build-essential cmake curl git \
    libfdk-aac-dev libmp3lame-dev libopus-dev libssl-dev libswscale-dev \
    libvorbis-dev libx264-dev libnuma-dev libass-dev zlib1g-dev \
    meson nasm pkg-config yasm > /dev/null'
buildah run "${builder}" sh -c 'apt clean'
buildah run -v "$(pwd):/io" "${builder}" sh -c './build-ffmpeg.sh'
buildah rm "${builder}"
