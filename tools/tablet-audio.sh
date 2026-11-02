#!/bin/sh
# brave-os tablet audio/bluetooth diagnostic, version 2. Run in the live session: sudo sh tablet-audio.sh
# Prints a compact report (photograph it). Nothing persists in a live session.
# It plays a 2-second test tone on every audio output and records 3 seconds from the default input.
U=${SUDO_UID:-1000}; R=/run/user/$U
asuser() { sudo -u "#$U" env XDG_RUNTIME_DIR=$R "$@"; }
hr() { echo "---- $1"; }
hr "power-save state and model option"
cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null; cat /sys/module/snd_hda_intel/parameters/model 2>/dev/null
hr "controller/codec"
lspci -nn | grep -i audio
awk 'NR<=3' /proc/asound/card0/codec#0 2>/dev/null || ls /proc/asound/card0/ 2>/dev/null
grep -E 'Vendor Id|Subsystem Id|Revision Id' /proc/asound/card0/codec#0 2>/dev/null
hr "nhlt (digital mics table) and dsp modules"
ls /sys/firmware/acpi/tables/ | grep -i nhlt || echo "no NHLT table"
lsmod | grep -oE '^snd_(sof[a-z_]*|soc_skl|hda_intel|intel_dspcfg)' | sort -u | tr '\n' ' '; echo
hr "dmesg: audio driver decisions"
dmesg | grep -iE 'dsp|dmic|sof|snd_hda_intel|hdaudio' | grep -viE 'integrity|ACPI: SSDT|IO TLB|pps_core|PCI-DMA|ISO 9660|input:' | head -12
hr "speaker/mic pins (0x14 0x1b 0x12 0x13 0x19)"
awk '/^Node 0x1[2349b] /{p=1} /^Node /{if($2!~/0x1[2349b]/)p=0} p&&/Node|Pin Default|Pin-ctls|Amp-Out vals|EAPD/' /proc/asound/card0/codec#0 2>/dev/null | head -24
hr "pipewire (version 2 of this script)"
asuser wpctl status 2>&1 | grep -E 'Sinks:|Sources:|^ \│  [ *]+[0-9]+\.|^ │  [ *]+[0-9]+\.' | head -12
echo "default sink: $(asuser wpctl inspect @DEFAULT_AUDIO_SINK@ 2>&1 | grep -oE 'node.(description|name) = .*' | head -2 | tr '\n' ' ')"
echo "default source: $(asuser wpctl inspect @DEFAULT_AUDIO_SOURCE@ 2>&1 | grep -oE 'node.(description|name) = .*' | head -2 | tr '\n' ' ')"
hr "test tone on every sink (listen) and 3 s capture from the default source"
python3 - <<'PY'
import math, struct, wave
with wave.open('/tmp/tone.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000)
    frames = b''.join(struct.pack('<hh', int(12000*math.sin(2*math.pi*440*i/48000)), int(12000*math.sin(2*math.pi*440*i/48000))) for i in range(96000))
    w.writeframes(frames)
PY
chmod 644 /tmp/tone.wav
asuser wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>&1; asuser wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.0 2>&1
echo "playing 2 s on the default sink"; asuser pw-play /tmp/tone.wav 2>&1 | head -2
for name in $(asuser pw-cli list-objects Node 2>/dev/null | grep -oE 'node.name = "alsa_output[^"]*"' | cut -d\" -f2); do
    echo "playing 2 s on $name"; asuser pw-play --target "$name" /tmp/tone.wav 2>&1 | head -2
done
asuser wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 0 2>&1; asuser wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 1.0 2>&1
echo "recording 3 s from the default source (say something)"
rm -f /tmp/cap.wav; asuser pw-record -t 3s /tmp/cap.wav 2>&1 | head -2
python3 - <<'PY'
import struct, wave
try:
    with wave.open('/tmp/cap.wav') as w:
        n = w.getnframes(); d = w.readframes(n); ch = w.getnchannels()
        s = struct.unpack('<%dh' % (len(d)//2), d); peak = max(abs(x) for x in s) if s else 0
        print("capture: %d frames, %d ch, peak %d of 32767 (%s)" % (n, ch, peak, "signal" if peak > 500 else "silence"))
except Exception as e:
    print("capture failed:", e)
PY
hr "bluetooth"
lsusb | grep -iE '8087|bluetooth' || echo "no Intel/bluetooth USB device"
dmesg | grep -iE 'bluetooth|btusb|hci0' | head -4
bluetoothctl list 2>/dev/null | head -2 || true
echo "---- end"
