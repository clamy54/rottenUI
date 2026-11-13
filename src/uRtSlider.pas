unit uRtSlider;
{ rottenUI — a slider drawn in the theme's colours: its caption and its
  value on a first line (the value in the accent colour), a rounded track
  filled up to a round thumb, labelled marks under it. Linear or
  logarithmic (a size from 200 to 10 000 pixels reads well on the latter).
  Mouse (click, drag), wheel and keys (arrows, Page Up / Down, Home, End).
  Compact: one line for a toolbar (caption, track, value), marks unlabelled.
  The shapes are drawn four times larger then averaged, for smooth edges on
  every platform; the texts are written at their size, sharp; all of it off
  screen first, then shown at once (no flicker while dragging).
  SPDX-License-Identifier: GPL-3.0-or-later }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType;

type
  TRtSliderFormat = function(Sender: TObject; AValue: Double): string of object;

  TRtSliderMark = record
    Value: Double;
    Text: string;
    Strong: Boolean;          // a reference (the own size, a default): drawn in the accent
  end;

  TRtSlider = class(TCustomControl)
  private
    FMin, FMax, FValue: Double;
    FLogarithmic, FIntegral, FDragging, FCompact: Boolean;
    FSteps: Integer;
    FMarks: array of TRtSliderMark;
    FOnChange: TNotifyEvent;
    FOnFormat: TRtSliderFormat;
    procedure SetValue(AValue: Double);
    procedure SetRange(AMin, AMax: Double);
    function Fraction(AValue: Double): Double;
    function FromFraction(F: Double): Double;
    function TrackRect: TRect;
    function ThumbX: Integer;
    procedure ValueAt(X: Integer);
    procedure StepBy(ASteps: Integer);
    function RowHeight: Integer;
    function ValueText(AValue: Double): string;
    function CaptionWidth: Integer;
    function ValueWidth: Integer;
    procedure SetCompact(AValue: Boolean);
  protected
    procedure Paint; override;
    procedure PaintLabels(cv: TCanvas; const r: TRect; accent, muted: TColor);
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    { The height its three lines take with its font. }
    function PreferredHeight: Integer;
    procedure Configure(AMin, AMax, AValue: Double; ALogarithmic, AIntegral: Boolean);
    procedure ClearMarks;
    procedure AddMark(AValue: Double; const AText: string; AStrong: Boolean = False);
    property Min: Double read FMin;
    property Max: Double read FMax;
    property Value: Double read FValue write SetValue;
    property Logarithmic: Boolean read FLogarithmic;
    { Keyboard and wheel steps over the whole range. }
    property Steps: Integer read FSteps write FSteps;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    { The value as the first line shows it (else the number). }
    property OnFormat: TRtSliderFormat read FOnFormat write FOnFormat;
    { One line, for a toolbar. }
    property Compact: Boolean read FCompact write SetCompact;
    property Caption;
    property Font;
    property TabStop;
  end;

implementation

uses
  IntfGraphics, GraphType, FPImage, uTheme;

const
  SS = 4;             // supersampling of the shapes
  TRACK_H = 6;
  THUMB_R = 9;
  PAD_X = 12;         // room for the thumb at both ends
  MIN_TRACK = 40;     // a compact track shorter than this drops its texts

constructor TRtSlider.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  DoubleBuffered := True;
  FMin := 0;
  FMax := 100;
  FValue := 0;
  FSteps := 100;
  Width := 360;
  Height := 64;
end;

procedure TRtSlider.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  inherited SetBounds(ALeft, ATop, AWidth, AHeight);
  Invalidate;
end;

function TRtSlider.RowHeight: Integer;
begin
  Canvas.Font.Assign(Font);
  Result := Canvas.TextHeight('Ag') + 2;
end;

function TRtSlider.PreferredHeight: Integer;
begin
  if FCompact then Result := Math.Max(RowHeight, THUMB_R * 2 + 8)
  else Result := RowHeight * 2 + THUMB_R * 2 + 10;
end;

procedure TRtSlider.SetCompact(AValue: Boolean);
begin
  if AValue = FCompact then Exit;
  FCompact := AValue;
  Invalidate;
end;

function TRtSlider.ValueText(AValue: Double): string;
begin
  if Assigned(FOnFormat) then Result := FOnFormat(Self, AValue)
  else if FIntegral then Result := IntToStr(Round(AValue))
  else Result := FormatFloat('0.##', AValue);
end;

function TRtSlider.CaptionWidth: Integer;
begin
  Canvas.Font.Assign(Font);
  if Caption = '' then Result := 0 else Result := Canvas.TextWidth(Caption) + 10;
end;

{ Room for the widest value (its bounds), so that the track never moves. }
function TRtSlider.ValueWidth: Integer;
begin
  Canvas.Font.Assign(Font);
  Canvas.Font.Style := [fsBold];
  Result := Math.Max(Canvas.TextWidth(ValueText(FMin)), Canvas.TextWidth(ValueText(FMax))) + 10;
end;

procedure TRtSlider.Configure(AMin, AMax, AValue: Double; ALogarithmic, AIntegral: Boolean);
var
  i, n: Integer;
begin
  FLogarithmic := ALogarithmic and (AMin > 0);
  SetRange(AMin, AMax);
  // (Codex review 91) Whole values only when the range holds one.
  FIntegral := AIntegral and (Ceil(FMin) <= Floor(FMax));
  // Marks of an earlier range that this one does not hold: dropped.
  n := 0;
  for i := 0 to High(FMarks) do
    if (FMarks[i].Value >= FMin) and (FMarks[i].Value <= FMax) then
    begin
      FMarks[n] := FMarks[i];
      Inc(n);
    end;
  SetLength(FMarks, n);
  FValue := FMin;
  SetValue(AValue);
  Invalidate;
end;

procedure TRtSlider.SetRange(AMin, AMax: Double);
begin
  if IsNan(AMin) or IsNan(AMax) then Exit;
  if AMax < AMin then AMax := AMin;
  FMin := AMin;
  FMax := AMax;
end;

procedure TRtSlider.ClearMarks;
begin
  FMarks := nil;
  Invalidate;
end;

procedure TRtSlider.AddMark(AValue: Double; const AText: string; AStrong: Boolean);
begin
  if (AValue < FMin) or (AValue > FMax) then Exit;
  SetLength(FMarks, Length(FMarks) + 1);
  FMarks[High(FMarks)].Value := AValue;
  FMarks[High(FMarks)].Text := AText;
  FMarks[High(FMarks)].Strong := AStrong;
  Invalidate;
end;

procedure TRtSlider.SetValue(AValue: Double);
begin
  if IsNan(AValue) then Exit;
  AValue := EnsureRange(AValue, FMin, FMax);
  if FIntegral then AValue := EnsureRange(Round(AValue), Ceil(FMin), Floor(FMax));
  if AValue = FValue then Exit;
  FValue := AValue;
  // Shown at once, before whoever follows it does its (maybe long) work.
  Invalidate;
  if HandleAllocated and IsVisible then Update;
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TRtSlider.Fraction(AValue: Double): Double;
begin
  if FMax <= FMin then Exit(0);
  AValue := EnsureRange(AValue, FMin, FMax);
  if FLogarithmic then
    Result := Ln(AValue / FMin) / Ln(FMax / FMin)
  else
    Result := (AValue - FMin) / (FMax - FMin);
  Result := EnsureRange(Result, 0, 1);
end;

function TRtSlider.FromFraction(F: Double): Double;
begin
  F := EnsureRange(F, 0, 1);
  if FLogarithmic then
    Result := FMin * Exp(F * Ln(FMax / FMin))
  else
    Result := FMin + F * (FMax - FMin);
end;

function TRtSlider.TrackRect: TRect;
var
  cy: Integer;
begin
  if FCompact then
  begin
    // (Codex review 94) Too narrow for all: the caption goes, then the
    // value; the track always stays within the control.
    cy := ClientHeight div 2;
    Result := Rect(PAD_X + CaptionWidth, cy - TRACK_H div 2, ClientWidth - PAD_X - ValueWidth,
      cy - TRACK_H div 2 + TRACK_H);
    if Result.Right < Result.Left + MIN_TRACK then Result.Left := PAD_X;
    if Result.Right < Result.Left + MIN_TRACK then Result.Right := ClientWidth - PAD_X;
    if Result.Right < Result.Left then Result.Right := Result.Left;
    Exit;
  end;
  cy := RowHeight + THUMB_R + 4;
  Result := Rect(PAD_X, cy - TRACK_H div 2, ClientWidth - PAD_X, cy - TRACK_H div 2 + TRACK_H);
end;

function TRtSlider.ThumbX: Integer;
var
  r: TRect;
begin
  r := TrackRect;
  Result := r.Left + Round((r.Right - r.Left) * Fraction(FValue));
end;

procedure TRtSlider.ValueAt(X: Integer);
var
  r: TRect;
begin
  r := TrackRect;
  if r.Right <= r.Left then Exit;
  SetValue(FromFraction((X - r.Left) / (r.Right - r.Left)));
end;

procedure TRtSlider.StepBy(ASteps: Integer);
var
  f, v: Double;
begin
  f := Fraction(FValue) + ASteps / Math.Max(1, FSteps);
  v := FromFraction(f);
  // A whole value always moves at least by one.
  if FIntegral and (Round(v) = Round(FValue)) and (ASteps <> 0) then v := FValue + Sign(ASteps);
  SetValue(v);
end;

procedure TRtSlider.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if CanFocus then SetFocus;
  FDragging := True;
  ValueAt(X);
end;

procedure TRtSlider.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then ValueAt(X);
end;

procedure TRtSlider.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TRtSlider.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then StepBy(1) else StepBy(-1);
end;

procedure TRtSlider.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_LEFT, VK_DOWN: StepBy(-1);
    VK_RIGHT, VK_UP: StepBy(1);
    VK_PRIOR: StepBy(10);
    VK_NEXT: StepBy(-10);
    VK_HOME: SetValue(FMin);
    VK_END: SetValue(FMax);
  else
    begin
      inherited KeyDown(Key, Shift);
      Exit;
    end;
  end;
  Key := 0;
end;

procedure TRtSlider.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TRtSlider.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

{ The big bitmap averaged by SS x SS blocks into the small one. }
procedure Shrink(ABig, ASmall: TBitmap);
var
  src, dst: TLazIntfImage;
  desc: TRawImageDescription;
  x, y, i, j, w, h: Integer;
  r, g, b: Cardinal;
  c: TFPColor;
begin
  w := ASmall.Width;
  h := ASmall.Height;
  src := ABig.CreateIntfImage;
  dst := TLazIntfImage.Create(0, 0);
  try
    desc.Init_BPP24_B8G8R8_BIO_TTB(w, h);
    dst.DataDescription := desc;
    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
      begin
        r := 0; g := 0; b := 0;
        for j := 0 to SS - 1 do
          for i := 0 to SS - 1 do
          begin
            c := src.Colors[x * SS + i, y * SS + j];
            Inc(r, c.Red shr 8);
            Inc(g, c.Green shr 8);
            Inc(b, c.Blue shr 8);
          end;
        c.Red := (r div (SS * SS)) * 257;
        c.Green := (g div (SS * SS)) * 257;
        c.Blue := (b div (SS * SS)) * 257;
        c.Alpha := $FFFF;
        dst.Colors[x, y] := c;
      end;
    ASmall.LoadFromIntfImage(dst);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TRtSlider.Paint;
var
  big, small: TBitmap;
  r: TRect;
  tx, cy, i, mx: Integer;
  muted, track, accent: TColor;
  shown: string;
  cv: TCanvas;
begin
  r := TrackRect;
  tx := ThumbX;
  cy := (r.Top + r.Bottom) div 2;
  accent := clAccent;
  muted := BlendColor(clAppFg, clAppBg, 55);
  track := BlendColor(clAppFg, clAppBg, 18);
  // The shapes, four times larger, then averaged.
  big := TBitmap.Create;
  small := TBitmap.Create;
  try
    big.SetSize(Math.Max(1, ClientWidth * SS), Math.Max(1, ClientHeight * SS));
    small.SetSize(Math.Max(1, ClientWidth), Math.Max(1, ClientHeight));
    with big.Canvas do
    begin
      Brush.Style := bsSolid;
      Brush.Color := clAppBg;
      FillRect(Rect(0, 0, big.Width, big.Height));
      Pen.Style := psClear;
      // The track, then its part up to the thumb.
      Brush.Color := track;
      RoundRect(r.Left * SS, r.Top * SS, r.Right * SS, r.Bottom * SS, TRACK_H * SS, TRACK_H * SS);
      Brush.Color := accent;
      if tx > r.Left then
        RoundRect(r.Left * SS, r.Top * SS, tx * SS + TRACK_H * SS div 2, r.Bottom * SS, TRACK_H * SS, TRACK_H * SS);
      // The marks' ticks (under the track; none when compact).
      if not FCompact then
      for i := 0 to High(FMarks) do
      begin
        mx := r.Left + Round((r.Right - r.Left) * Fraction(FMarks[i].Value));
        if FMarks[i].Strong then Brush.Color := accent else Brush.Color := muted;
        FillRect(Rect((mx * SS) - SS, (r.Bottom + 5) * SS, (mx * SS) + SS, (r.Bottom + 9) * SS));
      end;
      // The thumb: a halo when focused, a ring in the accent.
      if Focused then
      begin
        Brush.Color := BlendColor(accent, clAppBg, 30);
        Ellipse((tx - THUMB_R - 4) * SS, (cy - THUMB_R - 4) * SS, (tx + THUMB_R + 4) * SS, (cy + THUMB_R + 4) * SS);
      end;
      Brush.Color := accent;
      Ellipse((tx - THUMB_R) * SS, (cy - THUMB_R) * SS, (tx + THUMB_R) * SS, (cy + THUMB_R) * SS);
      Brush.Color := clAppBg;
      Ellipse((tx - THUMB_R + 3) * SS, (cy - THUMB_R + 3) * SS, (tx + THUMB_R - 3) * SS, (cy + THUMB_R - 3) * SS);
    end;
    Shrink(big, small);
    // The texts, sharp, on the same bitmap: caption and value, then the
    // marks' labels (none when compact).
    cv := small.Canvas;
    cv.Font.Assign(Font);
    cv.Brush.Style := bsClear;
    cv.Font.Color := clAppFg;
    shown := ValueText(FValue);
    if FCompact then
    begin
      // The texts the layout kept room for.
      if r.Left > PAD_X then
        cv.TextOut(PAD_X - 4, (ClientHeight - cv.TextHeight('Ag')) div 2, Caption);
      cv.Font.Style := [fsBold];
      cv.Font.Color := accent;
      if r.Right < ClientWidth - PAD_X then
        cv.TextOut(ClientWidth - PAD_X + 4 - cv.TextWidth(shown), (ClientHeight - cv.TextHeight('Ag')) div 2, shown);
    end
    else
    begin
      cv.TextOut(PAD_X - 4, 0, Caption);
      cv.Font.Style := [fsBold];
      cv.Font.Color := accent;
      cv.TextOut(ClientWidth - PAD_X + 4 - cv.TextWidth(shown), 0, shown);
      cv.Font.Style := [];
      cv.Font.Height := -Math.Max(8, Round(Abs(Font.Height) * 0.85));
      if Font.Height = 0 then cv.Font.Size := Math.Max(7, Round(Font.Size * 0.85));
      PaintLabels(cv, r, accent, muted);
    end;
    Canvas.Draw(0, 0, small);
  finally
    small.Free;
    big.Free;
  end;
end;

procedure TRtSlider.PaintLabels(cv: TCanvas; const r: TRect; accent, muted: TColor);
var
  i, j, mx, tw, lx, pass: Integer;
  spans: array of TPoint;            // X..Y: the labels written
  clash: Boolean;
begin
  // Labels: the strong ones first, then the others where they fit.
  SetLength(spans, 0);
  for pass := 0 to 1 do
    for i := 0 to High(FMarks) do
    begin
      if FMarks[i].Strong <> (pass = 0) then Continue;
      mx := r.Left + Round((r.Right - r.Left) * Fraction(FMarks[i].Value));
      tw := cv.TextWidth(FMarks[i].Text);
      lx := EnsureRange(mx - tw div 2, 0, Math.Max(0, ClientWidth - tw));
      clash := False;
      for j := 0 to High(spans) do
        if (lx < spans[j].Y + 8) and (lx + tw + 8 > spans[j].X) then clash := True;
      if clash then Continue;
      if FMarks[i].Strong then cv.Font.Color := accent else cv.Font.Color := muted;
      cv.TextOut(lx, r.Bottom + 10, FMarks[i].Text);
      SetLength(spans, Length(spans) + 1);
      spans[High(spans)] := Point(lx, lx + tw);
    end;
end;

end.
