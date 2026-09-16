unit uclockrender;

{$mode objfpc}{$H+}

{ Software RGBA canvas for the RISC OS analogue clock. Hosts only upload
  the bytes. Layout is derived from the buffer size so a 160-pixel window
  and a 4K fullscreen share the same proportions.

  The face is a tribute to RISC OS 3 !Clock / !Alarm analogue:
    white disc, thin black rim, twelve axis-aligned blue squares,
    grey kite hour/minute hands, thin red second hand, red centre boss.
  Those blue squares are *not* rotated ticks — they stay axis-aligned,
  which is the tell that this is Acorn's clock, not a generic xclock. }

interface

type
  TPixelBuffer = class
  private
    FWidth, FHeight: Integer;
    FData: array of Byte;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Resize(AWidth, AHeight: Integer);
    procedure Clear(R, G, B, A: Byte);
    function Ptr: PByte;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

  TClockLayout = record
    CX, CY, Radius: Double;
  end;

function MakeClockLayout(BufW, BufH: Integer): TClockLayout;
procedure RenderClock(Buf: TPixelBuffer; HourAngle, MinuteAngle, SecondAngle: Double);
procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);

implementation

uses
  Math;

type
  TColor = record
    R, G, B: Byte;
  end;

function C(R, G, B: Byte): TColor;
begin
  Result.R := R;
  Result.G := G;
  Result.B := B;
end;

constructor TPixelBuffer.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Resize(AWidth, AHeight);
end;

procedure TPixelBuffer.Resize(AWidth, AHeight: Integer);
begin
  if AWidth < 1 then
    AWidth := 1;
  if AHeight < 1 then
    AHeight := 1;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FData, FWidth * FHeight * 4);
end;

procedure TPixelBuffer.Clear(R, G, B, A: Byte);
var
  I: Integer;
  P: PByte;
begin
  P := @FData[0];
  I := 0;
  while I < Length(FData) do
  begin
    P[I] := R;
    P[I + 1] := G;
    P[I + 2] := B;
    P[I + 3] := A;
    Inc(I, 4);
  end;
end;

function TPixelBuffer.Ptr: PByte;
begin
  Result := @FData[0];
end;

procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);
var
  I, N: Integer;
  S, D: PByte;
begin
  S := Buf.Ptr;
  D := Dest;
  N := Buf.Width * Buf.Height;
  for I := 0 to N - 1 do
  begin
    D[0] := S[2]; { B — Windows DIB wants BGRA; the canvas is RGBA }
    D[1] := S[1];
    D[2] := S[0];
    D[3] := S[3];
    Inc(S, 4);
    Inc(D, 4);
  end;
end;

procedure BlendPixel(P: PByte; R, G, B: Byte; A: Double);
var
  SA, DA, OutA, Inv: Double;
begin
  if A <= 0.001 then
    Exit;
  if A > 1 then
    A := 1;
  SA := A;
  DA := P[3] / 255.0;
  Inv := 1.0 - SA;
  OutA := SA + DA * Inv;
  if OutA <= 0.001 then
    Exit;
  P[0] := Round((R * SA + P[0] * DA * Inv) / OutA);
  P[1] := Round((G * SA + P[1] * DA * Inv) / OutA);
  P[2] := Round((B * SA + P[2] * DA * Inv) / OutA);
  P[3] := Round(OutA * 255.0);
end;

function CoverEllipse(PX, PY, CX, CY, RX, RY: Double): Double;
var
  NX, NY, D, Edge: Double;
begin
  if (RX <= 0.2) or (RY <= 0.2) then
    Exit(0);
  NX := (PX - CX) / RX;
  NY := (PY - CY) / RY;
  D := Sqrt(NX * NX + NY * NY);
  Edge := (D - 1.0) * Min(RX, RY);
  if Edge <= -0.6 then
    Result := 1
  else if Edge >= 0.6 then
    Result := 0
  else
    Result := 1.0 - (Edge + 0.6) / 1.2;
end;

procedure FillEllipse(Buf: TPixelBuffer; CX, CY, RX, RY: Double; Col: TColor; Alpha: Double);
var
  X0, Y0, X1, Y1, X, Y, W: Integer;
  Cov: Double;
  P: PByte;
begin
  if (Alpha <= 0) or (RX <= 0) or (RY <= 0) then
    Exit;
  X0 := Max(0, Floor(CX - RX - 1));
  Y0 := Max(0, Floor(CY - RY - 1));
  X1 := Min(Buf.Width - 1, Ceil(CX + RX + 1));
  Y1 := Min(Buf.Height - 1, Ceil(CY + RY + 1));
  W := Buf.Width;
  for Y := Y0 to Y1 do
  begin
    P := Buf.Ptr + (Y * W + X0) * 4;
    for X := X0 to X1 do
    begin
      Cov := CoverEllipse(X + 0.5, Y + 0.5, CX, CY, RX, RY);
      if Cov > 0 then
        BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      Inc(P, 4);
    end;
  end;
end;

procedure StrokeEllipse(Buf: TPixelBuffer; CX, CY, RX, RY, Thickness: Double; Col: TColor; Alpha: Double);
var
  InnerX, InnerY: Double;
  X0, Y0, X1, Y1, X, Y, W: Integer;
  Cov: Double;
  P: PByte;
begin
  InnerX := RX - Thickness;
  InnerY := RY - Thickness;
  if InnerX < 0.4 then
    InnerX := 0.4;
  if InnerY < 0.4 then
    InnerY := 0.4;
  X0 := Max(0, Floor(CX - RX - 1));
  Y0 := Max(0, Floor(CY - RY - 1));
  X1 := Min(Buf.Width - 1, Ceil(CX + RX + 1));
  Y1 := Min(Buf.Height - 1, Ceil(CY + RY + 1));
  W := Buf.Width;
  for Y := Y0 to Y1 do
  begin
    P := Buf.Ptr + (Y * W + X0) * 4;
    for X := X0 to X1 do
    begin
      Cov := CoverEllipse(X + 0.5, Y + 0.5, CX, CY, RX, RY) *
             (1.0 - CoverEllipse(X + 0.5, Y + 0.5, CX, CY, InnerX, InnerY));
      if Cov > 0 then
        BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      Inc(P, 4);
    end;
  end;
end;

procedure FillRectAA(Buf: TPixelBuffer; X0, Y0, X1, Y1: Double; Col: TColor);
var
  IX0, IY0, IX1, IY1, X, Y, W: Integer;
  PX, PY, CovX, CovY, Cov: Double;
  P: PByte;
begin
  if (X1 <= X0) or (Y1 <= Y0) then
    Exit;
  IX0 := Max(0, Floor(X0 - 1));
  IY0 := Max(0, Floor(Y0 - 1));
  IX1 := Min(Buf.Width - 1, Ceil(X1 + 1));
  IY1 := Min(Buf.Height - 1, Ceil(Y1 + 1));
  W := Buf.Width;
  for Y := IY0 to IY1 do
  begin
    P := Buf.Ptr + (Y * W + IX0) * 4;
    PY := Y + 0.5;
    if PY < Y0 then
      CovY := 1.0 - (Y0 - PY)
    else if PY > Y1 then
      CovY := 1.0 - (PY - Y1)
    else
      CovY := 1.0;
    if CovY < 0 then
      CovY := 0;
    if CovY > 1 then
      CovY := 1;
    for X := IX0 to IX1 do
    begin
      PX := X + 0.5;
      if PX < X0 then
        CovX := 1.0 - (X0 - PX)
      else if PX > X1 then
        CovX := 1.0 - (PX - X1)
      else
        CovX := 1.0;
      if CovX < 0 then
        CovX := 0;
      if CovX > 1 then
        CovX := 1;
      Cov := CovX * CovY;
      if Cov > 0 then
        BlendPixel(P, Col.R, Col.G, Col.B, Cov);
      Inc(P, 4);
    end;
  end;
end;

function EdgeDist(PX, PY, AX, AY, BX, BY: Double): Double;
{ Signed distance from P to line AB, in pixels. Positive is inside if
  A,B,C are wound counter-clockwise. }
var
  DX, DY, Len: Double;
begin
  DX := BX - AX;
  DY := BY - AY;
  Len := Sqrt(DX * DX + DY * DY);
  if Len < 0.001 then
    Exit(0);
  Result := (DX * (PY - AY) - DY * (PX - AX)) / Len;
end;

procedure FillTriangle(Buf: TPixelBuffer; AX, AY, BX, BY, CX, CY: Double; Col: TColor; Alpha: Double);
var
  Area, E0, E1, E2, Cov: Double;
  X0, Y0, X1, Y1, X, Y, W: Integer;
  PX, PY: Double;
  P: PByte;
begin
  Area := (BX - AX) * (CY - AY) - (CX - AX) * (BY - AY);
  if Abs(Area) < 0.5 then
    Exit;
  if Area < 0 then
  begin
    { Force CCW so EdgeDist > 0 means inside. }
    FillTriangle(Buf, AX, AY, CX, CY, BX, BY, Col, Alpha);
    Exit;
  end;
  X0 := Max(0, Floor(Min(AX, Min(BX, CX)) - 1));
  Y0 := Max(0, Floor(Min(AY, Min(BY, CY)) - 1));
  X1 := Min(Buf.Width - 1, Ceil(Max(AX, Max(BX, CX)) + 1));
  Y1 := Min(Buf.Height - 1, Ceil(Max(AY, Max(BY, CY)) + 1));
  W := Buf.Width;
  for Y := Y0 to Y1 do
  begin
    P := Buf.Ptr + (Y * W + X0) * 4;
    PY := Y + 0.5;
    for X := X0 to X1 do
    begin
      PX := X + 0.5;
      E0 := EdgeDist(PX, PY, AX, AY, BX, BY);
      E1 := EdgeDist(PX, PY, BX, BY, CX, CY);
      E2 := EdgeDist(PX, PY, CX, CY, AX, AY);
      if (E0 >= -0.6) and (E1 >= -0.6) and (E2 >= -0.6) then
      begin
        Cov := Min(E0, Min(E1, E2));
        if Cov >= 0.6 then
          Cov := 1
        else
          Cov := (Cov + 0.6) / 1.2;
        if Cov > 0 then
          BlendPixel(P, Col.R, Col.G, Col.B, Cov * Alpha);
      end;
      Inc(P, 4);
    end;
  end;
end;

procedure DirOf(Angle: Double; out DX, DY: Double);
begin
  { Angle 0 = 12 o'clock. Canvas is y-down, so "up" is minus cosine. }
  DX := Sin(Angle);
  DY := -Cos(Angle);
end;

procedure DrawKite(Buf: TPixelBuffer; CX, CY, Angle, Length, Width, Tail: Double; Fill, Outline: TColor);
var
  DX, DY, PX, PY: Double;
  TipX, TipY, TailX, TailY, WideX, WideY, LeftX, LeftY, RightX, RightY: Double;
  OutW, OutLen, OutTail: Double;
begin
  DirOf(Angle, DX, DY);
  PX := -DY;
  PY := DX;
  OutW := Width + Max(1.1, Width * 0.22);
  OutLen := Length + Max(0.8, Length * 0.015);
  OutTail := Tail + Max(0.8, Tail * 0.10);

  { Outline kite first so the grey fill gets a dark rim, like the original
    plot of a filled path with a black edge. }
  TipX := CX + DX * OutLen;
  TipY := CY + DY * OutLen;
  TailX := CX - DX * OutTail;
  TailY := CY - DY * OutTail;
  WideX := CX + DX * (Length * 0.06);
  WideY := CY + DY * (Length * 0.06);
  LeftX := WideX + PX * OutW;
  LeftY := WideY + PY * OutW;
  RightX := WideX - PX * OutW;
  RightY := WideY - PY * OutW;
  FillTriangle(Buf, TipX, TipY, LeftX, LeftY, RightX, RightY, Outline, 1);
  FillTriangle(Buf, LeftX, LeftY, TailX, TailY, RightX, RightY, Outline, 1);

  TipX := CX + DX * Length;
  TipY := CY + DY * Length;
  TailX := CX - DX * Tail;
  TailY := CY - DY * Tail;
  LeftX := WideX + PX * Width;
  LeftY := WideY + PY * Width;
  RightX := WideX - PX * Width;
  RightY := WideY - PY * Width;
  FillTriangle(Buf, TipX, TipY, LeftX, LeftY, RightX, RightY, Fill, 1);
  FillTriangle(Buf, LeftX, LeftY, TailX, TailY, RightX, RightY, Fill, 1);
end;

procedure DrawSecondHand(Buf: TPixelBuffer; CX, CY, Angle, Length, Tail, Thick: Double; Col: TColor);
var
  DX, DY, PX, PY: Double;
  TipX, TipY, TailX, TailY, Half: Double;
begin
  DirOf(Angle, DX, DY);
  PX := -DY;
  PY := DX;
  Half := Thick * 0.5;
  TipX := CX + DX * Length;
  TipY := CY + DY * Length;
  TailX := CX - DX * Tail;
  TailY := CY - DY * Tail;
  FillTriangle(Buf,
    TipX + PX * Half, TipY + PY * Half,
    TipX - PX * Half, TipY - PY * Half,
    TailX + PX * Half, TailY + PY * Half, Col, 1);
  FillTriangle(Buf,
    TipX - PX * Half, TipY - PY * Half,
    TailX - PX * Half, TailY - PY * Half,
    TailX + PX * Half, TailY + PY * Half, Col, 1);
  FillEllipse(Buf, TipX, TipY, Half, Half, Col, 1);
  FillEllipse(Buf, TailX, TailY, Half, Half, Col, 1);
end;

function MakeClockLayout(BufW, BufH: Integer): TClockLayout;
begin
  Result.CX := BufW * 0.5;
  Result.CY := BufH * 0.5;
  { Leave a sliver of RISC OS grey around the disc so a non-square
    fullscreen still reads as "clock on the desktop", not a stretched oval. }
  Result.Radius := Min(BufW, BufH) * 0.46;
  if Result.Radius < 8 then
    Result.Radius := 8;
end;

procedure RenderClock(Buf: TPixelBuffer; HourAngle, MinuteAngle, SecondAngle: Double);
var
  Lay: TClockLayout;
  R, Mark, MarkR, Outline: Double;
  I: Integer;
  DX, DY, MX, MY: Double;
  Grey, White, Black, Blue, HandFill, HandEdge, Red: TColor;
begin
  { RISC OS WIMP greys / palette colours, sampled from RISC OS 3 screenshots. }
  Grey := C(192, 192, 192);
  White := C(255, 255, 255);
  Black := C(0, 0, 0);
  Blue := C(0, 0, 170);       { the twelve hour squares }
  HandFill := C(176, 176, 176);
  HandEdge := C(64, 64, 64);
  Red := C(221, 0, 0);

  Buf.Clear(Grey.R, Grey.G, Grey.B, 255);
  Lay := MakeClockLayout(Buf.Width, Buf.Height);
  R := Lay.Radius;
  Outline := Max(1.2, R * 0.008);
  Mark := Max(2.6, R * 0.048);
  MarkR := R - Outline - Mark * 0.55;

  FillEllipse(Buf, Lay.CX, Lay.CY, R, R, White, 1);
  StrokeEllipse(Buf, Lay.CX, Lay.CY, R, R, Outline, Black, 1);

  { Twelve axis-aligned squares — RISC OS did not rotate them with the hour. }
  for I := 0 to 11 do
  begin
    DirOf(I * (Pi / 6.0), DX, DY);
    MX := Lay.CX + DX * MarkR;
    MY := Lay.CY + DY * MarkR;
    FillRectAA(Buf, MX - Mark * 0.5, MY - Mark * 0.5,
      MX + Mark * 0.5, MY + Mark * 0.5, Blue);
  end;

  DrawKite(Buf, Lay.CX, Lay.CY, HourAngle,
    R * 0.52, R * 0.055, R * 0.11, HandFill, HandEdge);
  DrawKite(Buf, Lay.CX, Lay.CY, MinuteAngle,
    R * 0.78, R * 0.042, R * 0.11, HandFill, HandEdge);
  DrawSecondHand(Buf, Lay.CX, Lay.CY, SecondAngle,
    R * 0.88, R * 0.14, Max(1.15, R * 0.010), Red);

  { Red boss last, covering the hub the way !Clock plotted GCOL 1 CIRCLE FILL. }
  FillEllipse(Buf, Lay.CX, Lay.CY, Max(2.2, R * 0.045), Max(2.2, R * 0.045), Red, 1);
end;

end.
