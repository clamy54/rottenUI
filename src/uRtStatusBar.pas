// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtStatusBar;

{$mode objfpc}{$H+}

// Barre de statut dessinee. Sous Windows, macOS et GTK3, la native n'accepte les couleurs
// du theme que si l'on dessine ses panneaux a sa place: autant tout dessiner, une fois.

interface

uses
  Classes, SysUtils, Controls, Graphics;

type
  TRtPanelColorEvent = procedure(Sender: TObject; AIndex: Integer; var AColor: TColor) of object;

  TRtStatusBar = class(TCustomControl)
  private
    FTexts: array of string;
    FWidths: array of Integer;
    FAligns: array of TAlignment;
    FOnGetPanelColor: TRtPanelColorEvent;
    function GetPanelCount: Integer;
    function GetPanelText(AIndex: Integer): string;
    procedure SetPanelText(AIndex: Integer; const AValue: string);
    function GetPanelWidth(AIndex: Integer): Integer;
    procedure SetPanelWidth(AIndex: Integer; AValue: Integer);
  protected
    procedure Paint; override;
    procedure DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
      const AXProportion, AYProportion: Double); override;
  public
    constructor Create(AOwner: TComponent); override;
    // AWidth <= 0: le panneau prend la place restante, partagee s'ils sont plusieurs
    function AddPanel(AWidth: Integer; AAlignment: TAlignment = taLeftJustify): Integer;
    procedure ClearPanels;
    function PanelRect(AIndex: Integer): TRect;
    function PanelAt(X: Integer): Integer;
    procedure RefreshTheme;
    property PanelCount: Integer read GetPanelCount;
    property PanelText[AIndex: Integer]: string read GetPanelText write SetPanelText;
    property PanelWidth[AIndex: Integer]: Integer read GetPanelWidth write SetPanelWidth;
    // couleur du texte d'un panneau, demandee a chaque dessin: clStatusText par defaut
    property OnGetPanelColor: TRtPanelColorEvent read FOnGetPanelColor write FOnGetPanelColor;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property PopupMenu;
  end;

implementation

uses
  uTheme;

const
  PAD_X = 4;
  PAD_Y = 1;

constructor TRtStatusBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csAcceptsControls];
  DoubleBuffered := True;
  Align := alBottom;
  RefreshTheme;
end;

procedure TRtStatusBar.RefreshTheme;
var
  bmp: TBitmap;
  h: Integer;
begin
  if RSUiFontName <> '' then Font.Name := RSUiFontName;
  if RSUiFontSize > 0 then Font.Size := RSUiFontSize;
  bmp := TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(Font);
    h := bmp.Canvas.TextHeight('Ag') + 2 * PAD_Y;
  finally
    bmp.Free;
  end;
  // Hauteur tenue par la police et verrouillee: un separateur voisin ne l'etire pas.
  Constraints.MaxHeight := 0;
  Constraints.MinHeight := h;
  Constraints.MaxHeight := h;
  Height := h;
  Invalidate;
end;

function TRtStatusBar.GetPanelCount: Integer;
begin
  Result := Length(FTexts);
end;

function TRtStatusBar.AddPanel(AWidth: Integer; AAlignment: TAlignment): Integer;
begin
  Result := Length(FTexts);
  SetLength(FTexts, Result + 1);
  SetLength(FWidths, Result + 1);
  SetLength(FAligns, Result + 1);
  FWidths[Result] := AWidth;
  FAligns[Result] := AAlignment;
  Invalidate;
end;

procedure TRtStatusBar.ClearPanels;
begin
  FTexts := nil;
  FWidths := nil;
  FAligns := nil;
  Invalidate;
end;

function TRtStatusBar.GetPanelText(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < Length(FTexts)) then
    Result := FTexts[AIndex]
  else
    Result := '';
end;

procedure TRtStatusBar.SetPanelText(AIndex: Integer; const AValue: string);
begin
  if (AIndex < 0) or (AIndex >= Length(FTexts)) or (FTexts[AIndex] = AValue) then Exit;
  FTexts[AIndex] := AValue;
  Invalidate;
end;

function TRtStatusBar.GetPanelWidth(AIndex: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex < Length(FWidths)) then
    Result := FWidths[AIndex]
  else
    Result := 0;
end;

procedure TRtStatusBar.SetPanelWidth(AIndex: Integer; AValue: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FWidths)) or (FWidths[AIndex] = AValue) then Exit;
  FWidths[AIndex] := AValue;
  Invalidate;
end;

function TRtStatusBar.PanelRect(AIndex: Integer): TRect;
var
  i, x, w, spare, fills: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if (AIndex < 0) or (AIndex >= Length(FWidths)) then Exit;
  spare := ClientWidth;
  fills := 0;
  for i := 0 to High(FWidths) do
    if FWidths[i] > 0 then Dec(spare, FWidths[i]) else Inc(fills);
  if spare < 0 then spare := 0;
  x := 0;
  w := 0;
  for i := 0 to AIndex do
  begin
    if FWidths[i] > 0 then
      w := FWidths[i]
    else
    begin
      // le dernier ramasse les pixels que la division a laisses
      w := spare div fills;
      Dec(spare, w);
      Dec(fills);
    end;
    if i < AIndex then Inc(x, w);
  end;
  Result := Rect(x, 0, x + w, ClientHeight);
end;

function TRtStatusBar.PanelAt(X: Integer): Integer;
var
  i: Integer;
  r: TRect;
begin
  for i := 0 to High(FWidths) do
  begin
    r := PanelRect(i);
    if (X >= r.Left) and (X < r.Right) then Exit(i);
  end;
  Result := -1;
end;

procedure TRtStatusBar.DoAutoAdjustLayout(const AMode: TLayoutAdjustmentPolicy;
  const AXProportion, AYProportion: Double);
var
  i: Integer;
begin
  inherited DoAutoAdjustLayout(AMode, AXProportion, AYProportion);
  if AMode in [lapAutoAdjustWithoutHorizontalScrolling, lapAutoAdjustForDPI] then
    for i := 0 to High(FWidths) do
      if FWidths[i] > 0 then
        FWidths[i] := Round(FWidths[i] * AXProportion);
end;

procedure TRtStatusBar.Paint;
var
  i, x, ty, tw: Integer;
  r: TRect;
  c: TColor;
begin
  Canvas.Brush.Color := clStatusBg;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  ty := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  for i := 0 to High(FTexts) do
  begin
    if FTexts[i] = '' then Continue;
    r := PanelRect(i);
    if r.Right <= r.Left then Continue;
    c := clStatusText;
    if Assigned(FOnGetPanelColor) then FOnGetPanelColor(Self, i, c);
    Canvas.Font.Color := c;
    x := r.Left + PAD_X;
    if FAligns[i] <> taLeftJustify then
    begin
      tw := Canvas.TextWidth(FTexts[i]);
      // un texte trop long reste cale a gauche: c'est son debut qu'on veut lire
      if tw < r.Right - r.Left - 2 * PAD_X then
        if FAligns[i] = taRightJustify then
          x := r.Right - PAD_X - tw
        else
          x := (r.Left + r.Right - tw) div 2;
    end;
    Canvas.TextRect(r, x, ty, FTexts[i]);
  end;
end;

end.
