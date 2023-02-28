#!/usr/bin/env bash

set -ex

builder=$(buildah from "docker.io/library/ubuntu:latest")
buildah config --workingdir '/io' "${builder}"
buildah run "${builder}" sh -c 'export DEBIAN_FRONTEND=noninteractive'
buildah run "${builder}" sh -c 'apt update -qq && apt upgrade -qq -y > /dev/null'
buildah run "${builder}" sh -c 'apt install -qq -y --no-install-recommends --no-install-suggests \
  ca-certificates build-essential gcc-multilib g++-multilib curl git apt-utils \
  autoconf automake curl git'
buildah run "${builder}" sh -c 'apt clean'
buildah run -v "$(pwd):/io" "${builder}" sh -c './build-openssh.sh x86'
buildah rm "${builder}"
