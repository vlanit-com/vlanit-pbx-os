#!/bin/sh
# Ждём DRM/fb до plymouthd — иначе two-step падает в text display.
set -eu
for m in virtio_gpu bochs; do
  modprobe "$m" 2>/dev/null || true
done
i=0
while [ "$i" -lt 40 ]; do
  if [ -e /dev/dri/card0 ] || [ -e /dev/fb0 ]; then
    echo "vlanit-plymouth: drm/fb ready (i=$i)" > /dev/kmsg 2>/dev/null || true
    exit 0
  fi
  i=$((i + 1))
  sleep 0.1
done
echo "vlanit-plymouth: WARN no /dev/dri/card0 or /dev/fb0 after wait" > /dev/kmsg 2>/dev/null || true
exit 0
