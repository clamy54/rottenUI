// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtFont;

{$mode objfpc}{$H+}

{ A TrueType reader of its own (no LCL, no OS): the glyphs of a font as
  outlines, so that a text is drawn by rottenUI's rasterizer the same on
  every system. Read as hostile input: every offset and count bounded,
  composite glyphs to a depth of 8, a glyph's points bounded; no hinting
  (the same shapes everywhere). Tables read: head, hhea, maxp, hmtx, loca,
  glyf, cmap (formats 4 and 12). }

interface

uses
  SysUtils;

type
  ERtFont = class(Exception);

  { A glyph's outline in font units (y up): contours of quadratic points. }
  TRtGlyphOutline = record
    X, Y: array of Single;
    OnCurve: array of Boolean;
    EndPts: array of Integer;      // the last point of each contour
    Count: Integer;                // points
  end;

  TRtFont = class
  private
    FData: RawByteString;
    FUnitsPerEm: Integer;
    FAscent, FDescent, FLineGap: Integer;
    FNumGlyphs, FNumHMetrics: Integer;
    FLongLoca: Boolean;
    FHmtx, FLoca, FGlyf, FGlyfLen, FLocaLen, FHmtxLen: Integer;
    FCmap: Integer;                // the chosen subtable's offset, 0 none
    FCmapFormat: Integer;
    FCmapEnd: Integer;             // its end (its declared length, within the table)
    FOutlines: array of TRtGlyphOutline;
    FLoaded: array of Boolean;
    FAdvances: array of Integer;
    function U8(AOfs: Integer): Integer;
    function U16(AOfs: Integer): Integer;
    function I16(AOfs: Integer): Integer;
    function U32(AOfs: Integer): Cardinal;
    function Table(const ATag: string; out ALen: Integer): Integer;
    procedure Need(AOfs, ALen: Integer);
    procedure ReadGlyph(AGlyph, ADepth: Integer; var AOut: TRtGlyphOutline; const AM: array of Double;
      var ABudget: Integer);
    function CU16(AOfs: Integer): Integer;
    function CU32(AOfs: Integer): Cardinal;
    function GlyphRange(AGlyph: Integer; out AOfs, ALen: Integer): Boolean;
  public
    { The font in AData (a .ttf file's bytes); raises ERtFont. }
    constructor Create(const AData: RawByteString);
    { The glyph of a Unicode code point, 0 (.notdef) when none. }
    function GlyphIndex(ACode: Cardinal): Integer;
    { A glyph's advance, in font units. }
    function Advance(AGlyph: Integer): Integer;
    { A glyph's outline, in font units (read once). }
    function Outline(AGlyph: Integer): TRtGlyphOutline;
    property UnitsPerEm: Integer read FUnitsPerEm;
    property Ascent: Integer read FAscent;       // above the baseline, positive
    property Descent: Integer read FDescent;     // below it, negative
    property LineGap: Integer read FLineGap;
    property GlyphCount: Integer read FNumGlyphs;
  end;

  { An outline flattened to polygons: Xs / Ys of every contour after one
    another, Starts the first point of each (pixels, y down). }
  TRtFlatGlyph = record
    Xs, Ys: array of Double;
    Starts: array of Integer;
    Count, Contours: Integer;
  end;

const
  RTFONT_MAX_BYTES = 32 * 1024 * 1024;
  RTFONT_MAX_POINTS = 65536;

{ AOutline placed by the affine A B C D E F (font units to pixels: x' = A x
  + C y + E, y' = B x + D y + F), its curves cut finer than ATolerance
  pixels, appended to AFlat. }
procedure RtFlattenGlyph(const AOutline: TRtGlyphOutline; A, B, C, D, E, F, ATolerance: Double;
  var AFlat: TRtFlatGlyph);

implementation

uses
  Math;

function TRtFont.U8(AOfs: Integer): Integer;
begin
  if (AOfs < 0) or (AOfs >= Length(FData)) then raise ERtFont.Create('font: read out of the file');
  Result := Ord(FData[AOfs + 1]);
end;

function TRtFont.U16(AOfs: Integer): Integer;
begin
  if (AOfs < 0) or (AOfs + 2 > Length(FData)) then raise ERtFont.Create('font: read out of the file');
  Result := Ord(FData[AOfs + 1]) shl 8 or Ord(FData[AOfs + 2]);
end;

function TRtFont.I16(AOfs: Integer): Integer;
begin
  Result := U16(AOfs);
  if Result >= 32768 then Dec(Result, 65536);
end;

function TRtFont.U32(AOfs: Integer): Cardinal;
begin
  if (AOfs < 0) or (AOfs + 4 > Length(FData)) then raise ERtFont.Create('font: read out of the file');
  Result := Cardinal(Ord(FData[AOfs + 1])) shl 24 or Cardinal(Ord(FData[AOfs + 2])) shl 16 or
    Cardinal(Ord(FData[AOfs + 3])) shl 8 or Cardinal(Ord(FData[AOfs + 4]));
end;

procedure TRtFont.Need(AOfs, ALen: Integer);
begin
  if (AOfs < 0) or (ALen < 0) or (Int64(AOfs) + ALen > Length(FData)) then
    raise ERtFont.Create('font: a table out of the file');
end;

function TRtFont.Table(const ATag: string; out ALen: Integer): Integer;
var
  n, i, rec: Integer;
  ofs, len: Cardinal;
begin
  Result := 0;
  ALen := 0;
  n := U16(4);
  if n > 256 then raise ERtFont.Create('font: too many tables');
  for i := 0 to n - 1 do
  begin
    rec := 12 + 16 * i;
    Need(rec, 16);
    if Copy(FData, rec + 1, 4) = ATag then
    begin
      ofs := U32(rec + 8);
      len := U32(rec + 12);
      if (ofs > Cardinal(Length(FData))) or (len > Cardinal(Length(FData)) - ofs) then
        raise ERtFont.CreateFmt('font: table %s out of the file', [ATag]);
      ALen := Integer(len);
      Exit(Integer(ofs));
    end;
  end;
end;

constructor TRtFont.Create(const AData: RawByteString);
var
  head, hhea, maxp, cmap, len, n, i, rec, sub, best, bestRank, rank, fmt, bestEnd: Integer;
  sublen: Int64;
  version: Cardinal;
begin
  inherited Create;
  if (Length(AData) < 12) or (Length(AData) > RTFONT_MAX_BYTES) then
    raise ERtFont.Create('font: not a TrueType file');
  FData := AData;
  version := U32(0);
  if (version <> $00010000) and (version <> $74727565 {'true'}) then
    raise ERtFont.Create('font: not a TrueType file (glyf outlines)');
  head := Table('head', len);
  if (head = 0) or (len < 54) then raise ERtFont.Create('font: no head table');
  FUnitsPerEm := U16(head + 18);
  if (FUnitsPerEm < 16) or (FUnitsPerEm > 16384) then raise ERtFont.Create('font: bad units per em');
  FLongLoca := I16(head + 50) = 1;
  hhea := Table('hhea', len);
  if (hhea = 0) or (len < 36) then raise ERtFont.Create('font: no hhea table');
  FAscent := I16(hhea + 4);
  FDescent := I16(hhea + 6);
  FLineGap := I16(hhea + 8);
  FNumHMetrics := U16(hhea + 34);
  maxp := Table('maxp', len);
  if (maxp = 0) or (len < 6) then raise ERtFont.Create('font: no maxp table');
  FNumGlyphs := U16(maxp + 4);
  if (FNumGlyphs = 0) or (FNumHMetrics = 0) or (FNumHMetrics > FNumGlyphs) then
    raise ERtFont.Create('font: bad glyph counts');
  FHmtx := Table('hmtx', FHmtxLen);
  if (FHmtx = 0) or (FHmtxLen < 4 * FNumHMetrics) then raise ERtFont.Create('font: no hmtx table');
  FLoca := Table('loca', FLocaLen);
  if FLongLoca then n := 4 else n := 2;
  if (FLoca = 0) or (FLocaLen < n * (FNumGlyphs + 1)) then raise ERtFont.Create('font: no loca table');
  FGlyf := Table('glyf', FGlyfLen);
  if FGlyf = 0 then raise ERtFont.Create('font: no glyf table (CFF outlines are not read)');
  // cmap: Unicode full (3,10 / 0,4+ format 12) first, else BMP (3,1 / 0,x format 4)
  cmap := Table('cmap', len);
  FCmap := 0;
  if cmap <> 0 then
  begin
    n := U16(cmap + 2);
    if n > 64 then n := 64;
    best := 0;
    bestRank := 0;
    bestEnd := 0;
    sublen := 0;
    for i := 0 to n - 1 do
    begin
      rec := cmap + 4 + 8 * i;
      // (Codex review 169) the record and its subtable within the table
      if rec + 8 > cmap + len then Break;
      if U32(rec + 4) > Cardinal(len) then Continue;
      sub := cmap + Integer(U32(rec + 4));
      if sub + 16 > cmap + len then Continue;
      fmt := U16(sub);
      rank := 0;
      if fmt = 12 then
      begin
        sublen := Int64(U32(sub + 4));
        if (sublen >= 16) and (sub + sublen <= cmap + len) and
          (16 + 12 * Int64(U32(sub + 12)) <= sublen) then rank := 2;
      end
      else if fmt = 4 then
      begin
        sublen := U16(sub + 2);
        if (sublen >= 16) and (sub + sublen <= cmap + len) and (16 + 4 * Int64(U16(sub + 6)) <= sublen) then
          rank := 1;
      end;
      if (U16(rec) = 1) then rank := 0;         // Macintosh encodings: no
      if rank > bestRank then
      begin
        bestRank := rank;
        best := sub;
        bestEnd := sub + Integer(sublen);
      end;
    end;
    if best <> 0 then
    begin
      FCmap := best;
      FCmapFormat := U16(best);
      FCmapEnd := bestEnd;
    end;
  end;
  SetLength(FOutlines, FNumGlyphs);
  SetLength(FLoaded, FNumGlyphs);
  SetLength(FAdvances, FNumGlyphs);
  for i := 0 to FNumGlyphs - 1 do
    if i < FNumHMetrics then FAdvances[i] := U16(FHmtx + 4 * i)
    else FAdvances[i] := FAdvances[FNumHMetrics - 1];
end;

function TRtFont.CU16(AOfs: Integer): Integer;
begin
  if (AOfs < FCmap) or (AOfs + 2 > FCmapEnd) then raise ERtFont.Create('font: cmap read out of its table');
  Result := U16(AOfs);
end;

function TRtFont.CU32(AOfs: Integer): Cardinal;
begin
  if (AOfs < FCmap) or (AOfs + 4 > FCmapEnd) then raise ERtFont.Create('font: cmap read out of its table');
  Result := U32(AOfs);
end;

function TRtFont.GlyphIndex(ACode: Cardinal): Integer;
var
  segX2, segs, lo, hi, mid, endOfs, startOfs, deltaOfs, rangeOfs, e, st, delta, ro, gOfs, n: Integer;
  groups: Cardinal;
  g, sc, ec, sg: Cardinal;
  l, h, m: Int64;
begin
  Result := 0;
  if FCmap = 0 then Exit;
  try
  if FCmapFormat = 4 then
  begin
    if ACode > $FFFF then Exit;
    segX2 := CU16(FCmap + 6);
    segs := segX2 div 2;
    if segs = 0 then Exit;
    endOfs := FCmap + 14;
    startOfs := endOfs + segX2 + 2;
    deltaOfs := startOfs + segX2;
    rangeOfs := deltaOfs + segX2;
    // the first segment whose end is not below the code
    lo := 0;
    hi := segs - 1;
    while lo < hi do
    begin
      mid := (lo + hi) div 2;
      if CU16(endOfs + 2 * mid) < Integer(ACode) then lo := mid + 1 else hi := mid;
    end;
    e := CU16(endOfs + 2 * lo);
    st := CU16(startOfs + 2 * lo);
    if (Integer(ACode) < st) or (Integer(ACode) > e) then Exit;
    delta := SmallInt(CU16(deltaOfs + 2 * lo));
    ro := CU16(rangeOfs + 2 * lo);
    if ro = 0 then
      Result := (Integer(ACode) + delta) and $FFFF
    else
    begin
      gOfs := rangeOfs + 2 * lo + ro + 2 * (Integer(ACode) - st);
      n := CU16(gOfs);
      if n <> 0 then Result := (n + delta) and $FFFF;
    end;
  end
  else if FCmapFormat = 12 then
  begin
    groups := CU32(FCmap + 12);
    if groups > 1000000 then Exit;
    l := 0;
    h := Int64(groups) - 1;
    while l <= h do
    begin
      m := (l + h) div 2;
      g := FCmap + 16 + Cardinal(m) * 12;
      sc := CU32(g);
      ec := CU32(g + 4);
      if ACode < sc then h := m - 1
      else if ACode > ec then l := m + 1
      else
      begin
        sg := CU32(g + 8);
        Result := Integer(sg + (ACode - sc));
        Break;
      end;
    end;
  end;
  except
    // (Codex review 169) a damaged cmap: no glyph, never an error at each frame
    on ERtFont do Result := 0;
  end;
  if (Result < 0) or (Result >= FNumGlyphs) then Result := 0;
end;

function TRtFont.Advance(AGlyph: Integer): Integer;
begin
  if (AGlyph < 0) or (AGlyph >= FNumGlyphs) then AGlyph := 0;
  Result := FAdvances[AGlyph];
end;

function TRtFont.GlyphRange(AGlyph: Integer; out AOfs, ALen: Integer): Boolean;
var
  a, b: Int64;
begin
  if FLongLoca then
  begin
    a := U32(FLoca + 4 * AGlyph);
    b := U32(FLoca + 4 * AGlyph + 4);
  end
  else
  begin
    a := Int64(U16(FLoca + 2 * AGlyph)) * 2;
    b := Int64(U16(FLoca + 2 * AGlyph + 2)) * 2;
  end;
  Result := (b > a) and (a >= 0) and (b <= FGlyfLen);
  if Result then
  begin
    AOfs := FGlyf + Integer(a);
    ALen := Integer(b - a);
  end
  else
  begin
    AOfs := 0;
    ALen := 0;
  end;
end;

procedure TRtFont.ReadGlyph(AGlyph, ADepth: Integer; var AOut: TRtGlyphOutline; const AM: array of Double;
  var ABudget: Integer);
const
  ON_CURVE = 1;
  X_SHORT = 2;
  Y_SHORT = 4;
  REPEAT_FLAG = 8;
  X_SAME = 16;
  Y_SAME = 32;
  ARG_WORDS = 1;
  ARGS_XY = 2;
  HAVE_SCALE = 8;
  MORE = 32;
  XY_SCALE = 64;
  TWO_BY_TWO = 128;
  HAVE_INSTR = 256;
  SCALED_OFFSET = $0800;
  UNSCALED_OFFSET = $1000;
var
  ofs, len, contours, p, i, n, base, flags, rep, x, y, d, comp, cf, gi, glyphStart, compStart, pa, pc: Integer;
  matched: Boolean;
  ex, ey: Double;
  endPts: array of Integer;
  fl: array of Byte;
  xs, ys: array of Integer;
  a, b, c, dd, e, f: Double;
  m: array[0..5] of Double;
begin
  if ADepth > 8 then raise ERtFont.Create('font: composite glyphs too deep');
  // (Codex review 169) every glyph visited counted, empty ones too
  Dec(ABudget);
  if ABudget < 0 then raise ERtFont.Create('font: a glyph of too many components');
  if (AGlyph < 0) or (AGlyph >= FNumGlyphs) then Exit;
  if not GlyphRange(AGlyph, ofs, len) then Exit;   // no contours (a space)
  if len < 10 then Exit;
  contours := I16(ofs);
  p := ofs + 10;
  if contours >= 0 then
  begin
    if contours = 0 then Exit;
    SetLength(endPts, contours);
    for i := 0 to contours - 1 do
    begin
      endPts[i] := U16(p);
      Inc(p, 2);
      if (i > 0) and (endPts[i] < endPts[i - 1]) then raise ERtFont.Create('font: bad contour ends');
    end;
    n := endPts[contours - 1] + 1;
    if AOut.Count + n > RTFONT_MAX_POINTS then raise ERtFont.Create('font: a glyph of too many points');
    Inc(p, 2 + U16(p));                      // the instructions skipped
    SetLength(fl, n);
    i := 0;
    while i < n do
    begin
      flags := U8(p);
      Inc(p);
      fl[i] := flags;
      Inc(i);
      if flags and REPEAT_FLAG <> 0 then
      begin
        rep := U8(p);
        Inc(p);
        while (rep > 0) and (i < n) do
        begin
          fl[i] := flags;
          Inc(i);
          Dec(rep);
        end;
      end;
    end;
    SetLength(xs, n);
    SetLength(ys, n);
    x := 0;
    for i := 0 to n - 1 do
    begin
      if fl[i] and X_SHORT <> 0 then
      begin
        d := U8(p);
        Inc(p);
        if fl[i] and X_SAME = 0 then d := -d;
      end
      else if fl[i] and X_SAME <> 0 then d := 0
      else
      begin
        d := I16(p);
        Inc(p, 2);
      end;
      Inc(x, d);
      xs[i] := x;
    end;
    y := 0;
    for i := 0 to n - 1 do
    begin
      if fl[i] and Y_SHORT <> 0 then
      begin
        d := U8(p);
        Inc(p);
        if fl[i] and Y_SAME = 0 then d := -d;
      end
      else if fl[i] and Y_SAME <> 0 then d := 0
      else
      begin
        d := I16(p);
        Inc(p, 2);
      end;
      Inc(y, d);
      ys[i] := y;
    end;
    if p > ofs + len then raise ERtFont.Create('font: a glyph beyond its length');
    base := AOut.Count;
    SetLength(AOut.X, base + n);
    SetLength(AOut.Y, base + n);
    SetLength(AOut.OnCurve, base + n);
    for i := 0 to n - 1 do
    begin
      AOut.X[base + i] := AM[0] * xs[i] + AM[2] * ys[i] + AM[4];
      AOut.Y[base + i] := AM[1] * xs[i] + AM[3] * ys[i] + AM[5];
      AOut.OnCurve[base + i] := fl[i] and ON_CURVE <> 0;
    end;
    i := Length(AOut.EndPts);
    SetLength(AOut.EndPts, i + contours);
    for comp := 0 to contours - 1 do AOut.EndPts[i + comp] := base + endPts[comp];
    AOut.Count := base + n;
  end
  else
  begin
    // composite: each component placed by its own matrix, then this one's
    comp := 0;
    glyphStart := AOut.Count;
    repeat
      Inc(comp);
      if comp > 64 then raise ERtFont.Create('font: too many components');
      cf := U16(p);
      gi := U16(p + 2);
      Inc(p, 4);
      matched := cf and ARGS_XY = 0;
      pa := 0;
      pc := 0;
      if cf and ARG_WORDS <> 0 then
      begin
        if matched then
        begin
          pa := U16(p);                        // a point of this glyph so far, one of the component
          pc := U16(p + 2);
          e := 0;
          f := 0;
        end
        else
        begin
          e := I16(p);
          f := I16(p + 2);
        end;
        Inc(p, 4);
      end
      else
      begin
        if matched then
        begin
          pa := U8(p);
          pc := U8(p + 1);
          e := 0;
          f := 0;
        end
        else
        begin
          e := ShortInt(U8(p));
          f := ShortInt(U8(p + 1));
        end;
        Inc(p, 2);
      end;
      a := 1;
      b := 0;
      c := 0;
      dd := 1;
      if cf and HAVE_SCALE <> 0 then
      begin
        a := I16(p) / 16384;
        dd := a;
        Inc(p, 2);
      end
      else if cf and XY_SCALE <> 0 then
      begin
        a := I16(p) / 16384;
        dd := I16(p + 2) / 16384;
        Inc(p, 4);
      end
      else if cf and TWO_BY_TWO <> 0 then
      begin
        a := I16(p) / 16384;
        b := I16(p + 2) / 16384;
        c := I16(p + 4) / 16384;
        dd := I16(p + 6) / 16384;
        Inc(p, 8);
      end;
      // (Codex review 169) an offset scaled by the component's matrix when
      // the font says so (else, as Microsoft's default, not)
      if (cf and SCALED_OFFSET <> 0) and (cf and UNSCALED_OFFSET = 0) then
      begin
        ex := a * e + c * f;
        ey := b * e + dd * f;
        e := ex;
        f := ey;
      end;
      // the component's matrix, then the parent's
      m[0] := AM[0] * a + AM[2] * b;
      m[1] := AM[1] * a + AM[3] * b;
      m[2] := AM[0] * c + AM[2] * dd;
      m[3] := AM[1] * c + AM[3] * dd;
      m[4] := AM[0] * e + AM[2] * f + AM[4];
      m[5] := AM[1] * e + AM[3] * f + AM[5];
      compStart := AOut.Count;
      ReadGlyph(gi, ADepth + 1, AOut, m, ABudget);
      // (Codex review 169) matched points: the component moved so that its
      // point pc lies on the glyph's point pa
      if matched and (glyphStart + pa < compStart) and (compStart + pc < AOut.Count) then
      begin
        ex := AOut.X[glyphStart + pa] - AOut.X[compStart + pc];
        ey := AOut.Y[glyphStart + pa] - AOut.Y[compStart + pc];
        for i := compStart to AOut.Count - 1 do
        begin
          AOut.X[i] := AOut.X[i] + ex;
          AOut.Y[i] := AOut.Y[i] + ey;
        end;
      end;
      if p > ofs + len then raise ERtFont.Create('font: a glyph beyond its length');
    until cf and MORE = 0;
  end;
end;

function TRtFont.Outline(AGlyph: Integer): TRtGlyphOutline;
var
  o: TRtGlyphOutline;
  budget: Integer;
begin
  if (AGlyph < 0) or (AGlyph >= FNumGlyphs) then AGlyph := 0;
  if not FLoaded[AGlyph] then
  begin
    o := Default(TRtGlyphOutline);
    budget := 4096;
    try
      ReadGlyph(AGlyph, 0, o, [1, 0, 0, 1, 0, 0], budget);
    except
      // a damaged glyph is drawn as nothing, never as an error at each frame
      o := Default(TRtGlyphOutline);
    end;
    FOutlines[AGlyph] := o;
    FLoaded[AGlyph] := True;
  end;
  Result := FOutlines[AGlyph];
end;

procedure RtFlattenGlyph(const AOutline: TRtGlyphOutline; A, B, C, D, E, F, ATolerance: Double;
  var AFlat: TRtFlatGlyph);

  procedure Add(AX, AY: Double);
  begin
    if AFlat.Count >= Length(AFlat.Xs) then
    begin
      SetLength(AFlat.Xs, Max(64, 2 * Length(AFlat.Xs)));
      SetLength(AFlat.Ys, Length(AFlat.Xs));
    end;
    AFlat.Xs[AFlat.Count] := A * AX + C * AY + E;
    AFlat.Ys[AFlat.Count] := B * AX + D * AY + F;
    Inc(AFlat.Count);
  end;

  procedure Quad(X0, Y0, X1, Y1, X2, Y2: Double);
  var
    dx, dy, len: Double;
    n, k: Integer;
    t, u: Double;
  begin
    // segments enough that the curve is within the tolerance (in pixels)
    dx := A * (X0 - 2 * X1 + X2) + C * (Y0 - 2 * Y1 + Y2);
    dy := B * (X0 - 2 * X1 + X2) + D * (Y0 - 2 * Y1 + Y2);
    len := Sqrt(dx * dx + dy * dy);
    n := EnsureRange(Ceil(Sqrt(len / (4 * Max(ATolerance, 0.01)))), 1, 64);
    for k := 1 to n do
    begin
      t := k / n;
      u := 1 - t;
      Add(u * u * X0 + 2 * u * t * X1 + t * t * X2, u * u * Y0 + 2 * u * t * Y1 + t * t * Y2);
    end;
  end;

var
  ci, first, last, i, iFrom, iTo: Integer;
  sx, sy, cx, cy, px, py, qx, qy: Double;
  haveCtl: Boolean;
begin
  first := 0;
  for ci := 0 to High(AOutline.EndPts) do
  begin
    last := AOutline.EndPts[ci];
    if (last < first) or (last >= AOutline.Count) then Break;
    if last - first + 1 < 2 then
    begin
      first := last + 1;
      Continue;
    end;
    if AFlat.Contours >= Length(AFlat.Starts) then SetLength(AFlat.Starts, Max(8, 2 * Length(AFlat.Starts)));
    AFlat.Starts[AFlat.Contours] := AFlat.Count;
    Inc(AFlat.Contours);
    // the start: the first point when on the curve, else the last when it
    // is, else the middle of the two (an implied point)
    iFrom := first;
    iTo := last;
    if AOutline.OnCurve[first] then
    begin
      sx := AOutline.X[first];
      sy := AOutline.Y[first];
      iFrom := first + 1;
    end
    else if AOutline.OnCurve[last] then
    begin
      sx := AOutline.X[last];
      sy := AOutline.Y[last];
      iTo := last - 1;
    end
    else
    begin
      sx := (AOutline.X[first] + AOutline.X[last]) / 2;
      sy := (AOutline.Y[first] + AOutline.Y[last]) / 2;
    end;
    Add(sx, sy);
    px := sx;
    py := sy;
    haveCtl := False;
    cx := 0;
    cy := 0;
    for i := iFrom to iTo do
    begin
      qx := AOutline.X[i];
      qy := AOutline.Y[i];
      if AOutline.OnCurve[i] then
      begin
        if haveCtl then Quad(px, py, cx, cy, qx, qy) else Add(qx, qy);
        haveCtl := False;
        px := qx;
        py := qy;
      end
      else if haveCtl then
      begin
        // two control points: the implied on-curve point between them
        Quad(px, py, cx, cy, (cx + qx) / 2, (cy + qy) / 2);
        px := (cx + qx) / 2;
        py := (cy + qy) / 2;
        cx := qx;
        cy := qy;
      end
      else
      begin
        cx := qx;
        cy := qy;
        haveCtl := True;
      end;
    end;
    // closed back to the start
    if haveCtl then Quad(px, py, cx, cy, sx, sy) else Add(sx, sy);
    first := last + 1;
  end;
end;

end.
