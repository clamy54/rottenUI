unit uRtSvgPaint;
{ rottenUI — an SVG image (uRtSvg) painted in a theme's colours: its black
  becomes the ink (the theme's foreground), its white the paper (the
  background), its greys a mix of both, and what it leaves transparent
  shows a third colour. Texts are written in an embedded font (never a
  system one), narrowed when the SVG asked for a proportional font so
  that they keep about the room they had, each in its place among the
  shapes (what is drawn after a text covers it).
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

var
  { A text its transform stretches (wider or narrower than high) is drawn
    stretched; False: drawn as before this setting existed, at the
    transform's mean scale. Texts that are not stretched are drawn the same
    either way. }
  RtSvgStretchTexts: Boolean = True;

implementation

uses
  IntfGraphics, GraphType, FPImage, LCLType, LCLIntf;

const
  BAND_PIXELS = 2 * 1024 * 1024;
  MAX_LAYERS = 16;      // texts among the shapes: beyond, on top of them
  // The width of an average character of a proportional font, in em (a
  // monospace one takes 0.6).
  PROPORTIONAL_EM = 0.52;
  // Beyond this difference between its width and its height scales, a text
  // is drawn stretched.
  STRETCH_MIN = 0.03;
  MAX_STRETCH_PIXELS = 4 * 1000 * 1000;   // a stretched text's box on the canvas

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

{ ACanvas's pixels under ARect (clipped to it), as an image to change. }
function GrabArea(ACanvas: TCanvas; var ARect: TRect): TBitmap;
var
  clip: TRect;
begin
  Result := nil;
  clip := ACanvas.ClipRect;
  if not IntersectRect(ARect, ARect, clip) then Exit;
  if (ARect.Right - ARect.Left <= 0) or (ARect.Bottom - ARect.Top <= 0) or
    (Int64(ARect.Right - ARect.Left) * (ARect.Bottom - ARect.Top) > MAX_STRETCH_PIXELS) then Exit;
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  Result.Canvas.CopyRect(Rect(0, 0, Result.Width, Result.Height), ACanvas, ARect);
end;

{ A text stretched: written level at its letters' height (AHeight) into a
  mask, then laid stretched by ARatio along its line, turned by AAngle
  (radians, clockwise on the canvas), its anchor at (APX, APY) (ADu, ADv:
  the anchor's place in the level text), blended in AColor. }
procedure PaintStretched(ACanvas: TCanvas; const AText, AFontName: string; AStyle: TFontStyles;
  AHeight, ARatio, AAngle, APX, APY: Double; AAnchor, ABaseline: Integer; AColor: TColor);
var
  mask: TBitmap;
  mi, di: TLazIntfImage;
  area: TBitmap;
  tw, th, mw, mh, x, y, ix, iy, padX, padY: Integer;
  du, dv, ux, uy, vx, vy, dx, dy, a, b, fx, fy, c00, c10, c01, c11, cov, cx, cy, minx, miny, maxx, maxy: Double;
  tm: TTextMetric;
  r, clip: TRect;
  ink: TRgbF;
  fp: TFPColor;
  onWhite: array of Single;
  cover: array of Single;
  q: Integer;

  procedure Level(ABack, AInk: TColor);
  begin
    mask.Canvas.Brush.Style := bsSolid;
    mask.Canvas.Brush.Color := ABack;
    mask.Canvas.FillRect(Rect(0, 0, mw, mh));
    mask.Canvas.Font.Color := AInk;
    mask.Canvas.Brush.Style := bsClear;
    mask.Canvas.TextOut(padX, padY, AText);
  end;

  function Grey(AImage: TLazIntfImage; AX, AY: Integer): Single;
  begin
    fp := AImage.Colors[AX, AY];
    Result := ((fp.Red shr 8) + (fp.Green shr 8) + (fp.Blue shr 8)) / (3 * 255);
  end;

begin
  mask := TBitmap.Create;
  try
    mask.PixelFormat := pf24bit;
    mask.Canvas.Font.Name := AFontName;
    mask.Canvas.Font.Style := AStyle;
    mask.Canvas.Font.Orientation := 0;
    mask.Canvas.Font.Height := -Max(1, Round(AHeight));
    mask.Canvas.Font.Quality := fqAntialiased;
    tw := mask.Canvas.TextWidth(AText);
    th := mask.Canvas.TextHeight(AText);
    tm := Default(TTextMetric);
    if not GetTextMetrics(mask.Canvas.Handle, tm) then
    begin
      tm.tmAscent := Round(AHeight * 0.8);
      tm.tmDescent := Round(AHeight * 0.2);
    end;
    // (Codex review 155) Room for what overhangs the advance (an italic f,
    // a j), the advance kept for the anchor.
    padX := 2 + Round(0.35 * AHeight);
    padY := 2 + Round(0.1 * AHeight);
    mw := tw + 2 * padX;
    mh := th + 2 * padY;
    if (tw <= 0) or (th <= 0) or (Int64(mw) * mh > MAX_STRETCH_PIXELS) then Exit;
    mask.SetSize(mw, mh);
    SetLength(onWhite, mw * mh);
    SetLength(cover, mw * mh);
    // (Codex review 155) Its coverage from two drawings, on white then on
    // black: what a glyph paints opaque counts whole, whatever its colour
    // (a colour font, an emoji), its antialiased edges in proportion.
    Level(clWhite, clBlack);
    mi := mask.CreateIntfImage;
    try
      for y := 0 to mh - 1 do
        for x := 0 to mw - 1 do onWhite[y * mw + x] := Grey(mi, x, y);
    finally
      mi.Free;
    end;
    Level(clBlack, clBlack);
    mi := mask.CreateIntfImage;
    try
      for y := 0 to mh - 1 do
        for x := 0 to mw - 1 do
        begin
          q := y * mw + x;
          cover[q] := EnsureRange(1 - (onWhite[q] - Grey(mi, x, y)), 0, 1);
        end;
    finally
      mi.Free;
    end;
  finally
    mask.Free;
  end;
  case AAnchor of
    1: du := tw / 2;
    2: du := tw;
  else
    du := 0;
  end;
  case ABaseline of
    1: dv := (tm.tmAscent + tm.tmDescent) / 2;
    2: dv := 0;
  else
    dv := tm.tmAscent;
  end;
  ux := Cos(AAngle); uy := Sin(AAngle);
  vx := -Sin(AAngle); vy := Cos(AAngle);
  // (Codex review 155) Its box on the canvas in real numbers, within the
  // canvas's clip before it becomes pixels (a huge stretch overflows them).
  minx := MaxDouble; miny := MaxDouble; maxx := -MaxDouble; maxy := -MaxDouble;
  for q := 0 to 3 do
  begin
    if (q and 1) = 0 then a := -du - padX else a := mw - padX - du;
    if (q and 2) = 0 then b := -dv - padY else b := mh - padY - dv;
    cx := APX + ux * a * ARatio + vx * b;
    cy := APY + uy * a * ARatio + vy * b;
    minx := Min(minx, cx); maxx := Max(maxx, cx);
    miny := Min(miny, cy); maxy := Max(maxy, cy);
  end;
  clip := ACanvas.ClipRect;
  minx := Max(minx - 1, clip.Left);
  miny := Max(miny - 1, clip.Top);
  maxx := Min(maxx + 2, clip.Right);
  maxy := Min(maxy + 2, clip.Bottom);
  if (maxx <= minx) or (maxy <= miny) or IsNan(minx) or IsNan(miny) then Exit;
  r := Rect(Floor(minx), Floor(miny), Ceil(maxx), Ceil(maxy));
  area := GrabArea(ACanvas, r);
  if area = nil then Exit;
  ink := Rgb3(AColor);
  try
    di := area.CreateIntfImage;
    try
      for y := 0 to area.Height - 1 do
        for x := 0 to area.Width - 1 do
        begin
          // the canvas's pixel back in the mask (its centre), sampled
          dx := r.Left + x + 0.5 - APX;
          dy := r.Top + y + 0.5 - APY;
          a := (dx * ux + dy * uy) / ARatio + du + padX - 0.5;
          b := dx * vx + dy * vy + dv + padY - 0.5;
          if (a < -1) or (b < -1) or (a > mw) or (b > mh) then Continue;
          ix := Floor(a);
          iy := Floor(b);
          fx := a - ix;
          fy := b - iy;
          if (ix >= 0) and (iy >= 0) and (ix < mw) and (iy < mh) then c00 := cover[iy * mw + ix] else c00 := 0;
          if (ix + 1 >= 0) and (iy >= 0) and (ix + 1 < mw) and (iy < mh) then c10 := cover[iy * mw + ix + 1] else c10 := 0;
          if (ix >= 0) and (iy + 1 >= 0) and (ix < mw) and (iy + 1 < mh) then c01 := cover[(iy + 1) * mw + ix] else c01 := 0;
          if (ix + 1 >= 0) and (iy + 1 >= 0) and (ix + 1 < mw) and (iy + 1 < mh) then c11 := cover[(iy + 1) * mw + ix + 1]
          else c11 := 0;
          cov := (c00 * (1 - fx) + c10 * fx) * (1 - fy) + (c01 * (1 - fx) + c11 * fx) * fy;
          if cov <= 0.004 then Continue;
          cov := Min(1, cov);
          fp := di.Colors[x, y];
          fp.Red := Round(EnsureRange(ink.R * cov + (fp.Red shr 8) * (1 - cov), 0, 255)) * 257;
          fp.Green := Round(EnsureRange(ink.G * cov + (fp.Green shr 8) * (1 - cov), 0, 255)) * 257;
          fp.Blue := Round(EnsureRange(ink.B * cov + (fp.Blue shr 8) * (1 - cov), 0, 255)) * 257;
          fp.Alpha := $FFFF;
          di.Colors[x, y] := fp;
        end;
      area.LoadFromIntfImage(di);
    finally
      di.Free;
    end;
    ACanvas.Draw(r.Left, r.Top, area);
  finally
    area.Free;
  end;
end;

{ The texts whose Order lies in AOrderLo..AOrderHi. }
procedure PaintTextRange(AImage: TRtSvgImage; ACanvas: TCanvas; const AM: TRtSvgMatrix;
  AInk, APaper: TColor; const AFontName: string; AOrderLo, AOrderHi: Integer);
var
  i, tw: Integer;
  t: TRtSvgText;
  m: TRtSvgMatrix;
  px, py, k, size, target, ang, du, dv, ux, uy, vx, vy, lum, along, across, stretch: Double;
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
    if (t.Order < AOrderLo) or (t.Order > AOrderHi) then Continue;
    if (t.Text = '') or (t.Alpha <= 0.02) or AImage.TextHidden[i] then Continue;
    m := RtSvgMul(AM, t.M);
    k := Sqrt(Abs(m.A * m.D - m.B * m.C));
    size := t.Size * k;
    // Its scales along its line and across it: a stretched text, unless
    // the application keeps the former drawing (RtSvgStretchTexts).
    along := Sqrt(m.A * m.A + m.B * m.B);
    stretch := 1;
    if RtSvgStretchTexts and (along > 1e-12) then
    begin
      across := Abs(m.A * m.D - m.B * m.C) / along;
      if (across > 1e-12) and (Abs(along / across - 1) > STRETCH_MIN) then
      begin
        stretch := along / across;
        size := t.Size * across;
      end;
    end;
    if IsNan(size) or (size < 3) or (size > 4000) then Continue;
    RtSvgApply(m, t.X, t.Y, px, py);
    // Not a sane place, or far off the canvas (a text is never longer
    // than this): skipped.
    // (Codex review 155) a stretched one reaches as far as it is stretched
    if IsNan(px) or IsNan(py) or (px < -size * 200 * Max(1, stretch)) or (py < -size * 200 * Max(1, stretch)) or
      (px > ACanvas.Width + size * 200 * Max(1, stretch)) or (py > ACanvas.Height + size * 200 * Max(1, stretch)) then
      Continue;
    ang := ArcTan2(m.B, m.A);
    if IsNan(ang) then Continue;
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
    if stretch <> 1 then
    begin
      PaintStretched(ACanvas, t.Text, AFontName, style, size, stretch, ang, px, py, t.Anchor, t.Baseline,
        ACanvas.Font.Color);
      Continue;
    end;
    // The canvas turns counterclockwise, the matrix clockwise (y down).
    ACanvas.Font.Orientation := Round(-RadToDeg(ang) * 10);
    ACanvas.TextOut(Round(px - ux * du - vx * dv), Round(py - uy * du - vy * dv), t.Text);
  end;
  ACanvas.Font.Orientation := 0;
  ACanvas.Brush.Style := bsSolid;
end;

procedure RtSvgPaintTexts(AImage: TRtSvgImage; ACanvas: TCanvas; const AM: TRtSvgMatrix;
  AInk, APaper: TColor; const AFontName: string);
begin
  PaintTextRange(AImage, ACanvas, AM, AInk, APaper, AFontName, Low(Integer), High(Integer));
end;

procedure RtSvgPaint(AImage: TRtSvgImage; ABitmap: TBitmap; AWidth, AHeight: Integer;
  const AM: TRtSvgMatrix; AInk, APaper, AVoid: TColor; const AFontName: string);
var
  intf: TLazIntfImage;
  desc: TRawImageDescription;
  r: TRtSvgRaster;
  ink, paper, void: TRgbF;
  y0, bh, x, y, i, j, k, n, layer, lo, hi: Integer;
  row: PByte;
  a, l, cr, cg, cb: Single;
  breaks: array of Integer;
  fp: TFPColor;
begin
  AWidth := Max(1, AWidth);
  AHeight := Max(1, AHeight);
  ink := Rgb3(AInk);
  paper := Rgb3(APaper);
  void := Rgb3(AVoid);
  bh := Max(1, BAND_PIXELS div AWidth);
  // (Codex review 90) Texts stand among the shapes: the shapes are
  // painted in layers cut where texts stand, each layer's texts written
  // before the next layer covers them. Beyond MAX_LAYERS, texts on top.
  breaks := nil;
  for i := 0 to AImage.TextCount - 1 do
  begin
    n := EnsureRange(AImage.Texts[i].Order, 0, AImage.ShapeCount);
    j := 0;
    while (j < Length(breaks)) and (breaks[j] < n) do Inc(j);
    if (j < Length(breaks)) and (breaks[j] = n) then Continue;
    SetLength(breaks, Length(breaks) + 1);
    for k := High(breaks) downto j + 1 do breaks[k] := breaks[k - 1];
    breaks[j] := n;
    if Length(breaks) > MAX_LAYERS then Break;
  end;
  if Length(breaks) > MAX_LAYERS then breaks := nil;
  // The last layer ends with the shapes.
  if (Length(breaks) = 0) or (breaks[High(breaks)] < AImage.ShapeCount) then
  begin
    SetLength(breaks, Length(breaks) + 1);
    breaks[High(breaks)] := AImage.ShapeCount;
  end;
  lo := 0;
  for layer := 0 to High(breaks) do
  begin
    hi := breaks[layer];
    if layer = 0 then
    begin
      // The first layer over the void, written whole.
      intf := TLazIntfImage.Create(0, 0);
      try
        // 32 bits per pixel, as screens are: copied without conversion.
        desc.Init_BPP32_B8G8R8_BIO_TTB(AWidth, AHeight);
        intf.DataDescription := desc;
        y0 := 0;
        while y0 < AHeight do
        begin
          r := Default(TRtSvgRaster);
          r.Width := AWidth;
          r.Height := Min(bh, AHeight - y0);
          AImage.Render(RtSvgMul(RtSvgTranslate(0, -y0), AM), r, lo, hi);
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
              row[4 * x] := Round(EnsureRange(cb, 0, 255));
              row[4 * x + 1] := Round(EnsureRange(cg, 0, 255));
              row[4 * x + 2] := Round(EnsureRange(cr, 0, 255));
              row[4 * x + 3] := 255;
            end;
          end;
          Inc(y0, r.Height);
        end;
        ABitmap.LoadFromIntfImage(intf);
      finally
        intf.Free;
      end;
    end
    else if hi > lo then
    begin
      // A later layer over what is painted (texts included).
      intf := ABitmap.CreateIntfImage;
      try
        y0 := 0;
        while y0 < AHeight do
        begin
          r := Default(TRtSvgRaster);
          r.Width := AWidth;
          r.Height := Min(bh, AHeight - y0);
          AImage.Render(RtSvgMul(RtSvgTranslate(0, -y0), AM), r, lo, hi);
          for y := 0 to r.Height - 1 do
            for x := 0 to AWidth - 1 do
            begin
              i := y * AWidth + x;
              a := r.Alpha[i];
              if a <= 0.002 then Continue;
              l := EnsureRange(r.Lum[i] / a, 0, 1);
              fp := intf.Colors[x, y0 + y];
              cr := (ink.R + (paper.R - ink.R) * l) * a + (fp.Red shr 8) * (1 - a);
              cg := (ink.G + (paper.G - ink.G) * l) * a + (fp.Green shr 8) * (1 - a);
              cb := (ink.B + (paper.B - ink.B) * l) * a + (fp.Blue shr 8) * (1 - a);
              fp.Red := Round(EnsureRange(cr, 0, 255)) * 257;
              fp.Green := Round(EnsureRange(cg, 0, 255)) * 257;
              fp.Blue := Round(EnsureRange(cb, 0, 255)) * 257;
              fp.Alpha := $FFFF;
              intf.Colors[x, y0 + y] := fp;
            end;
          Inc(y0, r.Height);
        end;
        ABitmap.LoadFromIntfImage(intf);
      finally
        intf.Free;
      end;
    end;
    // The texts standing after these shapes (all the rest after the last).
    if layer = 0 then j := Low(Integer) else j := lo + 1;
    if layer = High(breaks) then n := High(Integer) else n := hi;
    PaintTextRange(AImage, ABitmap.Canvas, AM, AInk, APaper, AFontName, j, n);
    lo := hi;
  end;
  r.Lum := nil;
  r.Alpha := nil;
end;

end.
