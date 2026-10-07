// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtGauge;

{$mode objfpc}{$H+}

// Jauge dessinee, commune aux deux familles de controles: elle ne depend que du theme.
// Mode indetermine pour les travaux dont personne ne connait la fin, serveur compris.

interface

uses
  Classes, SysUtils, Controls, Graphics, ExtCtrls;

type
  TRtGauge = class(TGraphicControl)
  private
    FPosition, FMax: Integer;
    FIndeterminate: Boolean;
    FTimer: TTimer;
    FStart: QWord;
    procedure SetPosition(AValue: Integer);
    procedure SetMax(AValue: Integer);
    procedure SetIndeterminate(AValue: Boolean);
    procedure Tick(Sender: TObject);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    // bloc mobile du mode indetermine, AElapsedMs apres son depart
    function SweepRect(AElapsedMs: QWord): TRect;
    property Position: Integer read FPosition write SetPosition;
    property Max: Integer read FMax write SetMax;
    property Indeterminate: Boolean read FIndeterminate write SetIndeterminate;
  end;

implementation

uses
  uTheme;

const
  SWEEP_MS = 1400;
  SWEEP_TICK_MS = 40;

constructor TRtGauge.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // elle peint tout son rectangle: pas d'effacement du parent a chaque pas du mode indetermine
  ControlStyle := ControlStyle + [csOpaque];
  FMax := 100;
  Height := 12;
  Width := 200;
end;

procedure TRtGauge.SetPosition(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue > FMax then AValue := FMax;
  if AValue = FPosition then Exit;
  FPosition := AValue;
  Invalidate;
end;

procedure TRtGauge.SetMax(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  if AValue = FMax then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TRtGauge.SetIndeterminate(AValue: Boolean);
begin
  if AValue = FIndeterminate then Exit;
  FIndeterminate := AValue;
  if AValue then
  begin
    if FTimer = nil then
    begin
      FTimer := TTimer.Create(Self);
      FTimer.Interval := SWEEP_TICK_MS;
      FTimer.OnTimer := @Tick;
    end;
    FStart := GetTickCount64;
  end;
  if FTimer <> nil then FTimer.Enabled := AValue;
  Invalidate;
end;

procedure TRtGauge.Tick(Sender: TObject);
begin
  if IsVisible then Invalidate;
end;

function TRtGauge.SweepRect(AElapsedMs: QWord): TRect;
var
  w, bw, x: Integer;
begin
  Result := ClientRect;
  w := Result.Right - Result.Left;
  bw := w div 4;
  if bw < 8 then bw := 8;
  // le bloc entre par la gauche et sort par la droite, en entier
  x := Result.Left - bw + Integer(Int64(w + bw) * Int64(AElapsedMs mod SWEEP_MS) div SWEEP_MS);
  if x > Result.Left then Result.Left := x;
  if x + bw < Result.Right then Result.Right := x + bw;
  if Result.Right < Result.Left then Result.Right := Result.Left;
end;

procedure TRtGauge.Paint;
var
  r: TRect;
begin
  r := ClientRect;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clProgressTrack;
  Canvas.FillRect(r);
  Canvas.Brush.Color := clProgressBar;
  if FIndeterminate then
    Canvas.FillRect(SweepRect(GetTickCount64 - FStart))
  else if (FMax > 0) and (FPosition > 0) then
  begin
    r.Right := r.Left + Integer(Int64(r.Right - r.Left) * FPosition div FMax);
    Canvas.FillRect(r);
  end;
  Canvas.Pen.Style := psSolid;
end;

end.
