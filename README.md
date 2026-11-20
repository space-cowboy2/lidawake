# LidAwake

A macOS menu bar toggle for `pmset -a disablesleep`. When it is on, the Mac stays awake with the lid closed, so other devices can still SSH in.

- Red bolt icon: on, the Mac stays awake with the lid closed.
- Moon icon: off, the Mac sleeps normally.

The state is read from `pmset -g` every time, so the icon stays correct if the setting changes outside the app.

## Build and install

Requires the Xcode command line tools (`swiftc`) and macOS 13 or later.

```bash
./build.sh
```

This compiles `main.swift`, ad-hoc signs the app, quits any running copy, and replaces `/Applications/LidAwake.app`.

## What it changes on the Mac

| Change | When | Undo |
| --- | --- | --- |
| `pmset -a disablesleep 1` | Keep Awake is turned on | Turn Off in the menu, or `sudo pmset -a disablesleep 0` |
| `/etc/sudoers.d/lidawake` | Skip Password Prompts is ticked | Untick it, or `sudo rm /etc/sudoers.d/lidawake` |
| Login item | Launch at Login is ticked | Untick it, or remove it in System Settings > General > Login Items |

The sudoers rule allows only `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password, and is checked with `visudo` before it is installed.

Quitting from the menu turns keep-awake off first. So does `kill`, `pkill`, logout and restart, as long as Skip Password Prompts is ticked (there is no password dialog at that point). A force kill (`kill -9`) or a crash cannot be caught: check with `pmset -g | grep SleepDisabled`.

The menu also shows whether SSH (Remote Login) is reachable on port 22.
