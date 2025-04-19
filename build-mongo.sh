#!/bin/bash

set -euo pipefail

# ---- CONFIGURATION ----
MONGO_VERSION="r7.0.4"
COMPILER_VERSION=13
PYTHON_VERSION="3.11.5"
BUILD_DIR="$HOME/mongo-build"
TARGET="$1"  # Options: pi5, pi0-2w, pizero

# ---- VALIDATE TARGET ----
if [[ "$TARGET" != "pi5" && "$TARGET" != "pi0-2w" && "$TARGET" != "pizero" ]]; then
  echo "Usage: $0 <pi5|pi0-2w|pizero>"
  exit 1
fi

# ---- INSTALL PYENV & DEPENDENCIES ----
echo "👉 Installing pyenv and build dependencies..."
sudo apt-get update
# Dependencies for pyenv and Python build
sudo apt-get install -y \
  git curl build-essential libssl-dev zlib1g-dev libbz2-dev \
  libreadline-dev libsqlite3-dev llvm libncurses5-dev libncursesw5-dev \
  xz-utils tk-dev libffi-dev liblzma-dev python3-openssl \
  gcc-${COMPILER_VERSION}-aarch64-linux-gnu g++-${COMPILER_VERSION}-aarch64-linux-gnu \
  gcc-${COMPILER_VERSION}-arm-linux-gnueabihf g++-${COMPILER_VERSION}-arm-linux-gnueabihf

# Install pyenv if not present
if [[ ! -d "$HOME/.pyenv" ]]; then
  curl https://pyenv.run | bash
fi
# Initialize pyenv in script
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv >/dev/null; then
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
fi

# Install required Python
if ! pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
  pyenv install "$PYTHON_VERSION"
fi
# Use Python locally for this build directory
pyenv shell "$PYTHON_VERSION"

# ---- BACKUP & CLEAN EXISTING SOURCES ----
# Only modify sources if running in GitHub Actions to ensure clean environment
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  echo "👉 [GitHub Actions] Backing up /etc/apt/sources.list..."
  sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

  # Remove any existing secondary lists first to avoid duplicates/conflicts
  echo "👉 [GitHub Actions] Removing existing *.list files from /etc/apt/sources.list.d/"
  sudo rm -f /etc/apt/sources.list.d/*.list

  # Overwrite /etc/apt/sources.list with official amd64 Noble repositories
  echo "👉 [GitHub Actions] Writing official Ubuntu 24.04 (noble) amd64 sources to /etc/apt/sources.list"
  sudo tee /etc/apt/sources.list > /dev/null <<EOF
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
echo "👉 Setting up multiarch sources..."
sudo dpkg --add-architecture arm64
sudo dpkg --add-architecture armhf

# Ubuntu AMD64 Main Archive (restrict to amd64 only)
echo "👉 Configuring AMD64 archive..."
sudo tee /etc/apt/sources.list.d/ubuntu-amd64-noble.list > /dev/null <<EOF
# Ubuntu 24.04 "Noble" AMD64 repositories
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-backports main universe multiverse
EOF

# Ubuntu Ports for arm64 and armhf
echo "👉 Configuring ARM64/ARMHF ports..."
sudo tee /etc/apt/sources.list.d/ubuntu-ports-noble.list > /dev/null <<EOF
# Ubuntu 24.04 "Noble" ports for ARM arches
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble main universe multiverse
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble-security main universe multiverse
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble-updates main universe multiverse
deb [arch=arm64,armhf] http://ports.ubuntu.com/ubuntu-ports noble-backports main universe multiverse
EOF

# MongoDB APT Repo (64-bit only)
echo "👉 Adding MongoDB repository..."
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-8.0.gpg
sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list > /dev/null <<EOF
# MongoDB 8.0 repository
deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] http://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main
EOF

# ---- UPDATE & INSTALL DEV LIBS ----
echo "👉 Updating APT and installing development libraries..."
sudo apt-get update
if [[ "$TARGET" == "pizero" ]]; then
  echo "👉 ARMHF libs for Pi Zero"
  sudo apt-get install -y libssl-dev:armhf libcurl4-openssl-dev:armhf liblzma-dev:armhf
else
  echo "👉 ARM64 libs for $TARGET"
  sudo apt-get install -y libssl-dev:arm64 libcurl4-openssl-dev:arm64 liblzma-dev:arm64
fi

# ---- CLONE SOURCE ----
echo "👉 Cloning MongoDB source..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
if [[ ! -d mongo ]]; then
  git clone -b "$MONGO_VERSION" https://github.com/mongodb/mongo.git
fi
cd mongo

# ---- PYTHON ENV SETUP ----
echo "👉 Creating Python venv with pyenv Python..."
if [[ ! -d venv ]]; then
  python -m venv venv
fi
source venv/bin/activate
pip install --upgrade pip==21.0.1
pip install -r etc/pip/compile-requirements.txt keyring jsonschema memory_profiler puremagic networkx cxxfilt

# ---- SET TOOLCHAIN CONFIG ----
case "$TARGET" in
  pi5)
    ARCH=arm64; GCC_PREFIX=aarch64-linux-gnu; CCFLAGS="-march=armv8-a+crc -mtune=cortex-a72";;
  pi0-2w)
    ARCH=arm64; GCC_PREFIX=aarch64-linux-gnu; CCFLAGS="-march=armv8-a -mtune=cortex-a53";;
  pizero)
    ARCH=armhf; GCC_PREFIX=arm-linux-gnueabihf; CCFLAGS="-march=armv6zk -mfpu=vfp -mfloat-abi=hard";;
esac
CORES=$(($(grep -c ^processor /proc/cpuinfo)-1))

echo "🔧 Configuring build for $TARGET with Python $PYTHON_VERSION..."
time python buildscripts/scons.py -j$CORES \
  AR=/usr/bin/${GCC_PREFIX}-ar CC=/usr/bin/${GCC_PREFIX}-gcc-${COMPILER_VERSION} \
  CXX=/usr/bin/${GCC_PREFIX}-g++-${COMPILER_VERSION} CCFLAGS="$CCFLAGS" \
  --dbg=off --opt=on --link-model=static --disable-warnings-as-errors \
  --linker=gold \
  --ninja generate-ninja NINJA_PREFIX=${GCC_PREFIX} VARIANT_DIR=${GCC_PREFIX} DESTDIR=${GCC_PREFIX}

echo "⚙️ Building MongoDB..."
time ninja -f ${GCC_PREFIX}.ninja -j$CORES install-devcore

echo "✂️ Stripping binaries..."
cd ${GCC_PREFIX}/bin
for bin in mongo mongod mongos; do mv $bin $bin.debug; ${GCC_PREFIX}-strip $bin.debug -o $bin; done

# ---- PACKAGE OUTPUT ----
cd ..
TAR_NAME="mongodb.${TARGET}.${MONGO_VERSION}.tar.gz"
tar --owner=root --group-root -czvf "$TAR_NAME" LICENSE-Community.txt README.md bin/mongo{d,,s}

echo "✅ Build complete! Archive at $(realpath $TAR_NAME)"
