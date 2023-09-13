#!/usr/bin/env bash

set -ex

builder=$(buildah from "docker.io/library/ubuntu:rolling")
buildah config --workingdir '/io' "${builder}"
buildah run "${builder}" sh -c 'sed -Ei "/[ -z \"$PS1\" ] && return/aexport DEBIAN_FRONTEND=noninteractive\nexport TERM=xterm-256color" ~/.bashrc'
buildah run "${builder}" sh -c 'apt update -qq && apt upgrade -qq -y'
buildah run "${builder}" sh -c 'apt install -qq -y build-essential cmake curl git \
    libfdk-aac-dev libmp3lame-dev libopus-dev libssl-dev libswscale-dev \
    libvorbis-dev libx264-dev libnuma-dev libass-dev libz-dev \
    meson nasm pkg-config yasm > /dev/null'
buildah run "${builder}" sh -c 'apt clean'
buildah run -v "$(pwd):/io" "${builder}" sh -c './build-ffmpeg.sh'
buildah rm "${builder}"
