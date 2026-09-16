unit uhostcocoa;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

{ macOS titled, resizable window. Regular activation policy so there is a
  Dock icon. Same TClockController as Windows/Linux; this unit presents
  pixels, runs the 10 Hz timer, and forwards fullscreen / double-click. }

interface

procedure HostRun;

implementation

uses
  SysUtils, Math, CocoaAll, uclockapp;

const
  WinPoints = 400;
  MinPoints = 160;
  TickInterval = 0.1; { 10 Hz: notice the second change quickly, paint once a second }

type
  TClockView = objcclass;
  TClockWindow = objcclass;

  NSBitmapImageRepClock = objccategory external (NSBitmapImageRep)
    function initRGBA(planes: Pointer; aWidth: NSInteger; aHeight: NSInteger;
      aBits: NSInteger; aSamples: NSInteger; aAlpha: ObjCBOOL;
      aPlanar: ObjCBOOL; aSpace: NSString; aBpr: NSInteger;
      aBpp: NSInteger): id; message 'initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:';
  end;

  TAppDelegate = objcclass(NSObject, NSApplicationDelegateProtocol, NSWindowDelegateProtocol)
  public
    controller: TClockController;
    window: TClockWindow;
    view: TClockView;
    frameImage: NSImage;
    animTimer: NSTimer;
    scale: Double;
    ready: ObjCBOOL;
    procedure applicationDidFinishLaunching(notification: NSNotification); message 'applicationDidFinishLaunching:';
    function applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL; message 'applicationShouldTerminateAfterLastWindowClosed:';
    procedure quitAction(sender: id); message 'quitAction:';
    procedure aboutAction(sender: id); message 'aboutAction:';
    procedure fullscreenAction(sender: id); message 'fullscreenAction:';
    procedure windowDidResize(notification: NSNotification); message 'windowDidResize:';
    procedure windowDidEnterFullScreen(notification: NSNotification); message 'windowDidEnterFullScreen:';
    procedure windowDidExitFullScreen(notification: NSNotification); message 'windowDidExitFullScreen:';
    procedure tick(timer: NSTimer); message 'tick:';
    procedure redraw; message 'redraw';
    procedure syncCanvasSize; message 'syncCanvasSize';
    procedure setup; message 'setup';
  end;

  TClockWindow = objcclass(NSWindow)
  public
    app: TAppDelegate;
    function canBecomeKeyWindow: ObjCBOOL; override;
  end;

  TClockView = objcclass(NSView)
  public
    app: TAppDelegate;
    procedure drawRect(dirtyRect: NSRect); override;
    function acceptsFirstResponder: ObjCBOOL; override;
    function acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL; override;
    procedure mouseDown(event: NSEvent); override;
    procedure keyDown(event: NSEvent); override;
  end;

var
  SharedApp: TAppDelegate;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

function MakeImage(Pixels: PByte; PixelW, PixelH: Integer; PointW, PointH: Double): NSImage;
var
  Rep: NSBitmapImageRep;
  Dest: PByte;
  Bytes: Integer;
begin
  Rep := NSBitmapImageRep(NSBitmapImageRep.alloc.initRGBA(nil, PixelW, PixelH, 8, 4,
    True, False, NSCalibratedRGBColorSpace, PixelW * 4, 32));
  { nil planes: AppKit owns a snapshot. Aliasing Canvas.Ptr would freeze the face. }
  Result := NSImage.alloc.initWithSize(NSMakeSize(PointW, PointH));
  if Rep <> nil then
  begin
    Dest := PByte(Rep.bitmapData);
    Bytes := PixelW * PixelH * 4;
    if (Dest <> nil) and (Pixels <> nil) and (Bytes > 0) then
      Move(Pixels^, Dest^, Bytes);
    Result.addRepresentation(Rep);
    Rep.release;
  end;
  Result.setCacheMode(NSImageCacheNever);
end;

procedure TAppDelegate.redraw;
var
  B: NSRect;
begin
  if (controller = nil) or (view = nil) then
    Exit;
  controller.Render;
  B := view.bounds;
  if frameImage <> nil then
    frameImage.release;
  frameImage := MakeImage(controller.Canvas.Ptr, controller.Canvas.Width,
    controller.Canvas.Height, B.size.width, B.size.height);
  controller.ConsumePresent;
  view.setNeedsDisplay_(True);
end;

procedure TAppDelegate.syncCanvasSize;
var
  B: NSRect;
  PW, PH: Integer;
begin
  if (view = nil) or (controller = nil) then
    Exit;
  B := view.bounds;
  PW := Max(1, Round(B.size.width * scale));
  PH := Max(1, Round(B.size.height * scale));
  controller.Resize(PW, PH);
end;

procedure TAppDelegate.tick(timer: NSTimer);
var
  Pool: NSAutoreleasePool;
begin
  Pool := NSAutoreleasePool.alloc.init;
  if controller <> nil then
  begin
    controller.Tick;
    if controller.NeedsPresent then
      redraw;
  end;
  Pool.release;
end;

procedure SetupMenu(Del: TAppDelegate);
var
  MainMenu, AppMenu, ViewMenu: NSMenu;
  AppItem, ViewItem, Item: NSMenuItem;
begin
  MainMenu := NSMenu.alloc.init;

  AppItem := NSMenuItem.alloc.init;
  AppMenu := NSMenu.alloc.initWithTitle(NSStr('Clock'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('About RISC OS Clock'), objcselector('aboutAction:'), NSStr(''));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppMenu.addItem(NSMenuItem.separatorItem);
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Quit RISC OS Clock'), objcselector('quitAction:'), NSStr('q'));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppItem.setSubmenu(AppMenu);
  MainMenu.addItem(AppItem);

  ViewItem := NSMenuItem.alloc.init;
  ViewMenu := NSMenu.alloc.initWithTitle(NSStr('View'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Full Screen'), objcselector('fullscreenAction:'), NSStr('f'));
  { Ctrl+Cmd+F — the same chord macOS uses for native fullscreen. }
  Item.setKeyEquivalentModifierMask(NSCommandKeyMask or NSControlKeyMask);
  Item.setTarget(Del);
  ViewMenu.addItem(Item);
  Item.release;
  ViewItem.setSubmenu(ViewMenu);
  MainMenu.addItem(ViewItem);

  NSApplication.sharedApplication.setMainMenu(MainMenu);
  ViewMenu.release;
  ViewItem.release;
  AppMenu.release;
  AppItem.release;
  MainMenu.release;
end;

procedure TAppDelegate.setup;
var
  PixelScale: Double;
  Style: NSUInteger;
  Rect, Vis: NSRect;
begin
  if ready then
    Exit;
  ready := True;

  PixelScale := 2;
  if NSScreen.mainScreen <> nil then
    PixelScale := NSScreen.mainScreen.backingScaleFactor;
  if PixelScale < 1 then
    PixelScale := 1;
  scale := PixelScale;

  controller := TClockController.Create(
    Round(WinPoints * scale), Round(WinPoints * scale));

  SetupMenu(self);

  Style := NSTitledWindowMask or NSClosableWindowMask or
    NSMiniaturizableWindowMask or NSResizableWindowMask;
  Rect := NSMakeRect(120, 80, WinPoints, WinPoints);
  if NSScreen.mainScreen <> nil then
  begin
    Vis := NSScreen.mainScreen.visibleFrame;
    Rect := NSMakeRect(
      Vis.origin.x + Trunc((Vis.size.width - WinPoints) / 2),
      Vis.origin.y + Trunc((Vis.size.height - WinPoints) / 2),
      WinPoints, WinPoints);
  end;
  window := TClockWindow.alloc.initWithContentRect_styleMask_backing_defer(
    Rect, Style, NSBackingStoreBuffered, False);
  window.app := self;
  window.setTitle(NSStr('Clock'));
  window.setReleasedWhenClosed(False);
  window.setOpaque(True);
  window.setBackgroundColor(NSColor.colorWithCalibratedRed_green_blue_alpha(0.75, 0.75, 0.75, 1.0));
  window.setContentMinSize(NSMakeSize(MinPoints, MinPoints));
  { Sonoma green-button fullscreen, not just zoom-to-fit. }
  window.setCollectionBehavior(NSWindowCollectionBehaviorFullScreenPrimary);
  window.setDelegate(self);

  view := TClockView.alloc.initWithFrame(NSMakeRect(0, 0, WinPoints, WinPoints));
  view.app := self;
  window.setContentView(view);
  window.makeFirstResponder(view);

  syncCanvasSize;
  redraw;

  animTimer := NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(
    TickInterval, self, objcselector('tick:'), nil, True);
  animTimer.retain;
  NSRunLoop.currentRunLoop.addTimer_forMode(animTimer, NSRunLoopCommonModes);

  NSApplication.sharedApplication.activateIgnoringOtherApps(True);
  window.makeKeyAndOrderFront(nil);
end;

procedure TAppDelegate.applicationDidFinishLaunching(notification: NSNotification);
begin
  setup;
end;

function TAppDelegate.applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL;
begin
  Result := True;
end;

procedure TAppDelegate.quitAction(sender: id);
begin
  NSApplication.sharedApplication.terminate(nil);
end;

procedure TAppDelegate.aboutAction(sender: id);
var
  Alert: NSAlert;
begin
  Alert := NSAlert.alloc.init;
  Alert.setMessageText(NSStr(ClockAboutTitle));
  Alert.setInformativeText(NSStr(ClockAboutText));
  Alert.runModal;
  Alert.release;
end;

procedure TAppDelegate.fullscreenAction(sender: id);
begin
  if window <> nil then
    window.toggleFullScreen(nil); { AppKit animates; DidEnter/DidExit update the model }
end;

procedure TAppDelegate.windowDidResize(notification: NSNotification);
begin
  syncCanvasSize;
  redraw;
end;

procedure TAppDelegate.windowDidEnterFullScreen(notification: NSNotification);
begin
  { State change: windowed → macOS fullscreen Space. }
  if controller <> nil then
    controller.SetFullScreen(True);
  syncCanvasSize;
  redraw;
end;

procedure TAppDelegate.windowDidExitFullScreen(notification: NSNotification);
begin
  { State change: fullscreen Space → titled window. }
  if controller <> nil then
    controller.SetFullScreen(False);
  syncCanvasSize;
  redraw;
end;

procedure TClockView.drawRect(dirtyRect: NSRect);
begin
  NSColor.colorWithCalibratedRed_green_blue_alpha(0.75, 0.75, 0.75, 1.0).set_;
  NSRectFill(self.bounds);
  if (app = nil) or (app.frameImage = nil) then
    Exit;
  app.frameImage.drawInRect_fromRect_operation_fraction(self.bounds, NSZeroRect,
    NSCompositeSourceOver, 1.0);
end;

function TClockView.acceptsFirstResponder: ObjCBOOL;
begin
  Result := True;
end;

function TClockView.acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL;
begin
  Result := True;
end;

procedure TClockView.mouseDown(event: NSEvent);
begin
  if app = nil then
    Exit;
  self.window.makeFirstResponder(self);
  if (event <> nil) and (event.clickCount >= 2) then
    app.fullscreenAction(nil); { double-click the face to toggle fullscreen }
end;

procedure TClockView.keyDown(event: NSEvent);
var
  Code: Word;
begin
  if (app = nil) or (event = nil) then
  begin
    inherited keyDown(event);
    Exit;
  end;
  Code := event.keyCode;
  case Code of
    53: { Escape }
      if app.controller.FullScreen then
        app.fullscreenAction(nil)
      else
        inherited keyDown(event);
    103: { F11 }
      app.fullscreenAction(nil);
    else
      inherited keyDown(event);
  end;
end;

function TClockWindow.canBecomeKeyWindow: ObjCBOOL;
begin
  Result := True;
end;

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
end;

end.
