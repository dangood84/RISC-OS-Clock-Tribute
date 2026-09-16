# Execution flow: from `begin` to a drawn second

A step-by-step trace of what happens from `program RISCOSClock` through host initialisation and timer startup, down to how an individual second is calculated and drawn.

Default launch (`make run`) opens the **macOS window**. `make windows` / `make linux` use the same model and renderer; only the present step changes. This trace is **macOS** (`uhostcocoa`) unless a step says otherwise.

One thread does everything after startup:

- **main (Pascal, then Cocoa run loop)** — `HostRun`, `setup`, `tick:`, `redraw`, AppKit drawing

There is no Swing EDT. `NSTimer` and `NSWindow` run on the same thread that called `NSApplication.run`.

---

## Phase A — process entry

**1.** The OS loads `RISCOSClock.app/Contents/MacOS/RISCOSClock` (or `./build/RISCOSClock`). FPC unit initialisation runs (`TClockModel` is not constructed yet).

**2.** `program RISCOSClock` executes `HostRun`.

```pascal
{ src/clock.pas }
begin
  HostRun;
end.
```

**3.** `HostRun` (Cocoa):

```pascal
procedure HostRun;
var
  Pool: NSAutoreleasePool;
  App: NSApplication;
begin
  Pool := NSAutoreleasePool.alloc.init;
  App := NSApplication.sharedApplication;
  App.setActivationPolicy(NSApplicationActivationPolicyRegular);
  SharedApp := TAppDelegate.alloc.init;
  App.setDelegate(SharedApp);
  SharedApp.setup;
  App.run;
  Pool.release;
end.
```

Regular policy (no `LSUIElement`) means: **Dock icon**, Cmd-Tab, a real window. `App.run` does not return until Quit.

Windows: `HostRun` registers a window class, `CreateWindowEx` with `WS_OVERLAPPEDWINDOW`, `SetTimer`, then `GetMessage`.  
Linux: `gtk_init`, `gtk_window_new`, `g_timeout_add(100, ...)`, `gtk_main`.

---

## Phase B — window initialisation (`setup`)

**4.** `TAppDelegate.setup` is idempotent (`if ready then Exit`). `applicationDidFinishLaunching` calls it again after `App.run` has started; the second call is a no-op.

**5.** Pixel scale: `NSScreen.mainScreen.backingScaleFactor` (typically `2` on Sonoma retina). The controller buffer is in **pixels**; the window is in **points** (400×400 at launch).

**6.** `controller := TClockController.Create(Round(400 * scale), …)`:

- `TClockModel.Create` — `FFirst = True`, so the first `SyncFromSystem` counts as a second-tick
- `TPixelBuffer` allocated (RGBA)
- `NeedsPresent := True` so the first paint happens before the timer

**7.** Menu: About / Quit on the application menu, **Full Screen** (Ctrl+Cmd+F) on View.

**8.** Window: titled, closable, miniaturisable, **resizable**, `NSWindowCollectionBehaviorFullScreenPrimary` (green button is real fullscreen, not zoom-to-fit). Content view is `TClockView` (unflipped, so the y-down buffer is not drawn upside down).

**9.** `syncCanvasSize` reads `view.bounds × scale` and `Resize`s the buffer if AppKit's first layout is not exactly 400×400.

**10.** `redraw` → `controller.Render` → `RenderClock` → copy into a fresh `NSImage` → `setNeedsDisplay`. The window is not blank when it appears.

**11.** Timer is armed at **0.1 s** (10 Hz). That is only so we *notice* the second change quickly. The face is painted when `SecondTicked` (about 1 Hz), and whenever the window is resized.

```pascal
animTimer := NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
  0.1, self, objcselector('tick:'), nil, True);
```

**12.** `App.run` starts.

---

## Phase C — per-tick update (main thread, ~10 times per second)

**13.** The timer fires → `tick:`. A fresh `NSAutoreleasePool` wraps the tick.

**14.** `controller.Tick` → `TClockModel.SyncFromSystem`:

```pascal
procedure TClockModel.SyncFromSystem;
begin
  if FFrozen then
    Exit;          { snapshots / tests: Now() must not move the hands }
  DecodeTime(Now, H, M, S, MS);
  Apply(H, M, S, MS);
end;
```

**15.** `Apply` is the second-tick state change:

```pascal
FSecondTicked := FFirst or (S <> FSecond);
FHour := H;
FMinute := M;
FSecond := S;
```

Most ticks: `SecondTicked = False`, `NeedsPresent` stays false, `tick:` returns without drawing.  
On a new integer second: `NeedsPresent := True` and we fall through to Phase D.

Windows: `WM_TIMER` / `GetTickCount` is not used for time — still `Now`.  
Linux: `g_timeout_add` → `OnTick` → the same `Tick`.

---

## Phase D — draw (`redraw` then AppKit)

**16.** `controller.Render` asks `Model.Hands` for three angles:

```
hour   = ((H mod 12) + M/60 + S/3600) * (π/6)
minute = (M + S/60) * (π/30)
second = S * (π/30)          { integer seconds: a 6° jump }
```

0 radians is **12 o'clock**. Canvas y is down, so a point on the rim is `(cx + sin(a)·r, cy − cos(a)·r)`.

**17.** `RenderClock`:

1. Clear RISC OS grey `(192,192,192)`
2. Fill white disc, stroke black rim
3. Twelve **axis-aligned** blue squares on the hour marks
4. Grey kite hour hand, then minute hand
5. Thin red second hand
6. Red centre boss on top of the hub

**18.** `MakeImage` allocates an `NSBitmapImageRep` with **nil planes** (AppKit owns the bytes), copies `Canvas.Ptr` into `bitmapData`, wraps that in a new `NSImage`. The previous `frameImage` is released. Do **not** alias the Pascal buffer: AppKit would cache the first frame.

**19.** `TClockView.drawRect` fills grey and `frameImage.drawInRect`.

---

## Fullscreen (a different state, same draw loop)

**20.** User hits **F11**, **Ctrl+Cmd+F**, **View → Full Screen**, or **double-clicks** the face.

**21.** Cocoa: `window.toggleFullScreen(nil)`. AppKit animates into a Space.

**22.** `windowDidEnterFullScreen`:

```pascal
controller.SetFullScreen(True);  { record the state change }
syncCanvasSize;                  { buffer becomes screen × scale }
redraw;
```

**23.** `windowDidResize` also fires during the animation; each time the buffer is rebuilt so the disc stays circular.

**24.** **Esc** (or the same toggle) → `windowDidExitFullScreen` → `SetFullScreen(False)` → buffer shrinks back to the windowed size.

Windows: F11 saves the overlapped style and monitor-fills a popup.  
Linux: F11 calls `gtk_window_fullscreen` and hides the menu bar. A window-state event keeps `FullScreen` in sync if the WM toggled it.

---

## The repeating loop

```text
NSTimer (~100 ms, main thread)
  → tick:  Model.SyncFromSystem
  → if SecondTicked (or a resize already set NeedsPresent):
        Hands (three angles)
        RenderClock
        MakeImage copy → drawRect
  → wait for next timer event
```

Quit: menu **Quit** → `NSApplication.terminate`. Close box → `applicationShouldTerminateAfterLastWindowClosed` → process ends.

---

## Windows path (same draw loop)

`WM_TIMER` → `Tick` → if `NeedsPresent` then `Present`:

1. `RenderClock`
2. `CopyBGRA` (Windows DIB is BGRA)
3. `InvalidateRect` → `WM_PAINT` `StretchDIBits`

`WM_SIZE` rebuilds the buffer to the client size. `WM_LBUTTONDBLCLK` / `VK_F11` toggle the popup fullscreen.

---

## Linux path (same draw loop)

`OnTick` (glib timeout):

1. `Controller.Tick`
2. If dirty: `RenderClock`, copy RGBA into a `GdkPixbuf` (rowstride may be wider than `width*4`)
3. `gtk_widget_queue_draw` → `expose-event` `gdk_pixbuf_render_to_drawable`

`configure-event` on the drawing area is the resize path.

---

## One-line map

`begin HostRun` → `setup` (window + 10 Hz timer) → **`SyncFromSystem` until the second changes** → **`Hands` converts H:M:S to angles** → **`RenderClock` writes RGBA** → **host copies a snapshot onto the window**.

Debugger: `HostRun`, `TAppDelegate.setup`, `TClockModel.Apply`, `RenderClock`, `MakeImage`. The first `tick:` already paints; `FFirst` makes `SecondTicked` true even if the wall clock has not moved.

See also `WORKINGS.md` for class responsibilities, hand angles, and the clamp of the disc inside a non-square window.
