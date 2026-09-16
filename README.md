# RISC OS Clock

A tribute to the analogue **Clock** from RISC OS 3 (`!Clock` / the `!Alarm` analogue face): a white disc, twelve axis-aligned blue hour squares, grey kite hands, and a red second hand with a red centre boss.

Written in **Free Pascal**. Lazarus and Delphi are not required — `fpc` plus the platform GUI libraries already on the machine are enough. There is no 3D engine and no widget-toolkit theme to fight. The whole face is a software RGBA canvas; each host only uploads those bytes into a native window.

The clock:

- uses **local time**
- **jumps** the red second hand once a second (the original did not sweep)
- lets the hour and minute hands **creep** with the seconds, so 6:30 is halfway to 7
- stays **circular** when you stretch the window or go fullscreen
- can be expanded to **fullscreen** (F11, double-click, or the View menu)

How the pieces fit together (same style as Eyes, the calculator, and the savers): `WORKINGS.md` for responsibilities and hand math, `EXECUTION_FLOW.md` for a tick-by-tick trace.

## Requirements

- **Free Pascal** 3.2+ (`fpc` on your `PATH`)

macOS (Homebrew), Sonoma-compatible:

```bash
brew install fpc
```

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
```

Windows 10+: a native Free Pascal install (the `Windows` unit ships with FPC).

## Run

From the project root:

```bash
make
make run
```

That compiles to `build/` and opens `RISCOSClock.app` on macOS. The window is a real app with a Dock icon.

Or with Make on other OSes:

```bash
make linux      # Linux / Raspberry Pi OS window
make windows    # RISCOSClock.exe
make test       # headless angle checks (no GUI)
make snap       # three PPM frames of the canvas
make clean      # remove build/
```

Manual compile on macOS (Make still has to wrap the binary in the `.app` bundle):

```bash
fpc -Mobjfpc -Scgi -O2 -Fusrc -FUbuild -FEbuild -obuild/RISCOSClock src/clock.pas
make app
open build/RISCOSClock.app
```

## Using it

1. The face follows the system clock. The red hand jumps on each new second.
2. Drag a corner to resize. The disc stays round; RISC OS grey fills any extra strip.
3. **F11** (or **View → Full Screen**, or **double-click** the face) goes fullscreen. **Esc** leaves it. On macOS the green traffic-light button and **Ctrl+Cmd+F** do the same native fullscreen.
4. **Clock → About** describes the tribute. Closing the window quits.

## Where it appears

| OS | Presence |
|----|----------|
| **macOS** | Titled, resizable window, Dock icon, native fullscreen Space. |
| **Windows** | Titled, resizable window on the taskbar, F11 monitor-filling popup. |
| **Linux** | GTK 2 window (Raspberry Pi OS friendly), F11 `gtk_window_fullscreen`. |

Closing the window **quits** the process. This is a desk clock, not a menu extra.

## Project layout

```
src/
  clock.pas          # program; picks the host with {$IFDEF}
  uclockmodel.pas    # local time → hand angles, second-tick flag
  uclockrender.pas   # software RGBA canvas (disc, squares, kites)
  uclockapp.pas      # TClockController: resize, tick, present flag
  uhostcocoa.pas     # macOS NSWindow
  uhostwin.pas       # Windows HWND
  uhostgtk.pas       # Linux GtkWindow
  clocktest.pas      # headless angle checks
  clocksnap.pas      # paints PPM frames without a window
bundle/
  Info.plist         # retina-capable app bundle
Makefile
```
