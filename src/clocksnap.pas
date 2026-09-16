program clocksnap;

{$mode objfpc}{$H+}

{ Writes PPM frames of the software canvas (no window).
  Usage: clocksnap out-dir }

uses
  SysUtils, uclockapp;

procedure WritePPM(const Path: string; C: TClockController);
var
  F: File;
  X, Y: Integer;
  P: PByte;
  RGB: array[0..2] of Byte;
  Header: string;
begin
  C.Render;
  Header := Format('P6'#10'%d %d'#10'255'#10, [C.Canvas.Width, C.Canvas.Height]);
  AssignFile(F, Path);
  Rewrite(F, 1);
  BlockWrite(F, Header[1], Length(Header));
  for Y := 0 to C.Canvas.Height - 1 do
  begin
    P := C.Canvas.Ptr + Y * C.Canvas.Width * 4;
    for X := 0 to C.Canvas.Width - 1 do
    begin
      RGB[0] := P[0];
      RGB[1] := P[1];
      RGB[2] := P[2];
      BlockWrite(F, RGB[0], 3);
      Inc(P, 4);
    end;
  end;
  CloseFile(F);
end;

var
  Dir: string;
  C: TClockController;
begin
  if ParamCount >= 1 then
    Dir := ParamStr(1)
  else
    Dir := 'build';
  ForceDirectories(Dir);
  C := TClockController.Create(440, 440);
  try
    { 10:10:00 — the classic "catalogue" pose, both hands in the upper half. }
    C.SetFrozenTime(10, 10, 0);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-1010.ppm', C);
    { 6:32:00 — close to the RISC OS 3.11 guidebook screenshot. }
    C.SetFrozenTime(6, 32, 2);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-632.ppm', C);
    { Wide buffer: the face must stay circular, grey filling the sides. }
    C.Resize(800, 440);
    C.SetFrozenTime(3, 0, 15);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-wide.ppm', C);
  finally
    C.Free;
  end;
end.
