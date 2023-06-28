#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
ORANGE='\033[0;33m'
NC='\033[0m'
MAKEPKG="makepkg -si --noconfirm"

error() {
  printf "${RED}%s${NC} %s\n" "ERROR:" "${1}"
  exit 1
}

warning() {
  printf "${ORANGE}%s${NC} %s\n" "WARNING:" "${1}"
}

# Configure package manager here if necessary:
if [[ -x "$(command -v yay)" ]]; then
  PKGMAN="yay -S --noconfirm"
elif [[ -x "$(command -v /bin/paru)" ]]; then
  PKGMAN="paru -S --noconfirm"
else
  error "Couldn't find a package manager, please install either yay or paru"
fi

build_and_install() {
  echo "# Build and install package: ${1}"
  pushd "${1}" || error "Not a directory: ${1}"
  eval "${MAKEPKG}"
  local installation_state="${?}"
  popd || error "Unable to go back to working directory."
  if [[ "${installation_state}" -eq 0 ]]; then
    echo "=> SUCCESS"
  else
    error "Failed to install: ${1}"
  fi
}

# ------------------------------------------------------------------------------

# Need to have the correct headers installed before proceding with DKMS
if pacman -Qq linux >/dev/null 2>/dev/null; then
  eval "${PKGMAN} --needed linux-headers"
fi
if pacman -Qq linux-lts >/dev/null 2>/dev/null; then
  eval "${PKGMAN} --needed linux-lts-headers"
fi
if pacman -Qq linux-zen >/dev/null 2>/dev/null; then
  eval "${PKGMAN} --needed linux-zen-headers"
fi
if pacman -Qq linux-hardened >/dev/null 2>/dev/null; then
  eval "${PKGMAN} --needed linux-hardened-headers"
fi

# General dependency(-ies?) to make the webcam work:
general_dependencies=(gst-plugin-pipewire)

# Install dependency for intel-ipu6-dkms-git
echo "# Install dependency for intel-ipu6-dkms-git"
if eval "${PKGMAN} intel-ivsc-firmware"; then
  echo "=> SUCCESS"
else
  error " Failed to install: intel-ivsc-firmware"
fi

build_and_install "intel-ipu6-dkms-git"

# Install dependency for intel-ipu6ep-camera-hal-git
echo "# Install dependency for intel-ipu6ep-camera-hal-git"
if eval "${PKGMAN} intel-ipu6ep-camera-bin"; then
  echo "=> SUCCESS"
else
  error " Failed to install: intel-ipu6ep-camera-bin"
fi

build_and_install "intel-ipu6ep-camera-hal-git"
build_and_install "v4l2loopback-dkms-git"
build_and_install "v4l2-relayd"
build_and_install "icamerasrc-git"

# Install general dependencies
echo "# Install general dependencies"
if eval "${PKGMAN} ${general_dependencies[*]}"; then
  echo "=> SUCCESS"
elif pacman -Qq "${general_dependencies[@]}"; then
  warning "Dependencies failed to update, but are already installed. Trying to continue."
else
  error "Failed to install: ${general_dependencies[*]}"
fi

# Copy workaround if requested
if [[ "${1:-}" == "--workaround" ]]; then
  sudo mkdir -p /etc/systemd/system/v4l2-relayd.service.d
  sudo cp -f workarounds/override.conf /etc/systemd/system/v4l2-relayd.service.d/override.conf
  sudo install -m 744 workarounds/i2c_ljca-s2disk.sh /usr/lib/systemd/system-sleep/i2c_ljca-s2disk.sh
fi

echo "# Enable: v4l2-relayd.service"
if sudo systemctl enable v4l2-relayd.service; then
  echo "=> SUCCESS"
else
  error "Failed to enable: v4l2-relayd.service"
fi
echo "# Start: v4l2-relayd.service"
if sudo systemctl start v4l2-relayd.service; then
  echo "=> SUCCESS"
else
  error "Failed to start: v4l2-relayd.service"
fi

echo -e "\n\nAll done.\nRemember to reboot upon succesful installation!"
