#!/bin/bash

# Script to prepare the build environment for MongoDB cross-compilation
# Installs dependencies, pyenv, Python, and configures APT.

set -euo pipefail

# ---- CONFIGURATION ----
COMPILER_VERSION=13
PYTHON_VERSION="3.11.5"

# Determine if sudo is needed
if [[ "$(id -u)" == "0" ]]; then
  SUDO=""
  echo "Running as root, sudo not required."
else
  SUDO="sudo"
  echo "Not running as root, using sudo."
fi

# ---- INSTALL BASE DEPENDENCIES ----
echo "👉 Installing base build dependencies via APT..."
$SUDO apt-get update
# Dependencies for pyenv and Python build, plus basic tools
$SUDO apt-get install -y \
  git curl build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev llvm libncurses5-dev libncursesw5-dev \
  xz-utils tk-dev libffi-dev liblzma-dev python3-openssl \
  gcc-${COMPILER_VERSION}-aarch64-linux-gnu g++-${COMPILER_VERSION}-aarch64-linux-gnu \
  gcc-${COMPILER_VERSION}-arm-linux-gnueabihf g++-${COMPILER_VERSION}-arm-linux-gnueabihf

# ---- INSTALL PYENV ----
if [[ ! -d "$HOME/.pyenv" ]]; then
  echo "👉 Installing pyenv..."
  curl https://pyenv.run | bash
else
  echo "👉 pyenv already installed."
fi

# ---- INITIALIZE PYENV (for subsequent steps in this script) ----
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null; then
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
else
  echo "ERROR: pyenv command not found after installation attempt."
  exit 1
fi

# ---- INSTALL REQUIRED PYTHON ----
if ! pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
  echo "👉 Installing Python $PYTHON_VERSION via pyenv..."
  pyenv install "$PYTHON_VERSION"
else
  echo "👉 Python $PYTHON_VERSION already installed via pyenv."
fi

echo "👉 Configuring AMD64 archive..."
sudo tee /etc/apt/sources.list.d/ubuntu-amd64-noble.list >/dev/null <<EOF
# Ubuntu 24.04 "Noble" AMD64 repositories
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-backports main universe multiverse
EOF

# ---- PREPARE APT SOURCES FOR MULTIARCH ----
echo "👉 Setting up multiarch sources (dpkg --add-architecture)..."
$SUDO dpkg --add-architecture arm64
$SUDO dpkg --add-architecture armhf

# ---- CONFIGURE DEBIAN REPOS FOR ARM ----
echo "👉 Configuring Debian 12 (Bookworm) ARM repositories..."
# You might need to adjust the URL if debian.org has specific ports URLs
# Or rely on the main archive if it supports multiarch correctly
sudo tee /etc/apt/sources.list.d/debian-bookworm-arm.list >/dev/null <<EOF
# Debian 12 "Bookworm" for ARM arches
deb [arch=arm64,armhf] http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb [arch=arm64,armhf] http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb [arch=arm64,armhf] http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

# MongoDB APT Repo
echo "👉 Adding MongoDB repository key..."
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc |
  $SUDO gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg

echo "👉 Adding MongoDB repository source list..."
cat <<EOF | $SUDO tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
# MongoDB 8.0 repository
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main
EOF

# ---- FINAL APT UPDATE & INSTALL DEV LIBS ----
echo "👉 Updating APT listings after source changes..."
$SUDO apt-get update

echo "👉 Installing multiarch development libraries (libssl-dev, etc.)..."
# Install both sets, let apt handle dependencies. Simpler than conditional.
$SUDO apt-get install -y \
  libssl-dev:armhf libcurl4-openssl-dev:armhf liblzma-dev:armhf \
  libssl-dev:arm64 libcurl4-openssl-dev:arm64 liblzma-dev:arm64

echo "✅ Environment preparation complete." 