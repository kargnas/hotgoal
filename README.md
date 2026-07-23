# Thermal Icon

Tiny macOS menu-bar app that represents current CPU temperature with an animated thermometer.

- compact thermometer icon in the menu bar
- exact temperature in tooltip and menu
- optional icon-and-number menu-bar mode
- continuously temperature-colored Thermal Motes animation
- configurable warm/hot thresholds
- live fan RPM monitoring
- signed privileged helper with Muted, Quiet, Standard, and Ultra modes
- automatic fan reset when the app disconnects or the helper stops

Fan modes:

- **Muted** — Apple automatic fan control, allowing zero RPM when the system considers it safe
- **Quiet** — 1,500 RPM minimum through the hot threshold, rising to maximum by 90 °C
- **Standard** — 1,800 RPM minimum through the hot threshold, rising to maximum by 90 °C
- **Ultra** — fixed 100% fan speed

Quiet and Standard hold small 3 °C cooldown fluctuations and lower RPM more slowly than they raise it, preventing audible fan-speed hunting. The 90 °C maximum-speed rule bypasses this stabilization immediately.

## Run

```bash
./script/build_and_run.sh --verify
```

Built app: `dist/Thermal Icon.app`

Fan control setup:

1. Quit other fan controllers such as Macs Fan Control.
2. Choose **Fan Control → Enable Fan Control…**.
3. Approve **Thermal Icon.app** in **System Settings → General → Login Items & Extensions**.

The build script signs the app and helper with the first available Developer ID Application or Apple Development identity. Fan control is restricted to the four modes; arbitrary RPM values are intentionally unsupported. The hot threshold starts Quiet and Standard ramping, while 90 °C always forces maximum speed. Quitting the app or losing the helper connection restores Apple's automatic control.

Icon colors move continuously from blue through cyan, green, and yellow to red. Mercury level follows temperature and fills the tube near 95 °C. Rising motes alternate left and right: Cool shows one slowly, Warm shows two, and Hot shows four faster motes. macOS Reduce Motion keeps the color and thermometer level while removing particle movement.

Requires macOS 14 or later. CPU sensor mappings cover common Intel Macs and Apple M1–M5 generations.

## License

MIT. AppleSMC, signed-helper, and fan-stabilization code is based on [Stats](https://github.com/exelban/stats), [MacFanControl](https://github.com/achen4020/MacFanControl), and [smctl](https://github.com/leaperone/smctl); see `THIRD_PARTY_NOTICES.md`.
