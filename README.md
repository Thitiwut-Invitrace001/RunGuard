# RunGuard

A native macOS menu bar app for keeping long-running development work awake.

## Build

Run `./build-app.sh`, then open `RunGuard.app`.

The bundled command runner keeps the Mac awake for the lifetime of one command:

```sh
RunGuard.app/Contents/MacOS/runguard -- python3 train.py
```

## Included

- Manual Keep Awake with a macOS idle-sleep assertion.
- Timers from 30 minutes to 8 hours.
- Charging-only behavior.
- Closed-Lid Mode using the macOS `pmset disablesleep` setting, with an administrator prompt, prior-setting restore, and battery/critical-thermal stop conditions.
- Auto Mode based on a small list of known developer process names.
- Battery and critical-thermal guardrails.
- A local activity history.
- A command wrapper that releases its assertion when the child command exits.

## Current limits

RunGuard does not yet implement a privileged helper, Smart Rules, push alerts/webhooks, weekly reports, or fan control. Closed-Lid Mode asks for administrator authorization each time it changes the system setting. If RunGuard crashes while the mode is active, the setting may remain enabled until RunGuard is opened again; the app restores the saved setting on its next launch. A plain sleep assertion cannot prevent macOS clamshell sleep. Closed-lid operation can trap heat, so use a hard ventilated surface and keep the battery and thermal protections enabled. Auto Mode is a process-name check, so it can keep the Mac awake while a watched app is idle. It recognizes only a small starter list of tools.

The feature list is based on REA inventory and static analysis of LidRun 1.2.31, plus the vendor's public [feature and pricing page](https://lidrun.com/pricing) and [closed-lid safety guide](https://lidrun.com/guide/closed-lid-safety). The source app is closed-source, so its full runtime behavior and Pro service behavior are not independently verified.

This first build is unsigned and intended for local development on macOS 13 or later.
