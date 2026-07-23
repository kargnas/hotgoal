# Thermal Icon

Tiny macOS menu-bar app that represents current CPU temperature with an icon instead of permanent digits.

- compact thermometer icon in the menu bar
- exact temperature in tooltip and menu
- optional numeric menu-bar mode
- temperature-colored Thermal Motes animation in icon mode
- configurable warm/hot thresholds
- live fan RPM monitoring
- signed privileged helper with Quiet, Standard, and Ultra modes
- automatic fan reset when the app disconnects or the helper stops

Fan modes:

- **Quiet** — hardware-minimum speed through the hot threshold, rising to maximum by 90 °C
- **Standard** — 1,800 RPM minimum through the hot threshold, rising to maximum by 90 °C
- **Ultra** — fixed 100% fan speed

## Run

```bash
./script/build_and_run.sh --verify
```

Built app: `dist/Thermal Icon.app`

Fan control setup:

1. Quit other fan controllers such as Macs Fan Control.
2. Choose **Fan Control → Enable Fan Control…**.
3. Approve **Thermal Icon.app** in **System Settings → General → Login Items & Extensions**.

The build script signs the app and helper with the first available Developer ID Application or Apple Development identity. Fan writes are restricted to the three modes; arbitrary RPM values are intentionally unsupported. The hot threshold starts Quiet and Standard ramping, while 90 °C always forces maximum speed. Quitting the app or losing the helper connection restores Apple's automatic control.

Icon colors are cyan for Cool, amber for Warm, and red for Hot. Warm shows two rising motes; Hot shows four faster motes. macOS Reduce Motion keeps the color and thermometer level while removing particle movement.

Requires macOS 14 or later. CPU sensor mappings cover common Intel Macs and Apple M1–M5 generations.

## License

MIT. AppleSMC and signed-helper code is based on [Stats](https://github.com/exelban/stats) and [MacFanControl](https://github.com/achen4020/MacFanControl); see `THIRD_PARTY_NOTICES.md`.
