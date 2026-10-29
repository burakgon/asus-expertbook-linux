"""Exercise installer failure/reinstall handling without privileged writes."""
from pathlib import Path
import os
import tempfile
import unittest


MODULE = Path(__file__).parents[1] / "module.sh"


class InstallTests(unittest.TestCase):
    def install(self, registered="", fail_build=False, native=False, kernel="7.2.3-arch1-3",
                diff_ok=True, others=(), headerless=(), missing=(), installed=(),
                fail_install=False):
        script = r'''
set -euo pipefail
source "$1"
MODULE_DIR="$FIXTURE"
warn() { printf 'warn %s\n' "$*" >&2; }
log() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
cat() { echo 'ASUS EXPERTBOOK B9406CAA'; }
uname() { echo "$KERNEL"; }
kernel_list() { printf '%s\n' "$KERNEL" $OTHERS $HEADERLESS; }
kernel_headers_present() { [[ -f $ROOT/lib/modules/$1/build/Makefile ]]; }
command() { [[ " $MISSING " != *" ${!#} "* ]]; }
install() { echo "write-source $*"; }
chown() { echo chown; }
chmod() { echo chmod; }
modprobe() { echo load-driver; }
mod_install_files() { echo publish-config; }
diff() { [[ $DIFF_OK == 1 ]]; }
# DKMS state, one line per registration ("<version> - registered") or per
# kernel build ("<version> <kernel> built|installed").
STATE="$ROOT/dkms.state"
dkms() {
  local cmd=$1 version="" k="" all=0
  shift
  while [[ $# -gt 0 ]]; do
    case $1 in
      -v) version=$2; shift 2 ;;
      -k) k=$2; shift 2 ;;
      --all) all=1; shift ;;
      *) shift ;;
    esac
  done
  if [[ $cmd == status ]]; then
    awk -v v="$version" -v k="$k" '
      $1 == v && $2 != "-" && (k == "" || $2 == k) {
        printf "b9406-mute-led/%s, %s, x86_64: %s\n", v, $2, $3; found = 1
      }
      $1 == v && $2 == "-" { registered = 1 }
      END { if (!found && registered && k == "") print "b9406-mute-led/" v ": added" }
    ' "$STATE"
    return 0
  fi
  echo "dkms-$cmd-$version${k:+-$k}"
  case $cmd in
    add) echo "$version - registered" >> "$STATE" ;;
    build)
      [[ $FAIL_BUILD == 1 ]] && return 42
      echo "$version $k built" >> "$STATE" ;;
    install)
      [[ $FAIL_INSTALL == 1 && $version == 0.2 ]] && return 43
      grep -v "^$version $k " "$STATE" > "$STATE.new" || true
      echo "$version $k installed" >> "$STATE.new"
      mv "$STATE.new" "$STATE" ;;
    uninstall)
      sed -i "s/^$version $k installed\$/$version $k built/" "$STATE" ;;
    remove)
      if (( all )); then
        grep -v "^$version " "$STATE" > "$STATE.new" || true
      else
        grep -v "^$version $k " "$STATE" > "$STATE.new" || true
      fi
      mv "$STATE.new" "$STATE" ;;
  esac
}
module_install
'''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment = dict(
                os.environ,
                FAIL_BUILD=str(int(fail_build)),
                FAIL_INSTALL=str(int(fail_install)),
                KERNEL=kernel,
                DIFF_OK=str(int(diff_ok)),
                OTHERS=" ".join(others),
                HEADERLESS=" ".join(headerless),
                MISSING=" ".join(missing),
                ROOT=str(root),
                MUTE_DKMS_ROOT=str(root / "src"),
                FIXTURE=str(root / "fixture"),
            )
            state = [f"{version} - registered" for version in registered.split()]
            for version, release in installed:
                state += [f"{version} - registered", f"{version} {release} installed"]
            (root / "dkms.state").write_text("".join(line + "\n" for line in state))
            bundle = root / "fixture/dkms/b9406-mute-led-0.2"
            bundle.mkdir(parents=True)
            (bundle / "dkms.conf").write_text("PACKAGE_VERSION=0.2\n")
            (bundle / "Makefile").write_text("obj-m += b9406_mute_led.o\n")
            (bundle / "b9406_mute_led.c").write_text("/* fixture */\n")
            for release in (kernel, *others):
                headers = root / "lib/modules" / release / "build"
                headers.mkdir(parents=True)
                (headers / "Makefile").touch()
            if not native:
                (root / "sys/module/b9406_mute_led").mkdir(parents=True)
            else:
                (root / "sys/class/leds/platform::mute").mkdir(parents=True)
            load = root / "modules-load.conf"
            source = MODULE.read_text()
            source = source.replace("/sys/", str(root / "sys") + "/")
            source = source.replace("/lib/modules/", str(root / "lib/modules") + "/")
            source = source.replace(
                "/etc/modules-load.d/b9406-mute-led.conf", str(load))
            manifest = root / "module.sh"
            manifest.write_text(source)
            completed = subprocess_run(script, manifest, environment, root)
            load = root / "modules-load.conf"
            completed.load_text = load.read_text() if load.exists() else ""
            return completed

    def test_failed_build_does_not_publish_boot_or_service_config(self):
        result = self.install(fail_build=True)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertNotIn("load-driver", result.stdout)
        self.assertNotIn("publish-config", result.stdout)

    def test_reinstall_does_not_overwrite_registered_source(self):
        result = self.install(registered="0.2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("write-source", result.stdout)
        self.assertNotIn("dkms-add-0.2", result.stdout)
        self.assertIn("dkms-install-0.2-7.2.3-arch1-3", result.stdout)
        self.assertIn("publish-config", result.stdout)

    def test_old_version_gives_way_only_once_0_2_is_built(self):
        result = self.install(installed=(("0.1", "7.2.3-arch1-3"),))
        self.assertEqual(result.returncode, 0, result.stderr)
        steps = ["dkms-add-0.2", "dkms-build-0.2-7.2.3-arch1-3",
                 "dkms-uninstall-0.1-7.2.3-arch1-3", "dkms-install-0.2-7.2.3-arch1-3",
                 "dkms-remove-0.1"]
        positions = [result.stdout.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions), result.stdout)

    def test_failed_build_leaves_the_old_version_alone(self):
        result = self.install(installed=(("0.1", "7.2.3-arch1-3"),), fail_build=True)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertNotIn("dkms-uninstall-0.1", result.stdout)
        self.assertNotIn("dkms-remove-0.1", result.stdout)

    def test_failed_install_puts_the_old_version_back(self):
        result = self.install(installed=(("0.1", "7.2.3-arch1-3"),), fail_install=True)
        self.assertEqual(result.returncode, 43, result.stderr)
        steps = ["dkms-uninstall-0.1-7.2.3-arch1-3", "dkms-install-0.2-7.2.3-arch1-3",
                 "dkms-install-0.1-7.2.3-arch1-3"]
        positions = [result.stdout.index(step) for step in steps]
        self.assertEqual(positions, sorted(positions), result.stdout)
        self.assertNotIn("dkms-remove-0.1", result.stdout)

    def test_old_version_stays_on_a_kernel_without_headers(self):
        result = self.install(headerless=("7.2.11-arch1-1",),
                              installed=(("0.1", "7.2.3-arch1-3"), ("0.1", "7.2.11-arch1-1")))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dkms-uninstall-0.1-7.2.3-arch1-3", result.stdout)
        self.assertNotIn("dkms-uninstall-0.1-7.2.11-arch1-1", result.stdout)
        self.assertNotIn("dkms-remove-0.1", result.stdout)
        self.assertIn("kept b9406-mute-led 0.1 on 7.2.11-arch1-1", result.stderr)

    def test_old_version_comes_off_a_kernel_that_no_longer_needs_the_bridge(self):
        result = self.install(others=("7.4.1-arch1-1",),
                              installed=(("0.1", "7.2.3-arch1-3"), ("0.1", "7.4.1-arch1-1")))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dkms-uninstall-0.1-7.4.1-arch1-1", result.stdout)
        self.assertIn("dkms-remove-0.1", result.stdout)

    def test_registered_source_mismatch_is_not_overwritten(self):
        result = self.install(registered="0.2", diff_ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("write-source", result.stdout)
        self.assertNotIn("publish-config", result.stdout)
        self.assertIn("differs from this checkout", result.stderr)

    def test_native_led_still_installs_the_synchronizer(self):
        result = self.install(native=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("dkms-add-0.2", result.stdout)
        self.assertNotIn("load-driver", result.stdout)
        self.assertIn("publish-config", result.stdout)
        self.assertIn("provided by the kernel", result.load_text)

    def test_kernel_7_4_skips_the_bridge_and_keeps_the_synchronizer(self):
        result = self.install(kernel="7.4.1-arch1-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("dkms-add-0.2", result.stdout)
        self.assertIn("publish-config", result.stdout)
        self.assertIn("provided by the kernel", result.load_text)

    def test_every_installed_kernel_that_needs_the_bridge_is_built(self):
        result = self.install(others=("7.3.0-2-cachyos-bore-lto", "7.4.1-arch1-1"),
                              headerless=("7.2.11-arch1-1",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dkms-install-0.2-7.2.3-arch1-3", result.stdout)
        self.assertIn("dkms-install-0.2-7.3.0-2-cachyos-bore-lto", result.stdout)
        self.assertNotIn("7.4.1-arch1-1", result.stdout)
        self.assertNotIn("dkms-install-0.2-7.2.11-arch1-1", result.stdout)
        self.assertIn("skipping 7.2.11-arch1-1", result.stderr)
        self.assertEqual(result.stdout.count("load-driver"), 1)

    def test_a_failed_build_for_another_kernel_still_fails_the_install(self):
        result = self.install(fail_build=True, others=("7.3.0-2-cachyos-bore-lto",))
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertNotIn("publish-config", result.stdout)

    def test_running_7_4_keeps_the_bridge_for_older_installed_kernels(self):
        result = self.install(kernel="7.4.1-arch1-1", others=("7.3.0-2-cachyos-bore-lto",),
                              registered="0.2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("dkms-remove-0.2", result.stdout)
        self.assertIn("dkms-install-0.2-7.3.0-2-cachyos-bore-lto", result.stdout)
        self.assertNotIn("dkms-install-0.2-7.4.1-arch1-1", result.stdout)
        self.assertNotIn("load-driver", result.stdout)
        self.assertIn("publish-config", result.stdout)
        self.assertNotIn("provided by the kernel", result.load_text)

    def test_missing_sync_tools_only_warn(self):
        result = self.install(missing=("pactl", "brightnessctl"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dkms-install-0.2-7.2.3-arch1-3", result.stdout)
        self.assertIn("load-driver", result.stdout)
        self.assertIn("missing pactl", result.stderr)
        self.assertIn("missing brightnessctl", result.stderr)

    def test_missing_dkms_still_fails_when_a_kernel_needs_the_bridge(self):
        result = self.install(missing=("dkms",))
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("publish-config", result.stdout)

    def test_native_led_on_the_running_kernel_still_bridges_older_kernels(self):
        result = self.install(native=True, others=("7.2.11-arch1-1",))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dkms-install-0.2-7.2.11-arch1-1", result.stdout)
        self.assertNotIn("dkms-install-0.2-7.2.3-arch1-3", result.stdout)
        self.assertNotIn("load-driver", result.stdout)
        self.assertNotIn("provided by the kernel", result.load_text)


def subprocess_run(script, manifest, environment, root):
    import subprocess
    completed = subprocess.run(
        ["bash", "-c", script, "test", str(manifest)],
        env=environment, text=True, capture_output=True)
    completed.load_conf = root / "modules-load.conf"
    return completed


if __name__ == "__main__":
    unittest.main()
