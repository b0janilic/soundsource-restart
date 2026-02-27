# sourcesound-restart

Automatically restarts SoundSource before the trial mode noise kicks in (~20 min).

## The Problem

SoundSource's trial mode injects unbearable white noise every ~20 minutes, forcing you to manually
restart the app. If you use parametric EQ with a negative preamp (e.g. for EQ correction), this
restart causes a volume spike — the PEQ is momentarily inactive while SoundSource relaunches, and
USB DACs that ignore macOS software volume control have no way to compensate.

Without `media-control`, this script polls SoundSource's uptime and restarts it just before the
trial window ends. Same result, no human needed — but the volume spike still applies.

With `media-control`, the script restarts SoundSource *before* the noise ever fires, pausing your
player during the restart so the transition is completely seamless. The only exception is songs
longer than 20 minutes — the script can't wait for the next track, so it pauses mid-song instead.

## Setup

1. Clone to a **permanent location** — the installer writes the absolute path into the LaunchAgent.
   If you move the folder later, re-run `install` to update it.

2. Optionally install `media-control` for seamless restarts (no audio spike):
   ```bash
   brew install media-control
   ```

3. Install and start:
   ```bash
   ./sourcesound-install.sh install
   ```

> SoundSource should be in **System Settings → General → Login Items** so it relaunches
> automatically after being killed.

---

## Config

Optional overrides in `~/.config/sourcesound-restart/config`:

| Variable              | Default | Description                                                                 |
|-----------------------|---------|-----------------------------------------------------------------------------|
| `TRIAL_INTERVAL`      | `1200`  | Seconds in the trial window (20 min). Change only if SoundSource updates.   |
| `RESTART_MARGIN`      | `90`    | Restart this many seconds before the trial window ends.                     |
| `RESTART_DELAY`       | `3`     | Seconds to wait after killing SoundSource before relaunching.               |
| `MUTE_EXTRA_WAIT`     | `0`     | Extra seconds paused after relaunch (increase if PEQ/plugin init is slow).  |
| `POPUP_POLL_INTERVAL` | `3`     | Seconds between uptime checks (both modes).                                 |

---

## Resource usage

The script runs as a macOS LaunchAgent (background service, starts on login, restarts on crash).
It has negligible system impact: no CPU when idle, ~1 MB RAM. It wakes every ~8 seconds to poll
`media-control`, does a quick calculation, then sleeps again. No network access, no elevated
privileges, no daemons — just a bash script managed by launchd.

## Service management

```bash
./sourcesound-install.sh install    # Install and start
./sourcesound-install.sh status     # Check status + tail logs
./sourcesound-install.sh reload     # Reload after config change
./sourcesound-install.sh uninstall  # Stop and remove from login
```

Logs: `~/.config/sourcesound-restart/sourcesound-restart.log`
