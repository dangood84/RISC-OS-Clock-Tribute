unit uhostwin;

{$mode objfpc}{$H+}

{ Windows titled, resizable window on the taskbar. Same TClockController
  as macOS; this unit presents pixels (BGRA StretchDIBits), a 100 ms
  timer, and F11 / double-click fullscreen. }

interface

procedure HostRun;

implementation

{$IFDEF WINDOWS}

uses
  Windows, Messages, SysUtils, uclockrender, uclockapp;

const
  AppName = 'RISCOSClockWnd';
  CmdAbout = 1001;
  CmdQuit = 1002;
  CmdFullScreen = 1003;
  WinSize = 400;
  MinSize = 160;
  TickId = 1;
  TickMs = 100;

var
  Controller: TClockController;
  MainWnd: HWND;
  Bgra: array of Byte;
  AppMenuBar: HMENU;
  FullScreen: Boolean;
  SavedStyle: LONG;
  SavedRect: TRect;
  SavedMenu: HMENU;

procedure Present(Wnd: HWND);
begin
  Controller.Render;
  SetLength(Bgra, Controller.Canvas.Width * Controller.Canvas.Height * 4);
  CopyBGRA(Controller.Canvas, @Bgra[0]);
  Controller.ConsumePresent;
  InvalidateRect(Wnd, nil, False);
end;

procedure PaintClock(Wnd: HWND);
var
  PS: PAINTSTRUCT;
  DC: HDC;
  Info: BITMAPINFO;
  R: TRect;
begin
  DC := BeginPaint(Wnd, @PS);
  GetClientRect(Wnd, @R);
  if Length(Bgra) = Controller.Canvas.Width * Controller.Canvas.Height * 4 then
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
    Info.bmiHeader.biWidth := Controller.Canvas.Width;
    Info.bmiHeader.biHeight := -Controller.Canvas.Height;
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    StretchDIBits(DC, 0, 0, R.Right - R.Left, R.Bottom - R.Top,
      0, 0, Controller.Canvas.Width, Controller.Canvas.Height,
      @Bgra[0], Info, DIB_RGB_COLORS, SRCCOPY);
  end;
  EndPaint(Wnd, @PS);
end;

procedure SyncCanvas(Wnd: HWND);
var
  R: TRect;
  CW, CH: Integer;
begin
  if not GetClientRect(Wnd, R) then
    Exit;
  CW := R.Right - R.Left;
  CH := R.Bottom - R.Top;
  if (CW < 1) or (CH < 1) then
    Exit;
  Controller.Resize(CW, CH);
end;

procedure ShowAbout(Wnd: HWND);
begin
  MessageBox(Wnd, PChar(ClockAboutText), ClockAboutTitle, MB_OK or MB_ICONINFORMATION);
end;

procedure EnterFullScreen(Wnd: HWND);
var
  Mi: TMonitorInfo;
  Mon: HMONITOR;
  Style: LONG;
begin
  if FullScreen then
    Exit;
  { State change: overlapped window → monitor-filling popup. }
  GetWindowRect(Wnd, SavedRect);
  SavedStyle := GetWindowLong(Wnd, GWL_STYLE);
  SavedMenu := GetMenu(Wnd);
  SetMenu(Wnd, 0);
  Style := SavedStyle and not (WS_CAPTION or WS_THICKFRAME or WS_BORDER or WS_SYSMENU);
  SetWindowLong(Wnd, GWL_STYLE, Style or WS_POPUP);
  FillChar(Mi, SizeOf(Mi), 0);
  Mi.cbSize := SizeOf(Mi);
  Mon := MonitorFromWindow(Wnd, MONITOR_DEFAULTTONEAREST);
  GetMonitorInfo(Mon, @Mi);
  SetWindowPos(Wnd, HWND_TOP,
    Mi.rcMonitor.Left, Mi.rcMonitor.Top,
    Mi.rcMonitor.Right - Mi.rcMonitor.Left,
    Mi.rcMonitor.Bottom - Mi.rcMonitor.Top,
    SWP_FRAMECHANGED or SWP_SHOWWINDOW);
  FullScreen := True;
  Controller.SetFullScreen(True);
end;

procedure LeaveFullScreen(Wnd: HWND);
begin
  if not FullScreen then
    Exit;
  { State change: popup → titled, resizable window. }
  SetWindowLong(Wnd, GWL_STYLE, SavedStyle);
  SetMenu(Wnd, SavedMenu);
  SetWindowPos(Wnd, HWND_TOP,
    SavedRect.Left, SavedRect.Top,
    SavedRect.Right - SavedRect.Left,
    SavedRect.Bottom - SavedRect.Top,
    SWP_FRAMECHANGED or SWP_SHOWWINDOW);
  FullScreen := False;
  Controller.SetFullScreen(False);
end;

procedure ToggleFullScreen(Wnd: HWND);
begin
  if FullScreen then
    LeaveFullScreen(Wnd)
  else
    EnterFullScreen(Wnd);
end;

function WndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  MinTrack: PMINMAXINFO;
begin
  Result := 0;
  case Msg of
    WM_CREATE:
      begin
        SetTimer(Wnd, TickId, TickMs, nil);
        SyncCanvas(Wnd);
        Present(Wnd);
      end;
    WM_TIMER:
      if WParam = TickId then
      begin
        Controller.Tick;
        if Controller.NeedsPresent then
          Present(Wnd);
      end;
    WM_PAINT:
      PaintClock(Wnd);
    WM_SIZE:
      begin
        SyncCanvas(Wnd);
        Present(Wnd);
      end;
    WM_GETMINMAXINFO:
      begin
        MinTrack := PMINMAXINFO(LParam);
        MinTrack^.ptMinTrackSize.X := MinSize + 32;
        MinTrack^.ptMinTrackSize.Y := MinSize + 48;
      end;
    WM_LBUTTONDBLCLK:
      ToggleFullScreen(Wnd);
    WM_KEYDOWN:
      case WParam of
        VK_F11:
          ToggleFullScreen(Wnd);
        VK_ESCAPE:
          if FullScreen then
            LeaveFullScreen(Wnd);
      end;
    WM_COMMAND:
      case LOWORD(WParam) of
        CmdAbout:
          ShowAbout(Wnd);
        CmdFullScreen:
          ToggleFullScreen(Wnd);
        CmdQuit:
          PostQuitMessage(0);
      end;
    WM_DESTROY:
      begin
        KillTimer(Wnd, TickId);
        PostQuitMessage(0);
      end;
    else
      Result := DefWindowProc(Wnd, Msg, WParam, LParam);
  end;
end;

function BuildMenu: HMENU;
var
  Bar, ClockMenu, ViewMenu: HMENU;
begin
  Bar := CreateMenu;
  ClockMenu := CreatePopupMenu;
  AppendMenu(ClockMenu, MF_STRING, CmdAbout, '&About RISC OS Clock...');
  AppendMenu(ClockMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(ClockMenu, MF_STRING, CmdQuit, 'E&xit');
  AppendMenu(Bar, MF_POPUP, ClockMenu, '&Clock');
  ViewMenu := CreatePopupMenu;
  AppendMenu(ViewMenu, MF_STRING, CmdFullScreen, '&Full Screen'#9'F11');
  AppendMenu(Bar, MF_POPUP, ViewMenu, '&View');
  Result := Bar;
end;

procedure HostRun;
var
  WC: WNDCLASS;
  Msg: TMsg;
  Wr: TRect;
  Style: DWORD;
begin
  Controller := TClockController.Create(WinSize, WinSize);
  FullScreen := False;
  AppMenuBar := BuildMenu;

  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := GetStockObject(LTGRAY_BRUSH);
  WC.lpszClassName := AppName;
  WC.style := CS_DBLCLKS or CS_HREDRAW or CS_VREDRAW; { double-click toggles fullscreen }
  RegisterClass(WC);

  Style := WS_OVERLAPPEDWINDOW;
  Wr.Left := 0;
  Wr.Top := 0;
  Wr.Right := WinSize;
  Wr.Bottom := WinSize;
  AdjustWindowRect(Wr, Style, True);

  MainWnd := CreateWindowEx(WS_EX_APPWINDOW, AppName, 'Clock',
    Style,
    CW_USEDEFAULT, CW_USEDEFAULT, Wr.Right - Wr.Left, Wr.Bottom - Wr.Top,
    0, AppMenuBar, HInstance, nil);

  ShowWindow(MainWnd, SW_SHOW);
  UpdateWindow(MainWnd);

  while GetMessage(Msg, 0, 0, 0) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
