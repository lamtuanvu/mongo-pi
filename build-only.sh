#!/bin/bash

# Script to build MongoDB after the environment has been prepared.
# Takes the target platform (pi5, pi0-2w, pizero) as the first argument.

set -euo pipefail

# ---- CONFIGURATION ----
MONGO_VERSION="r7.0.4" # Make sure this matches the intended build version
COMPILER_VERSION=13   # Make sure this matches the compiler installed
PYTHON_VERSION="3.11.5" # Make sure this matches the python installed by pyenv

# Build directory: Use /workspace/build inside Docker, or $HOME/mongo-build locally
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  BUILD_DIR="/workspace/build-output" # Build output within the mounted workspace
  MONGO_SRC_DIR="/workspace/mongo"    # Source cloned within the mounted workspace
else
  BUILD_DIR="$HOME/mongo-build"       # Default local build directory
  MONGO_SRC_DIR="$BUILD_DIR/mongo"    # Source cloned within the local build directory
fi

TARGET="$1" # Options: pi5, pi0-2w, pizero

# ---- VALIDATE TARGET ----
if [[ -z "$TARGET" || ( "$TARGET" != "pi5" && "$TARGET" != "pi0-2w" && "$TARGET" != "pizero" ) ]]; then
  echo "Usage: $0 <pi5|pi0-2w|pizero>"
  exit 1
fi

# ---- INITIALIZE PYENV (needed if running locally after prepare-env.sh) ----
if [[ "${GITHUB_ACTIONS:-false}" != "true" ]]; then
    echo "👉 Initializing pyenv for local execution..."
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    if command -v pyenv >/dev/null; then
      eval "$(pyenv init --path)"
      eval "$(pyenv init -)"
    else
        echo "ERROR: pyenv not found. Did you run prepare-env.sh first?"
        exit 1
    fi
    # Ensure the correct Python version is active
    pyenv shell "$PYTHON_VERSION"
fi

# ---- CLONE SOURCE ----
echo "👉 Cloning MongoDB source to $MONGO_SRC_DIR..."
mkdir -p "$(dirname "$MONGO_SRC_DIR")" # Create parent dir if needed
cd "$(dirname "$MONGO_SRC_DIR")"
if [[ ! -d "$(basename "$MONGO_SRC_DIR")" ]]; then
  git clone -b "$MONGO_VERSION" https://github.com/mongodb/mongo.git "$(basename "$MONGO_SRC_DIR")"
fi
cd "$MONGO_SRC_DIR"

# ---- PYTHON ENV SETUP ----
echo "👉 Creating Python venv in $MONGO_SRC_DIR/venv..."
if [[ ! -d venv ]]; then
  # Use the Python available in the PATH (should be the pyenv one locally, or system one in Docker)
  python -m venv venv
fi
source venv/bin/activate
# Use a pinned version for stability, ensure it's compatible with Python 3.11
pip install --upgrade pip==21.3.1 # Updated pip version
pip install -r etc/pip/compile-requirements.txt keyring jsonschema memory_profiler puremagic networkx cxxfilt

# ---- SET TOOLCHAIN CONFIG ----
case "$TARGET" in
pi5)
  ARCH=arm64
  GCC_PREFIX=aarch64-linux-gnu
  CCFLAGS="-march=armv8-a+crc -mtune=cortex-a72"
  ;;
pi0-2w)
  ARCH=arm64
  GCC_PREFIX=aarch64-linux-gnu
  CCFLAGS="-march=armv8-a -mtune=cortex-a53"
  ;;
pizero)
  ARCH=armhf
  GCC_PREFIX=arm-linux-gnueabihf
  CCFLAGS="-march=armv6zk -mfpu=vfp -mfloat-abi=hard"
  ;;
esac
# Determine cores available (works in Docker and locally)
CORES=$(($(nproc --all)-1))
if (( CORES < 1 )); then CORES=1; fi

# Add conditional SCons flags based on target
SCONS_FLAGS=""
if [[ "$TARGET" == "pi0-2w" ]]; then
  echo "👉 Disabling WiredTiger ARM CRC32 hardware support for Pi Zero 2 W (Cortex-A53 lacks CRC extension)"
  SCONS_FLAGS="--use-hardware-crc32=off"
fi

# Define build output directory *within* the build structure
TARGET_BUILD_DIR="$BUILD_DIR/$GCC_PREFIX"
mkdir -p "$TARGET_BUILD_DIR"

echo "🔧 Configuring build for $TARGET ($GCC_PREFIX) in $TARGET_BUILD_DIR..."

# Run scons from the source directory
cd "$MONGO_SRC_DIR"

time python buildscripts/scons.py -j$CORES \
  AR=/usr/bin/${GCC_PREFIX}-ar CC=/usr/bin/${GCC_PREFIX}-gcc-${COMPILER_VERSION} \
  CXX=/usr/bin/${GCC_PREFIX}-g++-${COMPILER_VERSION} CCFLAGS="$CCFLAGS" \
  --dbg=off --opt=on --link-model=static --disable-warnings-as-errors \
  --linker=gold \
  --ninja generate-ninja NINJA_PREFIX=${GCC_PREFIX} \
  VARIANT_DIR="${TARGET_BUILD_DIR}" DESTDIR="${TARGET_BUILD_DIR}" \
  $SCONS_FLAGS

echo "⚙️ Building MongoDB using Ninja..."
# Ninja file path is inside VARIANT_DIR
time ninja -f "${TARGET_BUILD_DIR}/compile_commands.ninja" -j$CORES install-devcore

echo "✂️ Stripping binaries in ${TARGET_BUILD_DIR}/bin..."
cd "${TARGET_BUILD_DIR}/bin"
for bin in mongo mongod mongos; do
  if [[ -f "$bin" ]]; then
    mv $bin $bin.debug
    ${GCC_PREFIX}-strip $bin.debug -o $bin
  else
      echo "Warning: Binary $bin not found for stripping."
  fi
done

# ---- PACKAGE OUTPUT ----
cd "${TARGET_BUILD_DIR}" # Change to the build output dir for packaging
TAR_NAME="mongodb.${TARGET}.${MONGO_VERSION}.tar.gz"

# Package LICENSE and README from the source directory ($MONGO_SRC_DIR)
# Package binaries from the current directory's bin/ subdir
echo "📦 Packaging binaries into $TAR_NAME..."
tar --owner=root -czvf "$TAR_NAME" \
    "$MONGO_SRC_DIR/LICENSE-Community.txt" \
    "$MONGO_SRC_DIR/README.md" \
    bin/mongo{d,,s}

# Provide the final path relative to the initial working directory
FINAL_PATH="$(realpath $TAR_NAME)"
echo "✅ Build complete! Archive at $FINAL_PATH" 