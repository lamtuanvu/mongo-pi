# MongoDB Cross-Compiler for Raspberry Pi

[![Build Status](https://github.com/lamtuanvu/mongo-pi/actions/workflows/build-mongo.yml/badge.svg)](https://github.com/lamtuanvu/mongo-pi/actions/workflows/build-mongo.yml)

This repository contains scripts and configurations to cross-compile MongoDB for specific Raspberry Pi models on an x86_64 Ubuntu host.

The primary goal is to provide an automated way to build MongoDB binaries suitable for:
*   Raspberry Pi 5 (64-bit ARMv8)
*   Raspberry Pi Zero / Zero W (32-bit ARMv6)

## Features

*   Cross-compiles a specific MongoDB version (currently `r7.0.4`).
*   Uses Ubuntu's multiarch support and dedicated GCC cross-compilers.
*   Utilizes `pyenv` to manage the required Python version (`3.11.5`) without interfering with system Python.
*   Automated builds via GitHub Actions (manually triggered).
*   Automatic upload of compiled binaries to GitHub Releases.
*   Strips binaries for reduced size.

## Pre-built Binaries

The easiest way to get the binaries is to download them directly from the [**GitHub Releases**](https://github.com/lamtuanvu/mongo-pi/releases) page of this repository.

The GitHub Actions workflow automatically builds the binaries for the supported targets (`pi5`, `pizero`) and attaches them to a release tagged with the corresponding MongoDB version (e.g., `r7.0.4`).

Look for files named `mongodb.pi5.rX.Y.Z.tar.gz` and `mongodb.pizero.rX.Y.Z.tar.gz`.

## Build Manually

If you prefer to build the binaries yourself, you can use the provided build script.

### Prerequisites

*   An x86_64 host machine running Ubuntu (tested with dependencies available on 24.04 LTS "Noble Numbat").
*   `git` and `curl` installed.
*   `sudo` privileges are required to install necessary build dependencies and configure multiarch APT sources.
*   Internet connection to download sources, dependencies, and the MongoDB codebase.

### Steps

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/lamtuanvu/mongo-pi.git
    cd mongo-pi
    ```

2.  **Run the build script:**
    The script takes the target platform as an argument (`pi5` or `pizero`).

    *   **For Raspberry Pi 5:**
        ```bash
        ./build-mongo.sh pi5
        ```
    *   **For Raspberry Pi Zero / Zero W:**
        ```bash
        ./build-mongo.sh pizero
        ```

The script will perform the following actions:
    *   Install `pyenv` if not present.
    *   Install the required Python version via `pyenv`.
    *   Install necessary build dependencies and cross-compilers using `apt`.
    *   Configure APT sources for multiarch (`arm64`, `armhf`).
    *   Install target architecture development libraries (`libssl-dev`, etc.).
    *   Clone the specified MongoDB source code version.
    *   Set up a Python virtual environment for the build.
    *   Configure the build using SCons.
    *   Compile MongoDB using Ninja.
    *   Strip the resulting binaries (`mongo`, `mongod`, `mongos`).
    *   Package the essential binaries, license, and README into a `.tar.gz` archive.

3.  **Locate the archive:**
    Upon successful completion, the script will print the full path to the generated archive. It will be located within the build directory:
    *   Pi 5: `$HOME/mongo-build/mongo/aarch64-linux-gnu/mongodb.pi5.<version>.tar.gz`
    *   Pi Zero: `$HOME/mongo-build/mongo/arm-linux-gnueabihf/mongodb.pizero.<version>.tar.gz`

## Configuration

The following versions can be adjusted at the top of the `build-mongo.sh` script:
*   `MONGO_VERSION`: The tag/branch of the MongoDB source to build.
*   `COMPILER_VERSION`: The major version of the GCC cross-compiler to use.
*   `PYTHON_VERSION`: The specific Python version required by the MongoDB build scripts.

## Contributing

Contributions are welcome! Please read the [CONTRIBUTING.md](./CONTRIBUTING.md) guide for details on how to submit bug reports, feature requests, and pull requests.

## Code of Conduct

Please review and adhere to the [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md).

## License

This project is licensed under the MIT License - see the [LICENSE](./LICENSE) file for details. 