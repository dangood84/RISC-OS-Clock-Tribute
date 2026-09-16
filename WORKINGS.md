# How RISC OS Clock works

This note is for someone who wants to **build and run** the tribute on each OS, and to see how a small Free Pascal desktop clock is structured: where it starts, who owns time, who paints pixels, and how fullscreen is wired.

You do not need to be a Cocoa, Win32, or GTK expert. The same ideas show up in Eyes and Goody's Calculator: an entry point, a model, a software canvas, and a native host that only presents bytes.

There is **no Lazarus form**. The face is a white disc, twelve blue squares, and three hands. Each second those numbers are turned into RGBA pixels. The host uploads that buffer to a window.

## Build / run workflows

Work from the project root. `fpc` must be on `PATH`. Output always lands in `build/` (gitignored).

| What you want | Command | What you get |
|---------------|---------|--------------|
| macOS app | `make` then `make run` | `build/RISCOSClock.app`, opened |
| Linux / Raspberry Pi OS | `sudo apt install fpc libgtk2.0-dev` then `make linux` then `./build/riscosclock` | GTK 2 window |
| Windows 10+ | from a native FPC prompt: `make windows` then `build\RISCOSClock.exe` | taskbar window |
| Headless angle checks | `make test` | prints `ok` lines; non-zero if an angle is wrong |
| Frozen canvas frames | `make snap` | `build/snap-1010.ppm`, `snap-632.ppm`, `snap-wide.ppm` |
| Start over | `make clean` | deletes `build/` |

macOS (Homebrew, Sonoma+):

```bash
brew install fpc
make
make run
```

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
make linux
./build/riscosclock
```

Windows: install FPC, open its command prompt so `fpc` is on `PATH`, then `make windows`. The `Windows` unit ships with FPC; no extra SDK is required for this app.

Only **one** host unit is compiled. `{$IFDEF DARWIN}` / `WINDOWS` / else picks `uhostcocoa`, `uhostwin`, or `uhostgtk`. Cross-compiling the GUI hosts is not a supported workflow — build on the OS you want to run on.

## Fullscreen workflow (all three hosts)

| Action | macOS | Windows | Linux |
|--------|-------|---------|-------|
| Menu | **View → Full Screen** | **View → Full Screen** | **View → Full Screen** |
| Key | **Ctrl+Cmd+F**, **F11** | **F11** | **F11** |
| Mouse | double-click the face | double-click the face | double-click the face |
| Leave | **Esc**, or the same toggle | **Esc** or **F11** | **Esc** or **F11** |
| What the OS does | native fullscreen Space (`toggleFullScreen`) | popup covering the current monitor | `gtk_window_fullscreen` |

Resize (drag a corner, maximise, or enter fullscreen) always **rebuilds** the pixel buffer to the new client size. The disc uses `min(width, height) * 0.46`, so a widescreen fullscreen is a round clock on RISC OS grey, not an oval.

## Mental model

```
clock.pas begin
  → HostRun                    # uhostcocoa / uhostwin / uhostgtk
      → create TClockController (model + pixel buffer)
      → create titled, resizable window
      → timer (~10 Hz)
           → Model.SyncFromSystem (local time, SecondTicked)
           → if second changed or the window resized:
                 RenderClock (RGBA pixels)
                 host shows the buffer
```

| Layer | Unit | Tester-friendly analogy |
|-------|------|-------------------------|
| Entry / routing | `clock.pas` | Test runner that picks the OS host at compile time |
| State | `uclockmodel` | Fixture: hour/minute/second and the three angles |
| Composer | `uclockapp` | Holds the model and the canvas; `NeedsPresent` is the dirty flag |
| View | `uclockrender` | The thing that actually paints disc / squares / kites |
| Window shell | `uhostcocoa` / `uhostwin` / `uhostgtk` | Window, timer, fullscreen, About / Quit |

The hosts are **event-driven**. Almost everything after `HostRun` runs on the GUI thread. That is why the clock uses `NSTimer` / `SetTimer` / `g_timeout_add` instead of a raw `while true` loop.

## Unit responsibilities

### `clock.pas` — composition root

- Picks the host with `{$IFDEF}`
- Calls `HostRun`
- Does **not** decode time or draw hands

### `uclockmodel` — time → angles

- `SyncFromSystem` reads local `Now` unless `Freeze` was called
- `SecondTicked` is true on the first sample and whenever the integer second changes
- Angles: 0 = 12 o'clock, clockwise. The second hand uses **integer** seconds (a jump). Hour and minute include the smaller units so 6:30 sits between 6 and 7.

This unit has no Cocoa/Win32/GTK types.

### `uclockrender` — software canvas

- `TPixelBuffer`: packed RGBA (`Width × Height × 4`)
- `RenderClock`: grey clear, white disc, black rim, twelve **axis-aligned** blue squares, grey kite hands, red second hand, red boss
- The squares staying axis-aligned (not rotated into radial ticks) is the RISC OS tell

### `uclockapp` — one controller

- Owns `TClockModel` and `TPixelBuffer`
- `Tick` → `SyncFromSystem`; sets `NeedsPresent` when the second jumps
- `Resize` rebuilds the buffer when the host's client area changes
- `SetFullScreen` only **records** the host's presentation change

### Hosts

- **Cocoa:** `NSWindow` with `NSResizableWindowMask` and `NSWindowCollectionBehaviorFullScreenPrimary`. Timer 0.1 s. Backing store is `bounds × backingScaleFactor`.
- **Win32:** `WS_OVERLAPPEDWINDOW`, `WM_TIMER` 100 ms, `StretchDIBits`. F11 strips the frame and covers the monitor.
- **GTK 2:** `gtk_window_set_resizable`, `g_timeout_add(100, ...)`, drawing area + `GdkPixbuf`. F11 calls `gtk_window_fullscreen`.

## Debugger map

Break on `HostRun`, `TClockModel.SyncFromSystem`, `TClockModel.Apply` (the second-tick state change), `RenderClock`, and the host present (`redraw` / `Present` / `OnExpose`). You will see: **timer → maybe a new second → paint disc and hands → upload**.
