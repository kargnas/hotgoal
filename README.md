# Thermal Icon

Tiny macOS menu-bar app that represents current CPU temperature with an icon instead of permanent digits.

- `thermometer.low`, `thermometer.medium`, or `thermometer.high` in menu bar
- exact temperature in tooltip and menu
- optional numeric menu-bar mode
- configurable warm/hot thresholds
- live fan RPM monitoring
- signed privileged helper for System Automatic, 70%, 85%, and 100% fan boost
- automatic fan reset when the app disconnects or the helper stops

## Run

```bash
./script/build_and_run.sh --verify
```

Built app: `dist/Thermal Icon.app`

Fan control setup:

1. Quit other fan controllers such as Macs Fan Control.
2. Choose **Fan Control → Enable Fan Control…**.
3. Approve **Thermal Icon.app** in **System Settings → General → Login Items & Extensions**.

The build script signs the app and helper with the first available Developer ID Application or Apple Development identity. Fan writes are restricted to safe boost presets; arbitrary low RPM values are intentionally unsupported.

Requires macOS 14 or later. CPU sensor mappings cover common Intel Macs and Apple M1–M5 generations.

## License

MIT. AppleSMC and signed-helper code is based on [Stats](https://github.com/exelban/stats) and [MacFanControl](https://github.com/achen4020/MacFanControl); see `THIRD_PARTY_NOTICES.md`.
