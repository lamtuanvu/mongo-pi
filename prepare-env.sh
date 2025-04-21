#!/bin/bash

# Script to prepare the build environment for MongoDB cross-compilation
# Installs dependencies and configures APT.

set -euo pipefail

# ---- CONFIGURATION ----
COMPILER_VERSION=12 # Using GCC 12 from Debian 12 base
# PYTHON_VERSION removed - using system python3

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
# Keep core tools + cross-compilers. Removed pyenv/python build dependencies.
$SUDO apt-get install -y \
  git curl build-essential \
  gcc-${COMPILER_VERSION}-aarch64-linux-gnu g++-${COMPILER_VERSION}-aarch64-linux-gnu \
  gcc-${COMPILER_VERSION}-arm-linux-gnueabihf g++-${COMPILER_VERSION}-arm-linux-gnueabihf

# ---- PYENV/PYTHON INSTALL REMOVED ----

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