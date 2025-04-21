#!/bin/bash

# Orchestration script to build MongoDB inside Docker

set -euo pipefail

# --- Configuration ---
TARGET="$1" # pi5, pi0-2w, or pizero
IMAGE_NAME="mongo-cross-builder"
CONTAINER_NAME="mongo-build-container"
DOCKERFILE="Dockerfile.mongo-builder"
# Assume scripts are in the same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output" # Output directory on the host

# --- Validate Target ---
if [[ -z "$TARGET" || ( "$TARGET" != "pi5" && "$TARGET" != "pi0-2w" && "$TARGET" != "pizero" ) ]]; then
  echo "Usage: $0 <pi5|pi0-2w|pizero>"
  echo "Example: $0 pi5"
  exit 1
fi

# --- Build Docker Image ---
echo "👉 Building Docker image '$IMAGE_NAME' (forcing no-cache)..."
docker build --no-cache -t "$IMAGE_NAME" -f "${SCRIPT_DIR}/${DOCKERFILE}" "$SCRIPT_DIR"

# --- Prepare Output Directory ---
echo "👉 Preparing host output directory '$OUTPUT_DIR'..."
mkdir -p "$OUTPUT_DIR"
# Optional: Clear previous build results for the target
# rm -f "${OUTPUT_DIR}/mongodb.${TARGET}."*".tar.gz"
echo "Host output directory ready."

# --- Run Build Container ---
echo "🚀 Running build for target '$TARGET' in Docker container..."
# Mount the output directory as /workspace/build-output (read-write)
# Restore original build command - run as root, fix script paths
docker run --rm \
       --name "$CONTAINER_NAME" \
       -v "$OUTPUT_DIR":/workspace/build-output:rw \
       "$IMAGE_NAME" \
       /bin/bash -c "set -euo pipefail && echo '--- Running prepare-env.sh ---' && /app/prepare-env.sh && echo '--- Running build-only.sh ---' && /app/build-only.sh $TARGET"

echo "✅ Docker build process completed."
echo "📦 Build artifact should be in: $OUTPUT_DIR"

# List the contents of the output directory
ls -l "$OUTPUT_DIR"
