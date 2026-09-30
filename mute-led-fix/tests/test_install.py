"""Exercise installer failure/reinstall handling without privileged writes."""
from pathlib import Path
import os
import tempfile
import unittest


MODULE = Path(__file__).parents[1] / "module.sh"


class InstallTests(unittest.TestCase):
    def install(self, registered="", fail_build=False, native=False, kernel="7.2.3-arch1-3",
                diff_ok=True):
        script = r'''
set -euo pipefail
source "$1"
MODULE_DIR="$FIXTURE"
warn() { printf 'warn %s\n' "$*" >&2; }
log() { :; }
die() { printf '%s\n' "$*" >&2; exit 1; }
cat() { echo 'ASUS EXPERTBOOK B9406CAA'; }
uname() { echo "$KERNEL"; }
command() { return 0; }
install() { echo "write-source $*"; }
chown() { echo chown; }
chmod() { echo chmod; }
modprobe() { echo load-driver; }
mod_install_files() { echo publish-config; }
diff() { [[ $DIFF_OK == 1 ]]; }
dkms() {
  local cmd=$1 version=""
  shift
  while [[ $# -gt 0 ]]; do
    if [[ $1 == -v ]]; then version=$2; shift 2; continue; fi
    shift
  done
  if [[ $cmd == status ]]; then
    [[ " $REGISTERED " == *" $version "* ]] && echo installed
    return 0
  fi
  echo "dkms-$cmd-$version"
  if [[ $cmd == install && $FAIL_BUILD == 1 ]]; then return 42; fi
}
module_install
'''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            environment = dict(
                os.environ,
                REGISTERED=registered,
                FAIL_BUILD=str(int(fail_build)),
                KERNEL=kernel,
                DIFF_OK=str(int(diff_ok)),
                MUTE_DKMS_ROOT=str(root / "src"),
                FIXTURE=str(root / "fixture"),
            )
            bundle = root / "fixture/dkms/b9406-mute-led-0.2"
            bundle.mkdir(parents=True)
            (bundle / "dkms.conf").write_text("PACKAGE_VERSION=0.2\n")
            (bundle / "Makefile").write_text("obj-m += b9406_mute_led.o\n")
            (bundle / "b9406_mute_led.c").write_text("/* fixture */\n")
            headers = root / "lib/modules" / kernel / "build"
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
        self.assertIn("dkms-install-0.2", result.stdout)
        self.assertIn("publish-config", result.stdout)

    def test_old_registration_is_removed_before_0_2_is_added(self):
        result = self.install(registered="0.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("dkms-remove-0.1", result.stdout)
        self.assertIn("dkms-add-0.2", result.stdout)
        self.assertLess(result.stdout.index("dkms-remove-0.1"),
                        result.stdout.index("dkms-add-0.2"))

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


def subprocess_run(script, manifest, environment, root):
    import subprocess
    completed = subprocess.run(
        ["bash", "-c", script, "test", str(manifest)],
        env=environment, text=True, capture_output=True)
    completed.load_conf = root / "modules-load.conf"
    return completed


if __name__ == "__main__":
    unittest.main()
