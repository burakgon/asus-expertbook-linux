# webcam-ai-fix module manifest.
#
# Stand up the userspace plumbing for AI-enhanced webcam on Linux —
# the "Windows Studio Effects" equivalent on Intel Panther Lake hardware.
#
# What this module installs:
#   v4l2loopback-dkms (extra)        creates /dev/video10 as "AI Camera"
#                                    so processed frames have a target
#   obs-studio (extra)               the orchestrator + virtual cam writer
#   obs-backgroundremoval (AUR)      ML segmentation plugin for OBS;
#                                    runs ONNX models, can target NPU via
#                                    OpenVINO if openvino is installed
#
# What this module deliberately does NOT install:
#   openvino (AUR)                   ~30+ minute compile from source. Add
#                                    later with `paru -S openvino` if you
#                                    want NPU acceleration. obs-bg-removal
#                                    works fine on TFLite/CPU without it.
#   intel/openvino-plugins-for-obs   no AUR packaging yet; build manually
#                                    from intel/openvino-plugins-for-obs-studio
#                                    if you want Intel's officially-blessed
#                                    Smart Framing / Background Concealment
#                                    plugins.
#
# NPU device permissions: /dev/accel/accel0 ships world-writable on this
# distro, so render-group membership is not required. We add the user
# anyway as defensive future-proofing.

MODULE_NAME="webcam-ai-fix"
MODULE_DESC="AI camera stack — OBS + obs-backgroundremoval + v4l2loopback (NPU optional)"
MODULE_VERSION="1.0.1"

MODULE_FILES=(
  "v4l2loopback.conf:/etc/modules-load.d/v4l2loopback.conf"
  "v4l2loopback-options.conf:/etc/modprobe.d/v4l2loopback-options.conf"
)

_wai_aur_helper() {
  local h
  for h in paru yay; do
    command -v "$h" >/dev/null 2>&1 && { printf '%s' "$h"; return 0; }
  done
  return 1
}

module_post_install() {
  echo "  installing v4l2loopback-dkms + obs-studio (extra repo)"
  pacman -S --needed --noconfirm v4l2loopback-dkms obs-studio 2>&1 | tail -5 || true

  echo
  echo "  obs-backgroundremoval lives in the AUR. paru / yay needs an interactive"
  echo "  sudo prompt during makepkg → install, which this scripted invocation"
  echo "  cannot supply. After the rest of the install finishes, run:"
  echo
  echo "      paru -S obs-backgroundremoval"
  echo
  echo "  ~5 min compile, all subsequent runs of './patch.sh status webcam-ai-fix'"
  echo "  will detect it."

  # Add user to render group (defensive — /dev/accel/accel0 is 0666 today
  # but distros sometimes tighten this).
  if [[ -n "${SUDO_USER:-}" ]] && ! id -nG "$SUDO_USER" | grep -qw render; then
    echo "  adding $SUDO_USER to render group (NPU access future-proofing)"
    usermod -aG render "$SUDO_USER" 2>/dev/null || true
    echo "  log out + back in for the new group to take effect"
  fi

  # Load v4l2loopback now so /dev/video10 appears without reboot.
  if ! lsmod | grep -q '^v4l2loopback'; then
    echo "  loading v4l2loopback now (devices=1 video_nr=10 'AI Camera')"
    modprobe v4l2loopback devices=1 video_nr=10 card_label='AI Camera' exclusive_caps=1 \
      2>&1 | tail -3 || true
  fi

  echo
  echo "Done. Next steps:"
  echo "  1) Open OBS Studio."
  echo "  2) Add a Video Capture Device source pointing at /dev/video2 (real cam)."
  echo "  3) Right-click the source → Filters → add 'Background Removal'."
  echo "  4) Tools → Start Virtual Camera (default writes to /dev/video10)."
  echo "  5) In Zoom / Discord / browser, pick 'AI Camera' as the camera."
  echo
  echo "For NPU acceleration, install openvino:"
  echo "  paru -S openvino"
  echo "  ─ then in obs-backgroundremoval Filter settings, set"
  echo "    'Inference Device' to NPU."
}

module_post_uninstall() {
  if lsmod | grep -q '^v4l2loopback'; then
    echo "  unloading v4l2loopback"
    rmmod v4l2loopback 2>/dev/null || true
  fi
  echo
  echo "  Packages (v4l2loopback-dkms, obs-studio, obs-backgroundremoval, openvino if you added it)"
  echo "  are left installed for revert without re-fetching. Remove fully with:"
  echo "    sudo pacman -Rns v4l2loopback-dkms obs-studio"
  echo "    paru -Rns obs-backgroundremoval openvino"
}

module_status_extra() {
  # NPU device
  if [[ -e /dev/accel/accel0 ]]; then
    local perms
    perms=$(stat -c '%a' /dev/accel/accel0 2>/dev/null)
    if [[ "$perms" == "666" ]] || id -nG "$USER" 2>/dev/null | grep -qw render; then
      printf '  NPU device:    %s/dev/accel/accel0 (mode %s) — accessible%s\n' "$c_ok" "$perms" "$c_off"
    else
      printf '  NPU device:    %s/dev/accel/accel0 (mode %s) — log out + in for render group%s\n' "$c_warn" "$perms" "$c_off"
    fi
  else
    printf '  NPU device:    %sNPU not exposed; check intel_vpu kernel module%s\n' "$c_warn" "$c_off"
  fi

  # v4l2loopback live + virtual cam
  if [[ -d /sys/module/v4l2loopback ]]; then
    printf '  v4l2loopback:  %sloaded%s\n' "$c_ok" "$c_off"
    if [[ -e /dev/video10 ]]; then
      local label
      label=$(v4l2-ctl --device /dev/video10 --info 2>/dev/null | awk -F': ' '/Card type/{print $2; exit}')
      printf '  virtual cam:   %s/dev/video10 ("%s")%s\n' "$c_ok" "$label" "$c_off"
    fi
  else
    printf '  v4l2loopback:  %snot loaded — run modprobe v4l2loopback or reboot%s\n' "$c_warn" "$c_off"
  fi

  # OBS + plugin
  if pacman -Q obs-studio >/dev/null 2>&1; then
    printf '  obs-studio:    %s%s%s\n' "$c_ok" "$(pacman -Q obs-studio | awk '{print $2}')" "$c_off"
  else
    printf '  obs-studio:    %snot installed%s\n' "$c_warn" "$c_off"
  fi
  if pacman -Q obs-backgroundremoval >/dev/null 2>&1; then
    printf '  bg-removal:    %s%s (plugin)%s\n' "$c_ok" "$(pacman -Q obs-backgroundremoval | awk '{print $2}')" "$c_off"
  else
    printf '  bg-removal:    %snot installed%s\n' "$c_warn" "$c_off"
  fi

  # OpenVINO (optional)
  if pacman -Q openvino >/dev/null 2>&1; then
    printf '  openvino:      %s%s — NPU acceleration enabled%s\n' "$c_ok" "$(pacman -Q openvino | awk '{print $2}')" "$c_off"

    # Quick test: does the OpenVINO runtime see the NPU?
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import openvino' 2>/dev/null; then
      local devs
      devs=$(python3 -c "import openvino; print(','.join(openvino.Core().available_devices))" 2>/dev/null || true)
      if [[ "$devs" == *"NPU"* ]]; then
        printf '  ov runtime:    %sdevices = %s%s\n' "$c_ok" "$devs" "$c_off"
      else
        printf '  ov runtime:    %sdevices = %s (no NPU yet — log out + in?)%s\n' "$c_warn" "$devs" "$c_off"
      fi
    fi
  else
    printf '  openvino:      %snot installed (CPU only; install with: paru -S openvino)%s\n' "$c_dim" "$c_off"
  fi
}
