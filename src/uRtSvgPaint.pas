unit uRtSvgPaint;
{ rottenUI — an SVG image (uRtSvg) painted in a theme's colours: its black
  becomes the ink (the theme's foreground), its white the paper (the
  background), its greys a mix of both, and what it leaves transparent
  shows a third colour. Texts are written in an embedded font (never a
  system one), narrowed when the SVG asked for a proportional font so
  that they keep about the room they had.
  SPDX-License-Identifier: GPL-3.0-or-later }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, uRtSvg;

{ Paints AImage onto ABitmap, sized AWidth x AHeight: AM maps the image's
  pixels onto the bitmap's. Rendered by bands, so that a large bitmap
  never needs the rasterizer's buffers for all its pixels at once. }
procedure RtSvgPaint(AImage: TRtSvgImage; ABitmap: TBitmap; AWidth, AHeight: Integer;
  const AM: TRtSvgMatrix; AInk, APaper, AVoid: TColor; const AFontName: string);

{ The texts only, onto any canvas (AM: the image's pixels to the canvas's). }
procedure RtSvgPaintTexts(AImage: TRtSvgImage; ACanvas: TCanvas; const AM: TRtSvgMatrix;
  AInk, APaper: TColor; const AFontName: string);

implementation

uses
  IntfGraphics, GraphType, LCLType, LCLIntf;

const
  BAND_PIXELS = 2 * 1024 * 1024;
  // The width of an average character of a proportional font, in em (a
  // monospace one takes 0.6).
  PROPORTIONAL_EM = 0.52;

type
  TRgbF = record
    R, G, B: Single;
  end;

function Rgb3(AColor: TColor): TRgbF;
var
  c: LongInt;
begin
  c := ColorToRGB(AColor);
  Result.R := Red(c);
  Result.G := Green(c);
  Result.B := Blue(c);
end;

function Utf8Chars(const S: string): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if (Ord(S[i]) and $C0) <> $80 then Inc(Result);
end;

procedure RtSvgPaintTexts(AImage: TRtSvgImage; ACanvas: TCanvas; const AM: TRtSvgMatrix;
  AInk, APaper: TColor; const AFontName: string);
var
  i, tw: Integer;
  t: TRtSvgText;
  m: TRtSvgMatrix;
  px, py, k, size, target, ang, du, dv, ux, uy, vx, vy, lum: Double;
  tm: TTextMetric;
  ink, paper: TRgbF;
  style: TFontStyles;
begin
  ink := Rgb3(AInk);
  paper := Rgb3(APaper);
  ACanvas.Brush.Style := bsClear;
  for i := 0 to AImage.TextCount - 1 do
  begin
    t := AImage.Texts[i];
    if (t.Text = '') or (t.Alpha <= 0.02) then Continue;
    m := RtSvgMul(AM, t.M);
    k := Sqrt(Abs(m.A * m.D - m.B * m.C));
    size := t.Size * k;
    if (size < 3) or (size > 4000) then Continue;
    RtSvgApply(m, t.X, t.Y, px, py);
    // Far off the canvas: skipped (a text is never longer than this).
    if (px < -size * 200) or (py < -size * 200) or (px > ACanvas.Width + size * 200) or
      (py > ACanvas.Height + size * 200) then Continue;
    ang := ArcTan2(m.B, m.A);
    style := [];
    if t.Bold then Include(style, fsBold);
    if t.Italic then Include(style, fsItalic);
    ACanvas.Font.Name := AFontName;
    ACanvas.Font.Style := style;
    ACanvas.Font.Orientation := 0;
    ACanvas.Font.Height := -Max(1, Round(size));
    tw := ACanvas.TextWidth(t.Text);
    if not t.Mono then
    begin
      target := PROPORTIONAL_EM * size * Utf8Chars(t.Text);
      if (tw > target) and (target > 0) then
      begin
        size := size * target / tw;
        if size < 3 then Continue;
        ACanvas.Font.Height := -Max(1, Round(size));
        tw := ACanvas.TextWidth(t.Text);
      end;
    end;
    tm := Default(TTextMetric);
    if not GetTextMetrics(ACanvas.Handle, tm) then
    begin
      tm.tmAscent := Round(size * 0.8);
      tm.tmDescent := Round(size * 0.2);
    end;
    case t.Anchor of
      1: du := tw / 2;
      2: du := tw;
    else
      du := 0;
    end;
    case t.Baseline of
      1: dv := (tm.tmAscent + tm.tmDescent) / 2;
      2: dv := 0;
    else
      dv := tm.tmAscent;
    end;
    ux := Cos(ang); uy := Sin(ang);
    vx := -Sin(ang); vy := Cos(ang);
    // The text's grey, over the paper.
    lum := t.Lum * t.Alpha + (1 - t.Alpha);
    ACanvas.Font.Color := RGBToColor(Round(ink.R + (paper.R - ink.R) * lum),
      Round(ink.G + (paper.G - ink.G) * lum), Round(ink.B + (paper.B - ink.B) * lum));
    // The canvas turns counterclockwise, the matrix clockwise (y down).
    ACanvas.Font.Orientation := Round(-RadToDeg(ang) * 10);
    ACanvas.TextOut(Round(px - ux * du - vx * dv), Round(py - uy * du - vy * dv), t.Text);
  end;
  ACanvas.Font.Orientation := 0;
  ACanvas.Brush.Style := bsSolid;
end;

procedure RtSvgPaint(AImage: TRtSvgImage; ABitmap: TBitmap; AWidth, AHeight: Integer;
  const AM: TRtSvgMatrix; AInk, APaper, AVoid: TColor; const AFontName: string);
var
  intf: TLazIntfImage;
  desc: TRawImageDescription;
  r: TRtSvgRaster;
  ink, paper, void: TRgbF;
  y0, bh, x, y, i: Integer;
  row: PByte;
  a, l, cr, cg, cb: Single;
begin
  AWidth := Max(1, AWidth);
  AHeight := Max(1, AHeight);
  ink := Rgb3(AInk);
  paper := Rgb3(APaper);
  void := Rgb3(AVoid);
  intf := TLazIntfImage.Create(0, 0);
  try
    desc.Init_BPP24_B8G8R8_BIO_TTB(AWidth, AHeight);
    intf.DataDescription := desc;
    bh := Max(1, BAND_PIXELS div AWidth);
    y0 := 0;
    while y0 < AHeight do
    begin
      r := Default(TRtSvgRaster);
      r.Width := AWidth;
      r.Height := Min(bh, AHeight - y0);
      AImage.Render(RtSvgMul(RtSvgTranslate(0, -y0), AM), r);
      for y := 0 to r.Height - 1 do
      begin
        row := intf.GetDataLineStart(y0 + y);
        for x := 0 to AWidth - 1 do
        begin
          i := y * AWidth + x;
          a := r.Alpha[i];
          if a > 0.0001 then l := EnsureRange(r.Lum[i] / a, 0, 1) else l := 1;
          cr := (ink.R + (paper.R - ink.R) * l) * a + void.R * (1 - a);
          cg := (ink.G + (paper.G - ink.G) * l) * a + void.G * (1 - a);
          cb := (ink.B + (paper.B - ink.B) * l) * a + void.B * (1 - a);
          row[3 * x] := Round(EnsureRange(cb, 0, 255));
          row[3 * x + 1] := Round(EnsureRange(cg, 0, 255));
          row[3 * x + 2] := Round(EnsureRange(cr, 0, 255));
        end;
      end;
      Inc(y0, r.Height);
    end;
    r.Lum := nil;
    r.Alpha := nil;
    ABitmap.LoadFromIntfImage(intf);
  finally
    intf.Free;
  end;
  RtSvgPaintTexts(AImage, ABitmap.Canvas, AM, AInk, APaper, AFontName);
end;

end.
