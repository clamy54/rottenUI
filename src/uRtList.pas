// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtList;

{$mode objfpc}{$H+}

// Liste en colonnes de la coque, dessinee aux couleurs du theme (l'en-tete du
// TListView natif de Windows reste clair). Deux modes: virtuel (OnGetCell,
// adapte aux dizaines de milliers de resultats) ou valeurs stockees. Avec
// FillWidth, les colonnes occupent toute la largeur en gardant leurs
// proportions (celles qu'impose l'utilisateur en les redimensionnant).

interface

uses
  Classes, SysUtils, Controls, Grids, Graphics, LCLType;

type
  TRtGetCellEvent = function(Sender: TObject; AIndex, ACol: Integer): string of object;
  TRtSelectEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  // icone Tabler devant le texte d'une cellule ('' = aucune) et sa couleur
  TRtGetCellIconEvent = function(Sender: TObject; AIndex, ACol: Integer;
    out AColor: TColor): string of object;

  TRtListGrid = class(TDrawGrid)
  private
    FCaptions: TStringList;
    FRows: TList;                 // TStringList par ligne (mode stocke)
    FCount: Integer;
    FOnGetCell: TRtGetCellEvent;
    FOnSelectRow: TRtSelectEvent;
    FLastSelected: Integer;
    FWeights: array of Integer;   // largeurs relatives des colonnes (FillWidth)
    FFillWidth: Boolean;
    FFitting: Boolean;
    FOnActivateRow: TRtSelectEvent;
    FOnGetCellIcon: TRtGetCellIconEvent;
    procedure SetCount(AValue: Integer);
    procedure SetFillWidth(AValue: Boolean);
    procedure FitColumns;
    function GetItemIndex: Integer;
    procedure SetItemIndex(AValue: Integer);
    procedure ClearRows;
  protected
    procedure DrawCell(ACol, ARow: Longint; ARect: TRect; AState: TGridDrawState); override;
    procedure SelectionChanged; virtual;
    procedure AfterMoveSelection(const aPrevCol, aPrevRow: Integer); override;
    procedure DoOnResize; override;
    procedure HeaderSized(IsColumn: Boolean; Index: Integer); override;
    procedure DblClick; override;
    procedure Click; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ClearColumns;
    procedure AddColumn(const ACaption: string; AWidth: Integer);
    // mode stocke
    procedure Clear;
    function AddRow(const AValues: array of string): Integer;
    function CellText(AIndex, ACol: Integer): string;
    procedure RefreshMetrics;
    // nombre de lignes de donnees (mode virtuel ou stocke)
    property Count: Integer read FCount write SetCount;
    property ItemIndex: Integer read GetItemIndex write SetItemIndex;
    property OnGetCell: TRtGetCellEvent read FOnGetCell write FOnGetCell;
    property OnSelectRow: TRtSelectEvent read FOnSelectRow write FOnSelectRow;
    // double clic ou Entree sur une ligne de donnees
    property OnActivateRow: TRtSelectEvent read FOnActivateRow write FOnActivateRow;
    property FillWidth: Boolean read FFillWidth write SetFillWidth;
    property OnGetCellIcon: TRtGetCellIconEvent read FOnGetCellIcon write FOnGetCellIcon;
    // icone d'une cellule de donnees ('' sans OnGetCellIcon)
    function CellIcon(AIndex, ACol: Integer; out AColor: TColor): string;
  end;

implementation

uses
  Forms, uTheme, uIcons;

const
  // icone de cellule (taille logique)
  CELL_ICON = 16;

function TRtListGrid.CellIcon(AIndex, ACol: Integer; out AColor: TColor): string;
begin
  AColor := clNone;
  Result := '';
  if Assigned(FOnGetCellIcon) and (AIndex >= 0) and (AIndex < FCount) then
    Result := FOnGetCellIcon(Self, AIndex, ACol, AColor);
end;

constructor TRtListGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCaptions := TStringList.Create;
  FRows := TList.Create;
  FLastSelected := -1;
  FixedCols := 0;
  ColCount := 1;
  RowCount := 1;
  FixedRows := 1;
  BorderStyle := bsNone;
  Options := [goRowSelect, goColSizing, goThumbTracking, goSmoothScroll];
  Flat := True;
  DefaultDrawing := False;
  FocusRectVisible := False;
  AutoFillColumns := False;
  ExtendedSelect := False;
end;

destructor TRtListGrid.Destroy;
begin
  ClearRows;
  FRows.Free;
  FCaptions.Free;
  inherited Destroy;
end;

procedure TRtListGrid.ClearRows;
var
  i: Integer;
begin
  for i := 0 to FRows.Count - 1 do
    TStringList(FRows[i]).Free;
  FRows.Clear;
end;

procedure TRtListGrid.ClearColumns;
begin
  FCaptions.Clear;
  FWeights := nil;
  ColCount := 1;
  ColWidths[0] := 100;
end;

procedure TRtListGrid.AddColumn(const ACaption: string; AWidth: Integer);
begin
  FCaptions.Add(ACaption);
  SetLength(FWeights, FCaptions.Count);
  FWeights[High(FWeights)] := AWidth;
  ColCount := FCaptions.Count;
  ColWidths[FCaptions.Count - 1] := AWidth;
  FitColumns;
  Invalidate;
end;

procedure TRtListGrid.SetFillWidth(AValue: Boolean);
begin
  FFillWidth := AValue;
  FitColumns;
end;

procedure TRtListGrid.FitColumns;
var
  i, total, avail, used, w: Integer;
begin
  if not FFillWidth or FFitting or (Length(FWeights) = 0) or (Length(FWeights) <> ColCount) then Exit;
  avail := ClientWidth - 2;
  if avail <= 0 then Exit;
  total := 0;
  for i := 0 to High(FWeights) do
    Inc(total, FWeights[i]);
  if total <= 0 then Exit;
  FFitting := True;
  try
    used := 0;
    for i := 0 to High(FWeights) do
    begin
      // la derniere colonne prend le reste: aucun vide ni debordement
      if i = High(FWeights) then
        w := avail - used
      else
        w := (avail * FWeights[i]) div total;
      if w < 40 then w := 40;
      ColWidths[i] := w;
      Inc(used, w);
    end;
  finally
    FFitting := False;
  end;
end;

procedure TRtListGrid.DoOnResize;
begin
  inherited DoOnResize;
  FitColumns;
end;

procedure TRtListGrid.HeaderSized(IsColumn: Boolean; Index: Integer);
var
  i: Integer;
begin
  inherited HeaderSized(IsColumn, Index);
  if not IsColumn or not FFillWidth or (Length(FWeights) <> ColCount) then Exit;
  // les proportions choisies a la souris deviennent la nouvelle repartition
  for i := 0 to High(FWeights) do
    FWeights[i] := ColWidths[i];
  FitColumns;
end;

procedure TRtListGrid.DblClick;
var
  pt: TPoint;
  c, r: Integer;
begin
  inherited DblClick;
  pt := ScreenToClient(Mouse.CursorPos);
  MouseToCell(pt.X, pt.Y, c, r);
  if (r >= 1) and (r - 1 < FCount) and Assigned(FOnActivateRow) then
    FOnActivateRow(Self, r - 1);
end;

// Clic sur la ligne deja courante (celle surlignee apres un remplissage):
// aucun deplacement, donc pas d'AfterMoveSelection; la selection est
// quand meme signalee si elle n'a pas encore ete vue
procedure TRtListGrid.Click;
begin
  inherited Click;
  SelectionChanged;
end;

procedure TRtListGrid.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) and (ItemIndex >= 0) and Assigned(FOnActivateRow) then
  begin
    FOnActivateRow(Self, ItemIndex);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TRtListGrid.RefreshMetrics;
var
  bmp: Graphics.TBitmap;
begin
  bmp := Graphics.TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(Font);
    DefaultRowHeight := bmp.Canvas.TextHeight('Ag') + 8;
    // une icone de cellule tient dans la ligne, avec 2 px de marge
    if Assigned(FOnGetCellIcon) and (DefaultRowHeight < ScreenIconSize(CELL_ICON) + 4) then
      DefaultRowHeight := ScreenIconSize(CELL_ICON) + 4;
  finally
    bmp.Free;
  end;
  Invalidate;
end;

procedure TRtListGrid.SetCount(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FCount := AValue;
  RowCount := FCount + 1;
  Invalidate;
end;

procedure TRtListGrid.Clear;
begin
  ClearRows;
  SetCount(0);
  FLastSelected := -1;
end;

function TRtListGrid.AddRow(const AValues: array of string): Integer;
var
  sl: TStringList;
  i: Integer;
begin
  sl := TStringList.Create;
  for i := 0 to High(AValues) do
    sl.Add(AValues[i]);
  FRows.Add(sl);
  Result := FRows.Count - 1;
  SetCount(FRows.Count);
end;

function TRtListGrid.CellText(AIndex, ACol: Integer): string;
var
  sl: TStringList;
begin
  Result := '';
  if Assigned(FOnGetCell) then
    Exit(FOnGetCell(Self, AIndex, ACol));
  if (AIndex < 0) or (AIndex >= FRows.Count) then Exit;
  sl := TStringList(FRows[AIndex]);
  if ACol < sl.Count then
    Result := sl[ACol];
end;

function TRtListGrid.GetItemIndex: Integer;
begin
  if (FCount = 0) or (Row < 1) then
    Result := -1
  else
    Result := Row - 1;
end;

procedure TRtListGrid.SetItemIndex(AValue: Integer);
begin
  if (AValue >= 0) and (AValue < FCount) then
    Row := AValue + 1;
end;

procedure TRtListGrid.SelectionChanged;
var
  idx: Integer;
begin
  idx := GetItemIndex;
  if idx = FLastSelected then Exit;
  FLastSelected := idx;
  if Assigned(FOnSelectRow) and (idx >= 0) then
    FOnSelectRow(Self, idx);
end;

procedure TRtListGrid.AfterMoveSelection(const aPrevCol, aPrevRow: Integer);
begin
  inherited AfterMoveSelection(aPrevCol, aPrevRow);
  SelectionChanged;
end;

procedure TRtListGrid.DrawCell(ACol, ARow: Longint; ARect: TRect; AState: TGridDrawState);
var
  s, iconId: string;
  ts: TTextStyle;
  textLeft, px: Integer;
  iconColor: TColor;
  bmp: TBitmap;
begin
  Canvas.Font.Assign(Font);
  if ARow = 0 then
  begin
    Canvas.Brush.Color := clSideBg;
    Canvas.Font.Color := clSideTextHi;
    if ACol < FCaptions.Count then s := FCaptions[ACol] else s := '';
  end
  else
  begin
    if (FCount > 0) and (ARow = Row) then
    begin
      Canvas.Brush.Color := clSideSel;
      Canvas.Font.Color := clSideTextHi;
    end
    else
    begin
      Canvas.Brush.Color := clAppBg;
      Canvas.Font.Color := clAppFg;
    end;
    if ARow - 1 < FCount then
      s := CellText(ARow - 1, ACol)
    else
      s := '';
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.FillRect(ARect);
  if ARow = 0 then
  begin
    Canvas.Pen.Color := clBorder;
    Canvas.Line(ARect.Right - 1, ARect.Top + 4, ARect.Right - 1, ARect.Bottom - 4);
    Canvas.Line(ARect.Left, ARect.Bottom - 1, ARect.Right, ARect.Bottom - 1);
  end;
  textLeft := ARect.Left + 6;
  if ARow > 0 then
  begin
    iconId := CellIcon(ARow - 1, ACol, iconColor);
    if iconId <> '' then
    begin
      px := ScreenIconSize(CELL_ICON);
      bmp := IconBitmap(iconId, px, iconColor);
      if bmp <> nil then
        Canvas.Draw(textLeft, ARect.Top + (ARect.Bottom - ARect.Top - px) div 2, bmp);
      Inc(textLeft, px + 6);
    end;
  end;
  ts := Canvas.TextStyle;
  ts.Layout := tlCenter;
  ts.SingleLine := True;
  ts.Clipping := True;
  ts.EndEllipsis := True;
  ts.Opaque := False;
  Canvas.TextRect(Classes.Rect(textLeft, ARect.Top, ARect.Right - 4, ARect.Bottom),
    textLeft, ARect.Top, s, ts);
end;

end.
