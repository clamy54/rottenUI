// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtRaster;

{$mode objfpc}{$H+}

{ A drawing surface of rottenUI's own (no LCL, no OS): what it draws is the
  same, to the byte, on every system. Pixels are opaque, $FFRRGGBB in a
  LongWord (bytes B G R A in memory); colours are given straight
  $AARRGGBB. Shapes are filled with an exact area coverage computed in
  integers: coordinates in 1/256 pixel, 16 rows sampled per pixel, the
  horizontal coverage exact; nonzero and even-odd rules exact where
  contours overlap. Strokes are the union of their pieces (segments,
  joins, caps) filled at once; a text is its glyphs' outlines filled at
  once (uRtFont). Colours are blended as stored (sRGB values), in
  integers. }

interface

uses
  SysUtils, uRtFont;

type
  TRtColor = LongWord;     // $AARRGGBB, straight alpha
  TRtCodePointArray = array of Cardinal;
  TRtFillRule = (rfNonZero, rfEvenOdd);
  TRtLineCap = (lcButt, lcRound, lcSquare);
  TRtLineJoin = (ljMiter, ljRound, ljBevel);

  { Polygons in pixels (y down): Xs / Ys of every contour after one another,
    Starts the first point of each. }
  TRtPath = record
    Xs, Ys: array of Double;
    Starts: array of Integer;
    Count, Contours: Integer;
  end;

  TRtRaster = class
  private
    FWidth, FHeight: Integer;
    FClipX0, FClipY0, FClipX1, FClipY1: Integer;
    FCov: array of Integer;      // a row's coverage, scratch
    procedure FillCoverage(const APath: TRtPath; AColor: TRtColor; ARule: TRtFillRule);
    procedure BlendSpan(AY, AX0: Integer; ACount: Integer; AColor: TRtColor);
  public
    Pixels: array of LongWord;
    constructor Create(AWidth, AHeight: Integer);
    procedure SetSize(AWidth, AHeight: Integer);
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    { Drawing kept inside (X0, Y0)-(X1, Y1), pixels, the end excluded. }
    procedure SetClip(AX0, AY0, AX1, AY1: Integer);
    procedure ResetClip;
    procedure Clear(AColor: TRtColor);
    procedure FillPath(const APath: TRtPath; AColor: TRtColor; ARule: TRtFillRule = rfNonZero);
    { Each contour of APath a polyline (closed when AClosed). ADash: lengths
      on, off, on... (none: plain), from ADashOffset along each contour. }
    procedure StrokePath(const APath: TRtPath; AClosed: Boolean; AWidth: Double; AColor: TRtColor;
      ACap: TRtLineCap = lcButt; AJoin: TRtLineJoin = ljMiter; AMiterLimit: Double = 4;
      const ADash: array of Double; ADashOffset: Double = 0);
    procedure FillRect(AX0, AY0, AX1, AY1: Double; AColor: TRtColor);
    procedure FillEllipse(ACX, ACY, ARX, ARY: Double; AColor: TRtColor);
    procedure StrokeEllipse(ACX, ACY, ARX, ARY, AWidth: Double; AColor: TRtColor);
    procedure FillRoundRect(AX0, AY0, AX1, AY1, ARadius: Double; AColor: TRtColor);
    procedure StrokeRoundRect(AX0, AY0, AX1, AY1, ARadius, AWidth: Double; AColor: TRtColor);
    procedure StrokeRect(AX0, AY0, AX1, AY1, AWidth: Double; AColor: TRtColor);
    procedure Line(AX0, AY0, AX1, AY1, AWidth: Double; AColor: TRtColor; ACap: TRtLineCap = lcButt);
    { AText (UTF-8) with its baseline's start at (AX, AY), its em ASize
      pixels, turned AAngle radians clockwise. }
    procedure DrawText(AFont: TRtFont; const AText: string; AX, AY, ASize, AAngle: Double; AColor: TRtColor);
    { ASrc's zone (SX, SY, SW, SH) drawn into (DX, DY, DW, DH), filtered
      bilinearly (its alpha honoured; a source pixel is $AARRGGBB). }
    procedure DrawRaster(const ASrc: array of LongWord; ASrcW, ASrcH: Integer; ASX, ASY, ASW, ASH,
      ADX, ADY, ADW, ADH: Double);
  end;

{ A text's advance (pixels) at an em of ASize. }
function RtTextWidth(AFont: TRtFont; const AText: string; ASize: Double): Double;
{ The code points of UTF-8 AText (a broken sequence as U+FFFD). }
function RtCodePoints(const AText: string): TRtCodePointArray;

procedure RtPathClear(var APath: TRtPath);
procedure RtPathMove(var APath: TRtPath; AX, AY: Double);
procedure RtPathLine(var APath: TRtPath; AX, AY: Double);
{ An ellipse as a polygon (clockwise on screen). }
procedure RtPathEllipse(var APath: TRtPath; ACX, ACY, ARX, ARY: Double);
procedure RtPathRoundRect(var APath: TRtPath; AX0, AY0, AX1, AY1, ARadius: Double);
procedure RtPathRect(var APath: TRtPath; AX0, AY0, AX1, AY1: Double);

function RtRgb(AR, AG, AB: Byte; AA: Byte = 255): TRtColor;

implementation

uses
  Math;

const
  SUB = 16;                // rows sampled per pixel
  FIX = 256;               // coordinates' fraction
  FULL = SUB * FIX;        // a pixel's whole coverage
  CIRCLE_STEPS = 128;      // the unit circle's table

var
  CosTab, SinTab: array[0..CIRCLE_STEPS] of Double;

function RtRgb(AR, AG, AB: Byte; AA: Byte): TRtColor;
begin
  Result := LongWord(AA) shl 24 or LongWord(AR) shl 16 or LongWord(AG) shl 8 or AB;
end;

{ ---- paths ---- }

procedure RtPathClear(var APath: TRtPath);
begin
  APath.Count := 0;
  APath.Contours := 0;
end;

procedure RtPathMove(var APath: TRtPath; AX, AY: Double);
begin
  if APath.Contours >= Length(APath.Starts) then SetLength(APath.Starts, Max(8, 2 * Length(APath.Starts)));
  APath.Starts[APath.Contours] := APath.Count;
  Inc(APath.Contours);
  RtPathLine(APath, AX, AY);
end;

procedure RtPathLine(var APath: TRtPath; AX, AY: Double);
begin
  if APath.Contours = 0 then
  begin
    RtPathMove(APath, AX, AY);
    Exit;
  end;
  if APath.Count >= Length(APath.Xs) then
  begin
    SetLength(APath.Xs, Max(32, 2 * Length(APath.Xs)));
    SetLength(APath.Ys, Length(APath.Xs));
  end;
  APath.Xs[APath.Count] := AX;
  APath.Ys[APath.Count] := AY;
  Inc(APath.Count);
end;

function EllipseSteps(ARX, ARY: Double): Integer;
begin
  // one step about every 2 pixels of its circumference, 8 at least
  Result := EnsureRange(Ceil(Max(Abs(ARX), Abs(ARY)) * Pi / 2), 8, CIRCLE_STEPS);
  // a divisor of the table's steps, so that every point comes from the table
  if Result <= 8 then Result := 8
  else if Result <= 16 then Result := 16
  else if Result <= 32 then Result := 32
  else if Result <= 64 then Result := 64
  else Result := 128;
end;

procedure RtPathEllipse(var APath: TRtPath; ACX, ACY, ARX, ARY: Double);
var
  n, i, k: Integer;
begin
  n := EllipseSteps(ARX, ARY);
  k := CIRCLE_STEPS div n;
  for i := 0 to n - 1 do
    if i = 0 then RtPathMove(APath, ACX + ARX * CosTab[0], ACY + ARY * SinTab[0])
    else RtPathLine(APath, ACX + ARX * CosTab[i * k], ACY + ARY * SinTab[i * k]);
end;

procedure RtPathRect(var APath: TRtPath; AX0, AY0, AX1, AY1: Double);
begin
  RtPathMove(APath, AX0, AY0);
  RtPathLine(APath, AX1, AY0);
  RtPathLine(APath, AX1, AY1);
  RtPathLine(APath, AX0, AY1);
end;

procedure RtPathRoundRect(var APath: TRtPath; AX0, AY0, AX1, AY1, ARadius: Double);
var
  r: Double;
  n, i, k, q: Integer;
  cx, cy: Double;
begin
  r := Min(ARadius, Min(Abs(AX1 - AX0), Abs(AY1 - AY0)) / 2);
  if r <= 0.01 then
  begin
    RtPathRect(APath, AX0, AY0, AX1, AY1);
    Exit;
  end;
  n := EllipseSteps(r, r);
  k := CIRCLE_STEPS div n;
  // four quarters, clockwise on screen from the right-bottom corner
  for q := 0 to 3 do
  begin
    case q of
      0: begin cx := AX1 - r; cy := AY1 - r; end;
      1: begin cx := AX0 + r; cy := AY1 - r; end;
      2: begin cx := AX0 + r; cy := AY0 + r; end;
    else
      begin cx := AX1 - r; cy := AY0 + r; end;
    end;
    for i := 0 to n div 4 do
      if (q = 0) and (i = 0) then RtPathMove(APath, cx + r * CosTab[(q * n div 4 + i) * k], cy + r * SinTab[(q * n div 4 + i) * k])
      else RtPathLine(APath, cx + r * CosTab[((q * n div 4 + i) * k) mod CIRCLE_STEPS],
        cy + r * SinTab[((q * n div 4 + i) * k) mod CIRCLE_STEPS]);
  end;
end;

{ ---- text ---- }

function RtCodePoints(const AText: string): TRtCodePointArray;
var
  i, n, len, need: Integer;
  c: Cardinal;
  b: Byte;
begin
  Result := nil;
  SetLength(Result, Length(AText));
  n := 0;
  i := 1;
  len := Length(AText);
  while i <= len do
  begin
    b := Ord(AText[i]);
    if b < $80 then
    begin
      c := b;
      need := 0;
    end
    else if b and $E0 = $C0 then
    begin
      c := b and $1F;
      need := 1;
    end
    else if b and $F0 = $E0 then
    begin
      c := b and $0F;
      need := 2;
    end
    else if b and $F8 = $F0 then
    begin
      c := b and $07;
      need := 3;
    end
    else
    begin
      c := $FFFD;
      need := 0;
    end;
    Inc(i);
    while (need > 0) and (i <= len) and (Ord(AText[i]) and $C0 = $80) do
    begin
      c := c shl 6 or (Ord(AText[i]) and $3F);
      Inc(i);
      Dec(need);
    end;
    if need > 0 then c := $FFFD;
    Result[n] := c;
    Inc(n);
  end;
  SetLength(Result, n);
end;

function RtTextWidth(AFont: TRtFont; const AText: string; ASize: Double): Double;
var
  cps: TRtCodePointArray;
  i: Integer;
  units: Int64;
begin
  Result := 0;
  if (AFont = nil) or (AText = '') then Exit;
  cps := RtCodePoints(AText);
  units := 0;
  for i := 0 to High(cps) do Inc(units, AFont.Advance(AFont.GlyphIndex(cps[i])));
  Result := units * ASize / AFont.UnitsPerEm;
end;

{ ---- the raster ---- }

constructor TRtRaster.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  SetSize(AWidth, AHeight);
end;

procedure TRtRaster.SetSize(AWidth, AHeight: Integer);
begin
  FWidth := Max(0, AWidth);
  FHeight := Max(0, AHeight);
  SetLength(Pixels, FWidth * FHeight);
  ResetClip;
end;

procedure TRtRaster.SetClip(AX0, AY0, AX1, AY1: Integer);
begin
  FClipX0 := EnsureRange(AX0, 0, FWidth);
  FClipY0 := EnsureRange(AY0, 0, FHeight);
  FClipX1 := EnsureRange(AX1, FClipX0, FWidth);
  FClipY1 := EnsureRange(AY1, FClipY0, FHeight);
end;

procedure TRtRaster.ResetClip;
begin
  SetClip(0, 0, FWidth, FHeight);
end;

procedure TRtRaster.Clear(AColor: TRtColor);
var
  i: Integer;
  c: LongWord;
begin
  c := AColor or $FF000000;
  for i := 0 to High(Pixels) do Pixels[i] := c;
end;

{ Blend one pixel: its coverage ACov in 0..255 times the colour's alpha. }
procedure BlendPixel(var APixel: LongWord; AColor: TRtColor; ACov: Integer); inline;
var
  a, ia: LongWord;
  d: LongWord;
begin
  a := (LongWord(ACov) * (AColor shr 24) + 127) div 255;
  if a = 0 then Exit;
  if a >= 255 then
  begin
    APixel := AColor or $FF000000;
    Exit;
  end;
  ia := 255 - a;
  d := APixel;
  APixel := $FF000000 or
    (((((AColor shr 16) and $FF) * a + ((d shr 16) and $FF) * ia + 127) div 255) shl 16) or
    (((((AColor shr 8) and $FF) * a + ((d shr 8) and $FF) * ia + 127) div 255) shl 8) or
    ((((AColor and $FF) * a + (d and $FF) * ia + 127) div 255));
end;

procedure TRtRaster.BlendSpan(AY, AX0: Integer; ACount: Integer; AColor: TRtColor);
var
  i, base: Integer;
begin
  base := AY * FWidth;
  for i := 0 to ACount - 1 do
    BlendPixel(Pixels[base + AX0 + i], AColor, 255);
end;

type
  TEdge = record
    X0, Y0, X1, Y1: Int64;   // 1/256 pixel, Y0 < Y1
    Dir: Integer;            // +1 downwards, -1 upwards
  end;

function FixOf(AValue: Double): Int64; inline;
begin
  if IsNan(AValue) then Exit(0);
  AValue := EnsureRange(AValue, -1e7, 1e7);
  Result := Floor(AValue * FIX + 0.5);
end;

procedure TRtRaster.FillCoverage(const APath: TRtPath; AColor: TRtColor; ARule: TRtFillRule);
var
  edges: array of TEdge;
  ne, c, i, j, first, last, n: Integer;
  ax, ay, bx, by: Int64;
  minY, maxY, minX, maxX: Int64;
  py0, py1, px0, px1, y, k, w: Integer;
  ys: Int64;
  xs: array of Int64;
  ds: array of Integer;
  nx, wind: Integer;
  tx: Int64;
  td: Integer;
  xa, xb: Int64;
  pa, pb, x, cov: Integer;
  inside, was: Boolean;
begin
  if (APath.Count < 3) or (FClipX1 <= FClipX0) or (FClipY1 <= FClipY0) then Exit;
  // the edges, in fixed point; horizontal ones are none
  SetLength(edges, APath.Count);
  ne := 0;
  minY := High(Int64);
  maxY := Low(Int64);
  minX := High(Int64);
  maxX := Low(Int64);
  for c := 0 to APath.Contours - 1 do
  begin
    first := APath.Starts[c];
    if c < APath.Contours - 1 then last := APath.Starts[c + 1] - 1 else last := APath.Count - 1;
    n := last - first + 1;
    if n < 2 then Continue;
    for i := 0 to n - 1 do
    begin
      j := first + (i + 1) mod n;
      ax := FixOf(APath.Xs[first + i]);
      ay := FixOf(APath.Ys[first + i]);
      bx := FixOf(APath.Xs[j]);
      by := FixOf(APath.Ys[j]);
      minX := Min(minX, Min(ax, bx));
      maxX := Max(maxX, Max(ax, bx));
      if ay = by then Continue;
      if ne >= Length(edges) then SetLength(edges, 2 * Length(edges));
      if ay < by then
      begin
        edges[ne].X0 := ax; edges[ne].Y0 := ay; edges[ne].X1 := bx; edges[ne].Y1 := by; edges[ne].Dir := 1;
      end
      else
      begin
        edges[ne].X0 := bx; edges[ne].Y0 := by; edges[ne].X1 := ax; edges[ne].Y1 := ay; edges[ne].Dir := -1;
      end;
      minY := Min(minY, edges[ne].Y0);
      maxY := Max(maxY, edges[ne].Y1);
      Inc(ne);
    end;
  end;
  if ne = 0 then Exit;
  // the rows and columns touched, in the clip
  py0 := Max(FClipY0, Integer(Max(Int64(-1), minY div FIX)));
  py1 := Min(FClipY1, Integer(Min(Int64(FHeight + 1), maxY div FIX + 1)));
  px0 := Max(FClipX0, Integer(Max(Int64(-1), minX div FIX)));
  px1 := Min(FClipX1, Integer(Min(Int64(FWidth + 1), maxX div FIX + 1)));
  if (py1 <= py0) or (px1 <= px0) then Exit;
  w := px1 - px0;
  if Length(FCov) < w + 2 then SetLength(FCov, w + 2);
  SetLength(xs, ne);
  SetLength(ds, ne);
  for y := py0 to py1 - 1 do
  begin
    for i := 0 to w + 1 do FCov[i] := 0;
    for k := 0 to SUB - 1 do
    begin
      // the sampled row's centre
      ys := Int64(y) * FIX + (k * FIX + FIX div 2) div SUB;
      nx := 0;
      for i := 0 to ne - 1 do
        if (edges[i].Y0 <= ys) and (ys < edges[i].Y1) then
        begin
          tx := edges[i].X0 + (ys - edges[i].Y0) * (edges[i].X1 - edges[i].X0) div (edges[i].Y1 - edges[i].Y0);
          // sorted as it goes (few crossings per row)
          j := nx;
          while (j > 0) and ((xs[j - 1] > tx) or ((xs[j - 1] = tx) and (ds[j - 1] > edges[i].Dir))) do
          begin
            xs[j] := xs[j - 1];
            ds[j] := ds[j - 1];
            Dec(j);
          end;
          xs[j] := tx;
          ds[j] := edges[i].Dir;
          Inc(nx);
        end;
      if nx < 2 then Continue;
      wind := 0;
      was := False;
      xa := 0;
      for i := 0 to nx - 1 do
      begin
        Inc(wind, ds[i]);
        if ARule = rfNonZero then inside := wind <> 0 else inside := Odd(wind);
        if inside and not was then xa := xs[i]
        else if was and not inside then
        begin
          // the span xa..xs[i] of this sampled row, cut to the columns
          xb := xs[i];
          xa := Max(xa, Int64(px0) * FIX);
          xb := Min(xb, Int64(px1) * FIX);
          if xb > xa then
          begin
            pa := Integer(xa div FIX) - px0;
            pb := Integer(xb div FIX) - px0;
            if pa = pb then
              Inc(FCov[pa], Integer(xb - xa))
            else
            begin
              Inc(FCov[pa], FIX - Integer(xa mod FIX));
              for x := pa + 1 to pb - 1 do Inc(FCov[x], FIX);
              if pb <= w then Inc(FCov[pb], Integer(xb mod FIX));
            end;
          end;
        end;
        was := inside;
      end;
    end;
    // the row blended: coverage out of FULL brought to 0..255
    for x := 0 to w - 1 do
    begin
      cov := FCov[x];
      if cov <= 0 then Continue;
      if cov >= FULL then cov := 255 else cov := (cov * 255 + FULL div 2) div FULL;
      BlendPixel(Pixels[y * FWidth + px0 + x], AColor, cov);
    end;
  end;
end;

procedure TRtRaster.FillPath(const APath: TRtPath; AColor: TRtColor; ARule: TRtFillRule);
begin
  if AColor shr 24 = 0 then Exit;
  FillCoverage(APath, AColor, ARule);
end;

{ The stroke's pieces appended to AOut, each a contour clockwise on screen
  (y down), so that their union is filled by the nonzero rule. }
procedure AddPiece(var AOut: TRtPath; const AX, AY: array of Double; ACount: Integer);
var
  area: Double;
  i, j: Integer;
begin
  if ACount < 3 then Exit;
  area := 0;
  for i := 0 to ACount - 1 do
  begin
    j := (i + 1) mod ACount;
    area := area + AX[i] * AY[j] - AX[j] * AY[i];
  end;
  if Abs(area) < 1e-12 then Exit;
  if area > 0 then
  begin
    RtPathMove(AOut, AX[0], AY[0]);
    for i := 1 to ACount - 1 do RtPathLine(AOut, AX[i], AY[i]);
  end
  else
  begin
    RtPathMove(AOut, AX[ACount - 1], AY[ACount - 1]);
    for i := ACount - 2 downto 0 do RtPathLine(AOut, AX[i], AY[i]);
  end;
end;

procedure AddDisc(var AOut: TRtPath; ACX, ACY, AR: Double);
var
  xs, ys: array of Double;
  n, i, k: Integer;
begin
  n := EllipseSteps(AR, AR);
  k := CIRCLE_STEPS div n;
  SetLength(xs, n);
  SetLength(ys, n);
  for i := 0 to n - 1 do
  begin
    xs[i] := ACX + AR * CosTab[i * k];
    ys[i] := ACY + AR * SinTab[i * k];
  end;
  AddPiece(AOut, xs, ys, n);
end;

procedure StrokePolyline(var AOut: TRtPath; const AX, AY: array of Double; AFrom, ACount: Integer;
  AClosed: Boolean; AHalf: Double; ACap: TRtLineCap; AJoin: TRtLineJoin; AMiter: Double);
var
  px, py: array[0..3] of Double;
  i, n, segs, a, b, c: Integer;
  dx, dy, len, nx, ny, ex, ey: Double;
  ux0, uy0, ux1, uy1, cross, dot, mx, my, ml: Double;
  pts: array of Integer;
begin
  // the distinct points (a point repeated is one)
  SetLength(pts, ACount);
  n := 0;
  for i := 0 to ACount - 1 do
    if (n = 0) or (Abs(AX[AFrom + i] - AX[AFrom + pts[n - 1]]) > 1e-9) or
      (Abs(AY[AFrom + i] - AY[AFrom + pts[n - 1]]) > 1e-9) then
    begin
      pts[n] := i;
      Inc(n);
    end;
  if AClosed and (n > 2) and (Abs(AX[AFrom + pts[0]] - AX[AFrom + pts[n - 1]]) < 1e-9) and
    (Abs(AY[AFrom + pts[0]] - AY[AFrom + pts[n - 1]]) < 1e-9) then Dec(n);
  if n = 1 then
  begin
    // a dot: drawn by its caps only
    if ACap = lcRound then AddDisc(AOut, AX[AFrom + pts[0]], AY[AFrom + pts[0]], AHalf)
    else if ACap = lcSquare then
    begin
      px[0] := AX[AFrom + pts[0]] - AHalf; py[0] := AY[AFrom + pts[0]] - AHalf;
      px[1] := AX[AFrom + pts[0]] + AHalf; py[1] := py[0];
      px[2] := px[1]; py[2] := AY[AFrom + pts[0]] + AHalf;
      px[3] := px[0]; py[3] := py[2];
      AddPiece(AOut, px, py, 4);
    end;
    Exit;
  end;
  if n < 2 then Exit;
  if AClosed and (n > 2) then segs := n else segs := n - 1;
  for i := 0 to segs - 1 do
  begin
    a := AFrom + pts[i];
    b := AFrom + pts[(i + 1) mod n];
    dx := AX[b] - AX[a];
    dy := AY[b] - AY[a];
    len := Sqrt(dx * dx + dy * dy);
    if len < 1e-12 then Continue;
    nx := -dy / len * AHalf;
    ny := dx / len * AHalf;
    ex := 0;
    ey := 0;
    // a square cap lengthens the open ends by half the width
    if (ACap = lcSquare) and not (AClosed and (n > 2)) then
    begin
      ex := dx / len * AHalf;
      ey := dy / len * AHalf;
    end;
    px[0] := AX[a] + nx; py[0] := AY[a] + ny;
    px[1] := AX[b] + nx; py[1] := AY[b] + ny;
    px[2] := AX[b] - nx; py[2] := AY[b] - ny;
    px[3] := AX[a] - nx; py[3] := AY[a] - ny;
    if ex <> 0 then
    begin
      if (i = 0) then
      begin
        px[0] := px[0] - ex; py[0] := py[0] - ey;
        px[3] := px[3] - ex; py[3] := py[3] - ey;
      end;
      if (i = segs - 1) then
      begin
        px[1] := px[1] + ex; py[1] := py[1] + ey;
        px[2] := px[2] + ex; py[2] := py[2] + ey;
      end;
    end;
    AddPiece(AOut, px, py, 4);
  end;
  // the joins, at every inner point (every point of a closed line)
  for i := 0 to n - 1 do
  begin
    if not (AClosed and (n > 2)) and ((i = 0) or (i = n - 1)) then Continue;
    a := AFrom + pts[(i + n - 1) mod n];
    b := AFrom + pts[i];
    c := AFrom + pts[(i + 1) mod n];
    dx := AX[b] - AX[a]; dy := AY[b] - AY[a];
    len := Sqrt(dx * dx + dy * dy);
    if len < 1e-12 then Continue;
    ux0 := dx / len; uy0 := dy / len;
    dx := AX[c] - AX[b]; dy := AY[c] - AY[b];
    len := Sqrt(dx * dx + dy * dy);
    if len < 1e-12 then Continue;
    ux1 := dx / len; uy1 := dy / len;
    cross := ux0 * uy1 - uy0 * ux1;
    dot := ux0 * ux1 + uy0 * uy1;
    if Abs(cross) < 1e-9 then Continue;      // straight on
    if AJoin = ljRound then
    begin
      AddDisc(AOut, AX[b], AY[b], AHalf);
      Continue;
    end;
    // the outer side: where the line turns away from
    if cross > 0 then
    begin
      // turning clockwise on screen: the outer side is the left normal
      px[0] := AX[b]; py[0] := AY[b];
      px[1] := AX[b] + uy0 * AHalf; py[1] := AY[b] - ux0 * AHalf;
      px[3] := AX[b] + uy1 * AHalf; py[3] := AY[b] - ux1 * AHalf;
    end
    else
    begin
      px[0] := AX[b]; py[0] := AY[b];
      px[1] := AX[b] - uy0 * AHalf; py[1] := AY[b] + ux0 * AHalf;
      px[3] := AX[b] - uy1 * AHalf; py[3] := AY[b] + ux1 * AHalf;
    end;
    // the miter's tip, within its limit (else a bevel)
    ml := 1 / Sqrt(Max(1e-12, (1 + dot) / 2));
    if (AJoin = ljMiter) and (ml <= AMiter) then
    begin
      mx := (px[1] + px[3]) / 2 - AX[b];
      my := (py[1] + py[3]) / 2 - AY[b];
      len := Sqrt(mx * mx + my * my);
      if len > 1e-12 then
      begin
        px[2] := AX[b] + mx / len * AHalf * ml;
        py[2] := AY[b] + my / len * AHalf * ml;
        AddPiece(AOut, px, py, 4);
        Continue;
      end;
    end;
    px[2] := px[3]; py[2] := py[3];
    AddPiece(AOut, px, py, 3);
  end;
  // round caps at the open ends
  if (ACap = lcRound) and not (AClosed and (n > 2)) then
  begin
    AddDisc(AOut, AX[AFrom + pts[0]], AY[AFrom + pts[0]], AHalf);
    AddDisc(AOut, AX[AFrom + pts[n - 1]], AY[AFrom + pts[n - 1]], AHalf);
  end;
end;

procedure TRtRaster.StrokePath(const APath: TRtPath; AClosed: Boolean; AWidth: Double; AColor: TRtColor;
  ACap: TRtLineCap; AJoin: TRtLineJoin; AMiterLimit: Double; const ADash: array of Double; ADashOffset: Double);
var
  outline: TRtPath;
  c, first, last, n, i, di, guard: Integer;
  total, pos, remain, seg, t, ax, ay, bx, by: Double;
  on_: Boolean;
  dx, dy: array of Double;
  dn: Integer;

  procedure FlushDash;
  begin
    if dn >= 2 then StrokePolyline(outline, dx, dy, 0, dn, False, AWidth / 2, ACap, AJoin, AMiterLimit)
    else if (dn = 1) and (ACap <> lcButt) then StrokePolyline(outline, dx, dy, 0, 1, False, AWidth / 2, ACap, AJoin, AMiterLimit);
    dn := 0;
  end;

  procedure AddDash(AX, AY: Double);
  begin
    if dn >= Length(dx) then
    begin
      SetLength(dx, Max(16, 2 * Length(dx)));
      SetLength(dy, Length(dx));
    end;
    dx[dn] := AX;
    dy[dn] := AY;
    Inc(dn);
  end;

begin
  if (AColor shr 24 = 0) or not (AWidth > 0) or (APath.Count < 1) then Exit;
  outline := Default(TRtPath);
  total := 0;
  for i := 0 to High(ADash) do total := total + Max(0, ADash[i]);
  for c := 0 to APath.Contours - 1 do
  begin
    first := APath.Starts[c];
    if c < APath.Contours - 1 then last := APath.Starts[c + 1] - 1 else last := APath.Count - 1;
    n := last - first + 1;
    if n < 1 then Continue;
    if (Length(ADash) = 0) or not (total > 0) then
    begin
      StrokePolyline(outline, APath.Xs, APath.Ys, first, n, AClosed, AWidth / 2, ACap, AJoin, AMiterLimit);
      Continue;
    end;
    // dashed: the pieces on, each stroked as an open line
    pos := ADashOffset - Floor(ADashOffset / total) * total;
    di := 0;
    while pos >= Max(0, ADash[di]) do
    begin
      pos := pos - Max(0, ADash[di]);
      di := (di + 1) mod Length(ADash);
    end;
    remain := Max(0, ADash[di]) - pos;
    on_ := not Odd(di);
    dn := 0;
    if on_ then AddDash(APath.Xs[first], APath.Ys[first]);
    guard := 0;
    for i := 0 to n - 1 + Ord(AClosed) - 1 do
    begin
      ax := APath.Xs[first + i];
      ay := APath.Ys[first + i];
      bx := APath.Xs[first + (i + 1) mod n];
      by := APath.Ys[first + (i + 1) mod n];
      seg := Sqrt(Sqr(bx - ax) + Sqr(by - ay));
      t := 0;
      while (seg - t > remain) and (guard < 1000000) do
      begin
        Inc(guard);
        t := t + remain;
        if on_ then
        begin
          AddDash(ax + (bx - ax) * t / seg, ay + (by - ay) * t / seg);
          FlushDash;
        end;
        di := (di + 1) mod Length(ADash);
        remain := Max(0, ADash[di]);
        on_ := not on_;
        if on_ then AddDash(ax + (bx - ax) * t / seg, ay + (by - ay) * t / seg);
      end;
      remain := remain - (seg - t);
      if on_ then AddDash(bx, by);
    end;
    FlushDash;
  end;
  FillCoverage(outline, AColor, rfNonZero);
end;

procedure TRtRaster.FillRect(AX0, AY0, AX1, AY1: Double; AColor: TRtColor);
var
  p: TRtPath;
begin
  p := Default(TRtPath);
  RtPathRect(p, AX0, AY0, AX1, AY1);
  FillPath(p, AColor);
end;

procedure TRtRaster.StrokeRect(AX0, AY0, AX1, AY1, AWidth: Double; AColor: TRtColor);
var
  p: TRtPath;
begin
  p := Default(TRtPath);
  RtPathRect(p, AX0, AY0, AX1, AY1);
  StrokePath(p, True, AWidth, AColor, lcButt, ljMiter, 4, []);
end;

procedure TRtRaster.FillEllipse(ACX, ACY, ARX, ARY: Double; AColor: TRtColor);
var
  p: TRtPath;
begin
  p := Default(TRtPath);
  RtPathEllipse(p, ACX, ACY, ARX, ARY);
  FillPath(p, AColor);
end;

procedure TRtRaster.StrokeEllipse(ACX, ACY, ARX, ARY, AWidth: Double; AColor: TRtColor);
var
  p: TRtPath;
begin
  p := Default(TRtPath);
  // the ring between the two ellipses: outer clockwise, inner the other way
  RtPathEllipse(p, ACX, ACY, ARX + AWidth / 2, ARY + AWidth / 2);
  if (ARX > AWidth / 2) and (ARY > AWidth / 2) then
    RtPathEllipse(p, ACX, ACY, ARX - AWidth / 2, ARY - AWidth / 2);
  FillPath(p, AColor, rfEvenOdd);
end;

procedure TRtRaster.FillRoundRect(AX0, AY0, AX1, AY1, ARadius: Double; AColor: TRtColor);
var
  p: TRtPath;
begin
  p := Default(TRtPath);
  RtPathRoundRect(p, AX0, AY0, AX1, AY1, ARadius);
  FillPath(p, AColor);
end;

procedure TRtRaster.StrokeRoundRect(AX0, AY0, AX1, AY1, ARadius, AWidth: Double; AColor: TRtColor);
var
  p: TRtPath;
  h: Double;
begin
  p := Default(TRtPath);
  h := AWidth / 2;
  RtPathRoundRect(p, AX0 - h, AY0 - h, AX1 + h, AY1 + h, ARadius + h);
  if (AX1 - AX0 > AWidth) and (AY1 - AY0 > AWidth) then
    RtPathRoundRect(p, AX0 + h, AY0 + h, AX1 - h, AY1 - h, Max(0, ARadius - h));
  FillPath(p, AColor, rfEvenOdd);
end;

procedure TRtRaster.Line(AX0, AY0, AX1, AY1, AWidth: Double; AColor: TRtColor; ACap: TRtLineCap);
var
  p: TRtPath;
begin
  p := Default(TRtPath);
  RtPathMove(p, AX0, AY0);
  RtPathLine(p, AX1, AY1);
  StrokePath(p, False, AWidth, AColor, ACap, ljMiter, 4, []);
end;

procedure TRtRaster.DrawText(AFont: TRtFont; const AText: string; AX, AY, ASize, AAngle: Double; AColor: TRtColor);
var
  cps: TRtCodePointArray;
  flat: TRtFlatGlyph;
  path: TRtPath;
  i, g: Integer;
  s, co, si, pen: Double;
begin
  if (AFont = nil) or (AText = '') or not (ASize > 0.2) or (ASize > 20000) or (AColor shr 24 = 0) then Exit;
  cps := RtCodePoints(AText);
  s := ASize / AFont.UnitsPerEm;
  co := Cos(AAngle);
  si := Sin(AAngle);
  if Abs(co) < 1e-15 then co := 0;
  if Abs(si) < 1e-15 then si := 0;
  flat := Default(TRtFlatGlyph);
  pen := 0;
  for i := 0 to High(cps) do
  begin
    g := AFont.GlyphIndex(cps[i]);
    // x' = O + s (pen + gx) u + s gy up, u = (cos, sin), up = (sin, -cos)
    RtFlattenGlyph(AFont.Outline(g), s * co, s * si, s * si, -s * co, AX + s * co * pen, AY + s * si * pen,
      0.2, flat);
    pen := pen + AFont.Advance(g);
  end;
  if flat.Count < 3 then Exit;
  path.Xs := flat.Xs;
  path.Ys := flat.Ys;
  path.Starts := flat.Starts;
  path.Count := flat.Count;
  path.Contours := flat.Contours;
  FillCoverage(path, AColor, rfNonZero);
end;

procedure TRtRaster.DrawRaster(const ASrc: array of LongWord; ASrcW, ASrcH: Integer; ASX, ASY, ASW, ASH,
  ADX, ADY, ADW, ADH: Double);
var
  x0, y0, x1, y1, x, y, ix, iy, fx, fy, ix1, iy1: Integer;
  sxF, syF, kx, ky: Int64;
  p00, p01, p10, p11: LongWord;
  a, r, g, b, w00, w01, w10, w11: LongWord;
  col: LongWord;

  function Ch(APix: LongWord; AShift: Integer): LongWord; inline;
  begin
    Result := (APix shr AShift) and $FF;
  end;

begin
  if (ASrcW <= 0) or (ASrcH <= 0) or (Length(ASrc) < ASrcW * ASrcH) or not (ADW > 0) or not (ADH > 0) or
    not (ASW > 0) or not (ASH > 0) then Exit;
  x0 := Max(FClipX0, Floor(ADX));
  y0 := Max(FClipY0, Floor(ADY));
  x1 := Min(FClipX1, Ceil(ADX + ADW));
  y1 := Min(FClipY1, Ceil(ADY + ADH));
  if (x1 <= x0) or (y1 <= y0) then Exit;
  // source steps per destination pixel, in 1/65536
  kx := Round(ASW / ADW * 65536);
  ky := Round(ASH / ADH * 65536);
  for y := y0 to y1 - 1 do
  begin
    // the source point of this pixel's centre, minus half a source pixel
    syF := Round((ASY + (y + 0.5 - ADY) * ASH / ADH) * 65536) - 32768;
    iy := Integer(Floor(syF / 65536));
    fy := Integer(syF - Int64(iy) * 65536) shr 8;     // 0..255
    iy1 := EnsureRange(iy + 1, 0, ASrcH - 1);
    iy := EnsureRange(iy, 0, ASrcH - 1);
    for x := x0 to x1 - 1 do
    begin
      sxF := Round((ASX + (x + 0.5 - ADX) * ASW / ADW) * 65536) - 32768;
      ix := Integer(Floor(sxF / 65536));
      fx := Integer(sxF - Int64(ix) * 65536) shr 8;
      ix1 := EnsureRange(ix + 1, 0, ASrcW - 1);
      ix := EnsureRange(ix, 0, ASrcW - 1);
      p00 := ASrc[iy * ASrcW + ix];
      p01 := ASrc[iy * ASrcW + ix1];
      p10 := ASrc[iy1 * ASrcW + ix];
      p11 := ASrc[iy1 * ASrcW + ix1];
      w00 := (256 - fx) * (256 - fy);
      w01 := fx * (256 - fy);
      w10 := (256 - fx) * fy;
      w11 := LongWord(fx) * fy;
      // premultiplied while filtered: no fringe at transparent edges
      a := Ch(p00, 24) * w00 + Ch(p01, 24) * w01 + Ch(p10, 24) * w10 + Ch(p11, 24) * w11;
      if a = 0 then Continue;
      r := Ch(p00, 16) * Ch(p00, 24) * w00 + Ch(p01, 16) * Ch(p01, 24) * w01 + Ch(p10, 16) * Ch(p10, 24) * w10 +
        Ch(p11, 16) * Ch(p11, 24) * w11;
      g := Ch(p00, 8) * Ch(p00, 24) * w00 + Ch(p01, 8) * Ch(p01, 24) * w01 + Ch(p10, 8) * Ch(p10, 24) * w10 +
        Ch(p11, 8) * Ch(p11, 24) * w11;
      b := Ch(p00, 0) * Ch(p00, 24) * w00 + Ch(p01, 0) * Ch(p01, 24) * w01 + Ch(p10, 0) * Ch(p10, 24) * w10 +
        Ch(p11, 0) * Ch(p11, 24) * w11;
      // back to straight colour, alpha out of 65536 * 255
      col := LongWord(Min(255, (a + 32768) shr 16)) shl 24 or
        (Min(255, (r + a div 2) div a) shl 16) or (Min(255, (g + a div 2) div a) shl 8) or Min(255, (b + a div 2) div a);
      BlendPixel(Pixels[y * FWidth + x], col, 255);
    end;
  end;
  if kx + ky = 0 then Exit;
end;

procedure InitTables;
var
  i: Integer;
begin
  for i := 0 to CIRCLE_STEPS do
  begin
    CosTab[i] := Cos(2 * Pi * i / CIRCLE_STEPS);
    SinTab[i] := Sin(2 * Pi * i / CIRCLE_STEPS);
  end;
  // exact where they are known, whatever the library's last bit
  for i := 0 to 4 do
  begin
    CosTab[i * CIRCLE_STEPS div 4] := Round(Cos(i * Pi / 2));
    SinTab[i * CIRCLE_STEPS div 4] := Round(Sin(i * Pi / 2));
  end;
end;

initialization
  InitTables;
end.
