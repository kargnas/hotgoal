# Thermal Icon

Tiny macOS menu-bar app that represents current CPU temperature with an icon instead of permanent digits.

- `thermometer.low`, `thermometer.medium`, or `thermometer.high` in menu bar
- exact temperature in tooltip and menu
- optional numeric menu-bar mode
- configurable warm/hot thresholds
- read-only AppleSMC access; no fan control or privileged helper

## Run

```bash
./script/build_and_run.sh --verify
```

Built app: `dist/Thermal Icon.app`

Requires macOS 14 or later. CPU sensor mappings cover common Intel Macs and Apple M1–M5 generations.

## License

MIT. AppleSMC protocol code is based on [Stats](https://github.com/exelban/stats); see `THIRD_PARTY_NOTICES.md`.
