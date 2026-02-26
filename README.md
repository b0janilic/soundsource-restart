# sourcesound-restart

Automatically restarts SoundSource before the trial mode noise kicks in (~20 min).

## The Problem

SoundSource's trial mode injects white noise and disables all audio processing every ~20 minutes.
If you use parametric EQ with a negative preamp, this causes a sudden volume spike when the PEQ
is bypassed. This script restarts the app proactively, before that happens — pausing your music
player only when a restart is actually needed, so the transition is seamless.

## Files

```
<repo>/
├── sourcesound-restart.sh      # Main daemon — runs continuously in the background
└── sourcesound-install.sh      # Helper to install / uninstall / check status

~/.config/sourcesound-restart/
├── config                      # Optional overrides for the variables below
├── sourcesound-restart.log     # Script log
└── launchd.log                 # Raw stdout/stderr from launchd

~/Library/LaunchAgents/
└── com.user.sourcesound-restart.plist   # launchd service definition (must live here)
```

---

## How It Works

The mode is **auto-detected at startup** based on whether `media-control` is installed.

### With `media-control` (recommended)

Listens to the `media-control` event stream. At each new song:

1. Checks if `elapsed_since_restart + new_song_duration` would exceed the trial window
2. If yes → pauses the player, restarts SoundSource, resumes (seamless, no audio spike)
3. If no → does nothing (transition is unaffected)

Also checks for the trial popup every `POPUP_POLL_INTERVAL` seconds as a fallback
(catches songs longer than 20 minutes).

```
[new song] → [elapsed + duration > threshold?] → [pause] → [restart SS] → [resume]
                          ↓ no
                       (nothing)
```

Works with any player that supports the macOS NowPlaying API (Tidal, Spotify, Apple Music, etc.).

### Without `media-control` (fallback)

Polls the macOS Accessibility API for the SoundSource trial dialog every `POPUP_POLL_INTERVAL`
seconds, and restarts the moment it appears.

**Requires:** Terminal (or your shell) listed under **System Settings → Privacy & Security → Accessibility**.

> On USB DACs that ignore macOS software volume control, a brief audio spike may be audible in
> this mode since the player cannot be paused. Install `media-control` to avoid this.

---

## Setup

1. Grant Accessibility access (needed for popup detection in both modes):
   **System Settings → Privacy & Security → Accessibility → enable Terminal**

2. Install `media-control` for the best experience (seamless restarts with no audio spike):

   ```bash
   brew install media-control
   ```

3. Install and start the service:

   ```bash
   cd /path/to/sourcesound-restart
   ./sourcesound-install.sh install
   ```

> SoundSource should be in **System Settings → General → Login Items** so it relaunches
> automatically after being killed.

---

## Config reference

All variables are optional. To override defaults, add them to `~/.config/sourcesound-restart/config`.

| Variable              | Default | Description                                                                 |
|-----------------------|---------|-----------------------------------------------------------------------------|
| `TRIAL_INTERVAL`      | `1200`  | Seconds in the trial window (20 min). Change only if SoundSource updates.   |
| `RESTART_MARGIN`      | `90`    | Restart this many seconds before the trial window ends.                     |
| `RESTART_DELAY`       | `3`     | Seconds to wait after killing SoundSource before relaunching.               |
| `MUTE_EXTRA_WAIT`     | `0`     | Extra seconds paused after relaunch (increase if PEQ/plugin init is slow).  |
| `POPUP_POLL_INTERVAL` | `3`     | Seconds between popup checks (both modes).                                  |
| `POPUP_COOLDOWN`      | `300`   | Fallback popup mode only: seconds to skip checks after a restart.           |

---

## Service management

```bash
# Install and start
./sourcesound-install.sh install

# Check status + tail logs
./sourcesound-install.sh status

# Reload after config change
./sourcesound-install.sh reload

# Stop and remove from login
./sourcesound-install.sh uninstall
```

---

## Logs

```bash
tail -f ~/.config/sourcesound-restart/sourcesound-restart.log
```
