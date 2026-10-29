#!/usr/bin/python3
"""Mirror session audio mute state to ASUS mute LEDs.

Uses the session audio server and logind (via brightnessctl), without root.
Reconciles once a second, including after resume and audio-server restarts.
Never changes audio state.

Speaker and microphone are independent. MUTE_LED_SPEAKER and MUTE_LED_MIC
are each "auto" (default), "on", or "off". "auto" writes an LED only while
its trigger is none, so it does not fight the kernel audio-mute or
audio-micmute trigger.
"""
import os
from pathlib import Path
import subprocess
import shutil
import time

os.environ["LC_ALL"] = "C"

SPEAKER = "platform::mute"
MIC = "platform::micmute"


def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL,
                                   timeout=3).strip()


def mode_for(device):
    key = "MUTE_LED_SPEAKER" if device == SPEAKER else "MUTE_LED_MIC"
    mode = os.environ.get(key, "auto").strip().lower()
    if mode not in ("auto", "on", "off"):
        raise ValueError(key + " must be auto, on, or off")
    return mode


def trigger_text(device):
    path = Path("/sys/class/leds") / device / "trigger"
    if not path.exists():
        return None
    return path.read_text()


def trigger_is_none(device):
    text = trigger_text(device)
    if text is None:
        return True
    selected = ""
    for token in text.split():
        if token.startswith("[") and token.endswith("]"):
            selected = token[1:-1]
            break
    return selected == "none"


def led_enabled(device):
    mode = mode_for(device)
    if mode == "off":
        return False
    if mode == "on":
        return True
    return trigger_is_none(device)


def update(device, muted):
    path = Path("/sys/class/leds") / device / "brightness"
    if path.exists() and path.read_text().strip() != str(int(muted)):
        run("brightnessctl", "--device=" + device, "set", str(int(muted)))


def sync():
    if led_enabled(SPEAKER):
        sink = (run("omarchy-audio-output-sink") if shutil.which("omarchy-audio-output-sink")
                else run("pactl", "get-default-sink"))
        if sink:
            update(SPEAKER, run("pactl", "get-sink-mute", sink) == "Mute: yes")
    if led_enabled(MIC):
        update(MIC, run("pactl", "get-source-mute", "@DEFAULT_SOURCE@") == "Mute: yes")


if __name__ == "__main__":
    last_error = None
    while True:
        try:
            sync()
            last_error = None
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            message = str(error)
            if message != last_error:
                print(message, flush=True)
                last_error = message
        time.sleep(1)
