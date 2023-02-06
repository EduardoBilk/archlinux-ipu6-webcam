#!/usr/bin/env bash

# Configure package manager here if necessary:
if [ -f /bin/yay ]; then
  PKGMAN="yay -S --noconfirm"
elif [ -f /bin/paru ]; then
  PKGMAN="paru -S --noconfirm"
else
  echo "ERROR: Couldn't find a package manager, please configure it manually"
  exit 1
fi

# Configure makepkg here if necessary:
MAKEPKG="makepkg -si --noconfirm"

error() {
  echo "ERROR: $1"
  exit 1
}

build_and_install() {
  echo "# Build and install package: $1"
  pushd "$1" || error "Not a directory: $1"
  $MAKEPKG
  local installation_state=$?
  popd || error "Unable to go back to working directory."
  if [[ "${installation_state}" -eq 0 ]]; then
    echo "=> SUCCESS"
  else
    error "Failed to install: $1"
  fi
}

# ------------------------------------------------------------------------------

# Need to have the correct headers installed before proceding with DKMS
if pacman -Qq linux >/dev/null 2>/dev/null; then
  $PKGMAN --needed linux-headers
fi
if pacman -Qq linux-lts >/dev/null 2>/dev/null; then
  $PKGMAN --needed linux-lts-headers
fi
if pacman -Qq linux-zen >/dev/null 2>/dev/null; then
  $PKGMAN --needed linux-zen-headers
fi
if pacman -Qq linux-hardened >/dev/null 2>/dev/null; then
  $PKGMAN --needed linux-hardened-headers
fi

# General dependencies to make the webcam work:
general_dependencies="intel-ivsc-driver-dkms-git intel-ivsc-firmware icamerasrc-git gst-plugin-pipewire"

build_and_install "intel-ipu6-dkms-git"

# Install dependency for intel-ipu6ep-camera-hal-git
echo "# Install dependency for intel-ipu6ep-camera-hal-git"
$PKGMAN intel-ipu6ep-camera-bin && \
  echo "=> SUCCESS" || \
  error "# Failed to install: intel-ipu6ep-camera-bin"

build_and_install "intel-ipu6ep-camera-hal-git"
build_and_install "v4l2-looback-dkms-git"
build_and_install "v4l2-relayd"

# Install general dependencies
echo "# Install general dependencies"
$PKGMAN $general_dependencies && \
  echo "=> SUCCESS" || \
  error "Failed to install: $general_dependencies"

echo "# Enable: v4l2-relayd.service"
sudo systemctl enable v4l2-relayd.service && \
  echo "=> SUCCESS" || \
  error "# Failed to enable: v4l2-relayd.service"
echo "# Start: v4l2-relayd.service"
sudo systemctl start v4l2-relayd.service && \
  echo "=> SUCCESS" || \
  error "Failed to start: v4l2-relayd.service"


if [ "$1" = "--workaround" ]; then
  echo "# Creating /etc/systemd/system/v4l2-relayd.service.d/override.conf"
  sudo mkdir -p /etc/systemd/system/v4l2-relayd.service.d && \
  echo -e "[Service]\nExecStart=\nExecStart=/bin/sh -c 'DEVICE=\$(grep -l -m1 -E \"^\${CARD_LABEL}\$\" /sys/devices/virtual/video4linux/*/name | cut -d/ -f6); exec /usr/bin/v4l2-relayd -i \"\${VIDEOSRC}\" \$\${SPLASHSRC:+-s \"\${SPLASHSRC}\"} -o \"appsrc name=appsrc caps=video/x-raw,format=\${FORMAT},width=\${WIDTH},height=\${HEIGHT},framerate=\${FRAMERATE} ! videoconvert ! video/x-raw,format=YUY2 ! v4l2sink name=v4l2sink device=/dev/\$\${DEVICE}\"'" | \
    sudo tee /etc/systemd/system/v4l2-relayd.service.d/override.conf >/dev/null && \
    echo "=> SUCCESS" || \
    error "Failed to write: /etc/systemd/system/v4l2-relayd.service.d/override.conf"

  echo "# Reloading systemd daemon"
  sudo systemctl daemon-reload && \
    echo "=> SUCCESS" || \
    error "Failed to reload systemd daemon"

  echo "# Restart: v4l2-relayd.service"
  sudo systemctl restart v4l2-relayd.service && \
    echo "=> SUCCESS" || \
    error "Failed to restart: v4l2-relayd.service"
fi

