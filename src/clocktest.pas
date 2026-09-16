program clocktest;

{$mode objfpc}{$H+}

{ Headless checks for hand angles. No window. }

uses
  SysUtils, Math, uclockmodel;

procedure ExpectNear(const LabelText: string; Got, Want, Eps: Double);
begin
  if Abs(Got - Want) > Eps then
  begin
    WriteLn('FAIL ', LabelText, ': got ', Got:0:6, ' want ', Want:0:6);
    Halt(1);
  end;
  WriteLn('ok   ', LabelText);
end;

procedure ExpectEq(const LabelText: string; Got, Want: Word);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', LabelText, ': got ', Got, ' want ', Want);
    Halt(1);
  end;
  WriteLn('ok   ', LabelText);
end;

var
  M: TClockModel;
  H: TClockHands;
begin
  ExpectNear('12:00 hour', HourAngleOf(12, 0, 0), 0, 1e-9);
  ExpectNear('12:00 minute', MinuteAngleOf(0, 0), 0, 1e-9);
  ExpectNear('12:00 second', SecondAngleOf(0), 0, 1e-9);
  ExpectNear('3:00 hour', HourAngleOf(3, 0, 0), Pi / 2, 1e-9);
  ExpectNear('6:00 hour', HourAngleOf(6, 0, 0), Pi, 1e-9);
  ExpectNear('9:00 hour', HourAngleOf(9, 0, 0), 3 * Pi / 2, 1e-9);
  ExpectNear('0:30 minute', MinuteAngleOf(30, 0), Pi, 1e-9);
  ExpectNear('0:15 second', SecondAngleOf(15), Pi / 2, 1e-9);
  { 6:30 — hour hand halfway from 6 toward 7 = 195 degrees. }
  ExpectNear('6:30 hour', HourAngleOf(6, 30, 0), Pi + Pi / 12, 1e-9);

  M := TClockModel.Create;
  try
    M.Freeze(10, 10, 0);
    ExpectEq('frozen hour', M.Hour, 10);
    ExpectEq('frozen minute', M.Minute, 10);
    ExpectEq('frozen second', M.Second, 0);
    H := M.Hands;
    ExpectNear('10:10 hour', H.HourAngle, HourAngleOf(10, 10, 0), 1e-12);
    M.SyncFromSystem; { frozen: must not pick up Now }
    ExpectEq('still frozen second', M.Second, 0);
    if M.SecondTicked then
    begin
      WriteLn('FAIL frozen SyncFromSystem should not tick');
      Halt(1);
    end;
    WriteLn('ok   frozen ignores Now');
  finally
    M.Free;
  end;
  WriteLn('All clock tests passed.');
end.
