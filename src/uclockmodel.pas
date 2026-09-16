unit uclockmodel;

{$mode objfpc}{$H+}

{ Time → hand angles. No pixels, no Cocoa/Win32/GTK.

  RISC OS Alarm / Clock plotted the analogue face from the system clock
  once a second. We do the same: SyncFromSystem() samples local time, and
  SecondTicked is how the controller knows the red hand should jump. }

interface

type
  TClockHands = record
    HourAngle: Double;   { radians, 0 = 12 o'clock, clockwise }
    MinuteAngle: Double;
    SecondAngle: Double;
    Hour, Minute, Second, Milli: Word;
  end;

  TClockModel = class
  private
    FHour, FMinute, FSecond, FMilli: Word;
    FFrozen: Boolean;
    FFirst: Boolean;
    FSecondTicked: Boolean;
    procedure Apply(H, M, S, MS: Word);
  public
    constructor Create;
    procedure SyncFromSystem;
    procedure Freeze(H, M, S: Word; MS: Word = 0);
    function Hands: TClockHands;
    property Hour: Word read FHour;
    property Minute: Word read FMinute;
    property Second: Word read FSecond;
    property SecondTicked: Boolean read FSecondTicked;
    property Frozen: Boolean read FFrozen;
  end;

{ 12 o'clock = 0, 3 o'clock = Pi/2. Shared with the headless tests. }
function HourAngleOf(H, M, S: Word): Double;
function MinuteAngleOf(M, S: Word): Double;
function SecondAngleOf(S: Word): Double;

implementation

uses
  SysUtils, Math;

constructor TClockModel.Create;
begin
  inherited Create;
  FFirst := True;
  FFrozen := False;
  FHour := 0;
  FMinute := 0;
  FSecond := 0;
  FMilli := 0;
  FSecondTicked := True;
end;

function HourAngleOf(H, M, S: Word): Double;
var
  Hours: Double;
begin
  { 30 degrees per hour, plus the minute/second creep so the hour hand
    is not stuck on the hour mark the way a cheap quartz toy is. }
  Hours := (H mod 12) + M / 60.0 + S / 3600.0;
  Result := Hours * (Pi / 6.0);
end;

function MinuteAngleOf(M, S: Word): Double;
begin
  Result := (M + S / 60.0) * (Pi / 30.0);
end;

function SecondAngleOf(S: Word): Double;
begin
  { Integer seconds only: the original red hand jumped, it did not sweep. }
  Result := S * (Pi / 30.0);
end;

procedure TClockModel.Apply(H, M, S, MS: Word);
begin
  { State change: a new integer second (or the first sample). The grey
    hands also move, but the red hand is the one you notice. }
  FSecondTicked := FFirst or (S <> FSecond);
  FFirst := False;
  FHour := H;
  FMinute := M;
  FSecond := S;
  FMilli := MS;
end;

procedure TClockModel.SyncFromSystem;
var
  H, M, S, MS: Word;
begin
  if FFrozen then
  begin
    { Snapshots and tests pin the hands; do not let Now() sneak in. }
    FSecondTicked := False;
    Exit;
  end;
  DecodeTime(Now, H, M, S, MS);
  Apply(H, M, S, MS);
end;

procedure TClockModel.Freeze(H, M, S: Word; MS: Word);
begin
  { State change: live clock → frozen pose (headless snap / tests). }
  FFrozen := True;
  FFirst := True;
  Apply(H, M, S, MS);
end;

function TClockModel.Hands: TClockHands;
begin
  Result.Hour := FHour;
  Result.Minute := FMinute;
  Result.Second := FSecond;
  Result.Milli := FMilli;
  Result.HourAngle := HourAngleOf(FHour, FMinute, FSecond);
  Result.MinuteAngle := MinuteAngleOf(FMinute, FSecond);
  Result.SecondAngle := SecondAngleOf(FSecond);
end;

end.
