unit uclockapp;

{$mode objfpc}{$H+}

{ One model, one canvas. Hosts call Tick on a timer, Resize when the
  window changes, and present Canvas when NeedsPresent is set.

  FullScreen is *reported* here so comments and About text can talk about
  it; the host is the one that actually asks Cocoa / Win32 / GTK to go
  full screen. }

interface

uses
  uclockmodel, uclockrender;

const
  ClockAboutTitle = 'RISC OS Clock';
  ClockAboutText =
    'A tribute to the analogue clock from RISC OS 3 (!Clock / !Alarm).' + LineEnding + LineEnding +
    'White face, twelve blue hour squares, grey hands, red second hand.' + LineEnding + LineEnding +
    'Resize the window, or press F11 (Esc to leave) for fullscreen. ' +
    'Double-click the face to toggle. Closing the window quits.';

type
  TClockController = class
  private
    FNeedsPresent: Boolean;
    FFullScreen: Boolean;
  public
    Model: TClockModel;
    Canvas: TPixelBuffer;
    constructor Create(PixelW, PixelH: Integer);
    destructor Destroy; override;
    procedure Resize(PixelW, PixelH: Integer);
    procedure Tick;
    procedure Render;
    procedure SetFrozenTime(H, M, S: Word);
    procedure SetFullScreen(Value: Boolean);
    property NeedsPresent: Boolean read FNeedsPresent;
    property FullScreen: Boolean read FFullScreen;
    procedure ConsumePresent;
  end;

implementation

constructor TClockController.Create(PixelW, PixelH: Integer);
begin
  inherited Create;
  Model := TClockModel.Create;
  Canvas := TPixelBuffer.Create(PixelW, PixelH);
  FNeedsPresent := True; { first frame before the timer so the window is not blank }
  FFullScreen := False;
end;

destructor TClockController.Destroy;
begin
  Canvas.Free;
  Model.Free;
  inherited Destroy;
end;

procedure TClockController.Resize(PixelW, PixelH: Integer);
begin
  if (PixelW = Canvas.Width) and (PixelH = Canvas.Height) then
    Exit;
  { State change: backing store follows the window (or the fullscreen
    display). The face is rebuilt from Radius = min(W,H)*0.46, so it
    stays circular on a widescreen. }
  Canvas.Resize(PixelW, PixelH);
  FNeedsPresent := True;
end;

procedure TClockController.Tick;
begin
  Model.SyncFromSystem;
  if Model.SecondTicked then
    { State change: integer second. The red hand jumps 6 degrees; hour
      and minute creep by a smaller amount. RISC OS redrew here too.
      The host notices NeedsPresent and uploads the canvas. }
    FNeedsPresent := True;
end;

procedure TClockController.Render;
var
  H: TClockHands;
begin
  H := Model.Hands;
  RenderClock(Canvas, H.HourAngle, H.MinuteAngle, H.SecondAngle);
  FNeedsPresent := True;
end;

procedure TClockController.SetFrozenTime(H, M, S: Word);
begin
  Model.Freeze(H, M, S);
  Render;
end;

procedure TClockController.SetFullScreen(Value: Boolean);
begin
  if FFullScreen = Value then
    Exit;
  { State change: windowed ↔ fullscreen. The host has already switched
    presentation; we only remember it. Resize() arrives separately with
    the new pixel size. }
  FFullScreen := Value;
  FNeedsPresent := True;
end;

procedure TClockController.ConsumePresent;
begin
  FNeedsPresent := False;
end;

end.
