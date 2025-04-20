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

# ---- APT SOURCE CONFIGURATION ----
# Only modify sources if running in GitHub Actions to ensure clean environment
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  echo "👉 [GitHub Actions] Backing up /etc/apt/sources.list..."
  $SUDO cp /etc/apt/sources.list /etc/apt/sources.list.bak

  # Remove any existing secondary lists first to avoid duplicates/conflicts
  echo "👉 [GitHub Actions] Removing existing *.list files from /etc/apt/sources.list.d/"
  $SUDO rm -f /etc/apt/sources.list.d/*.list

  # Overwrite /etc/apt/sources.list with official amd64 Noble repositories
  echo "👉 [GitHub Actions] Writing official Ubuntu 24.04 (noble) amd64 sources to /etc/apt/sources.list"
  # Use cat and pipe to sudo tee to avoid permission issues with redirection
  cat <<EOF | $SUDO tee /etc/apt/sources.list >/dev/null
# Ubuntu 24.04 "Noble" AMD64 repositories
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-backports main universe multiverse
EOF
else
  echo "👉 Skipping APT source modification (not running in GitHub Actions)"
fi

# ---- PREPARE APT SOURCES FOR MULTIARCH ----
echo "👉 Setting up multiarch sources (dpkg --add-architecture)..."
$SUDO dpkg --add-architecture arm64
$SUDO dpkg --add-architecture armhf

# Ubuntu Ports for arm64 and armhf
echo "👉 Configuring ARM64/ARMHF ports repository..."
cat <<EOF | $SUDO tee /etc/apt/sources.list.d/ubuntu-ports-noble.list >/dev/null
# Ubuntu 24.04 "Noble" ports for ARM arches
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble main universe multiverse
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble-security main universe multiverse
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble-updates main universe multiverse
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble-backports main universe multiverse
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