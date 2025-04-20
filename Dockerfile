# Use Ubuntu 24.04 as the base image
FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Copy the scripts into the image
COPY prepare-env.sh build-only.sh /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/prepare-env.sh /usr/local/bin/build-only.sh

# Run the environment preparation script during image build
# This installs apt packages, pyenv, python, configures apt/multiarch
RUN /usr/local/bin/prepare-env.sh

# Set up Python 3.11 provided by pyenv as the default
# (prepare-env.sh installs it to $HOME/.pyenv)
# Note: This assumes prepare-env.sh runs as root, so $HOME is /root
ENV PYENV_ROOT=/root/.pyenv
ENV PATH=$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH

# Create a working directory for the build script
WORKDIR /workspace

# Entrypoint will execute the build-only script
# The target (pi5, pizero) will be passed as CMD by docker run
ENTRYPOINT ["/usr/local/bin/build-only.sh"] 