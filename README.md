# Thermal Icon

Tiny macOS menu-bar app that represents current CPU temperature with an icon instead of permanent digits.

- `thermometer.low`, `thermometer.medium`, or `thermometer.high` in menu bar
- exact temperature in tooltip and menu
- optional numeric menu-bar mode
- configurable warm/hot thresholds
- live fan RPM monitoring
- signed privileged helper with Quiet, Standard, and Ultra modes
- automatic fan reset when the app disconnects or the helper stops

Fan modes:

- **Quiet** — temperature-aware curve from 30%, rising to 100% by 90 °C
- **Standard** — restores Apple's automatic fan control
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

The build script signs the app and helper with the first available Developer ID Application or Apple Development identity. Fan writes are restricted to the three modes; arbitrary RPM values are intentionally unsupported. The warm/hot thresholds calibrate Quiet mode, while 90 °C always forces maximum speed.

Requires macOS 14 or later. CPU sensor mappings cover common Intel Macs and Apple M1–M5 generations.

## License

MIT. AppleSMC and signed-helper code is based on [Stats](https://github.com/exelban/stats) and [MacFanControl](https://github.com/achen4020/MacFanControl); see `THIRD_PARTY_NOTICES.md`.
