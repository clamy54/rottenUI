// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtRasterLcl;

{$mode objfpc}{$H+}

{ uRtRaster with the LCL: a raster shown on a canvas in one copy of its
  pixels (32 bits, B G R as in memory, nothing converted, nothing scaled),
  written as PNG (FPC's own encoder), the LCL's colours and images as the
  raster takes them. }

interface

uses
  Classes, SysUtils, Graphics, uRtRaster;

{ An LCL colour (system and theme colours resolved) with its alpha. }
function RtColor(AColor: TColor; AAlpha: Byte = 255): TRtColor;
{ ARaster drawn at (AX, AY) of ACanvas; ABitmap kept between calls (freed
  by the caller). }
procedure RtRasterDraw(ARaster: TRtRaster; ACanvas: TCanvas; AX, AY: Integer; var ABitmap: TBitmap);
procedure RtRasterSavePng(ARaster: TRtRaster; AStream: TStream);
{ A graphic's pixels, straight $AARRGGBB (its alpha kept), as decoded by
  the LCL's own readers (PNG, JPEG, BMP: FPC's code, the same everywhere). }
function RtGraphicPixels(AGraphic: TGraphic; out AWidth, AHeight: Integer): TRtPixels;

implementation

uses
  Math, IntfGraphics, GraphType, FPImage, FPWritePNG, LCLType, LCLIntf;

function RtColor(AColor: TColor; AAlpha: Byte): TRtColor;
var
  c: LongInt;
begin
  c := ColorToRGB(AColor);
  // TColor is $00BBGGRR
  Result := LongWord(AAlpha) shl 24 or LongWord(c and $FF) shl 16 or LongWord(c and $FF00) or
    LongWord((c shr 16) and $FF);
end;

procedure RtRasterDraw(ARaster: TRtRaster; ACanvas: TCanvas; AX, AY: Integer; var ABitmap: TBitmap);
var
  img: TLazIntfImage;
  desc: TRawImageDescription;
  y: Integer;
begin
  if (ARaster = nil) or (ARaster.Width <= 0) or (ARaster.Height <= 0) then Exit;
  img := TLazIntfImage.Create(0, 0);
  try
    desc.Init_BPP32_B8G8R8_BIO_TTB(ARaster.Width, ARaster.Height);
    img.DataDescription := desc;
    for y := 0 to ARaster.Height - 1 do
      Move(ARaster.Pixels[y * ARaster.Width], img.GetDataLineStart(y)^, ARaster.Width * SizeOf(LongWord));
    if ABitmap = nil then ABitmap := TBitmap.Create;
    ABitmap.LoadFromIntfImage(img);
  finally
    img.Free;
  end;
  ACanvas.Draw(AX, AY, ABitmap);
end;

procedure RtRasterSavePng(ARaster: TRtRaster; AStream: TStream);
var
  img: TFPMemoryImage;
  w: TFPWriterPNG;
  x, y: Integer;
  p: LongWord;
  c: TFPColor;
begin
  img := TFPMemoryImage.Create(Max(1, ARaster.Width), Max(1, ARaster.Height));
  w := TFPWriterPNG.Create;
  try
    for y := 0 to ARaster.Height - 1 do
      for x := 0 to ARaster.Width - 1 do
      begin
        p := ARaster.Pixels[y * ARaster.Width + x];
        c.Red := ((p shr 16) and $FF) * 257;
        c.Green := ((p shr 8) and $FF) * 257;
        c.Blue := (p and $FF) * 257;
        c.Alpha := $FFFF;
        img.Colors[x, y] := c;
      end;
    w.UseAlpha := False;
    img.SaveToStream(AStream, w);
  finally
    w.Free;
    img.Free;
  end;
end;

function RtGraphicPixels(AGraphic: TGraphic; out AWidth, AHeight: Integer): TRtPixels;
var
  img: TLazIntfImage;
  bmp: TBitmap;
  x, y: Integer;
  c: TFPColor;
begin
  Result := nil;
  AWidth := 0;
  AHeight := 0;
  if (AGraphic = nil) or AGraphic.Empty then Exit;
  bmp := nil;
  if AGraphic is TRasterImage then
    img := TRasterImage(AGraphic).CreateIntfImage
  else
  begin
    bmp := TBitmap.Create;
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(AGraphic.Width, AGraphic.Height);
    bmp.Canvas.Draw(0, 0, AGraphic);
    img := bmp.CreateIntfImage;
  end;
  try
    AWidth := img.Width;
    AHeight := img.Height;
    SetLength(Result, AWidth * AHeight);
    for y := 0 to AHeight - 1 do
      for x := 0 to AWidth - 1 do
      begin
        c := img.Colors[x, y];
        Result[y * AWidth + x] := LongWord(c.Alpha shr 8) shl 24 or LongWord(c.Red shr 8) shl 16 or
          LongWord(c.Green shr 8) shl 8 or LongWord(c.Blue shr 8);
      end;
  finally
    img.Free;
    bmp.Free;
  end;
end;

end.
