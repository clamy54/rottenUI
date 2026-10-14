// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtChips;

{$mode objfpc}{$H+}

// Rangee de pastilles: jetons cliquables qui passent a la ligne, actions d'ajout, note. Tout est
// dessine; seul un jeton de texte pose un TEdit, le temps de la frappe. L'hote tient la liste.

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, LCLType, Types;

type
  TRtChip = record
    Caption: string;
    Badge: string;
    IconId: string;
    // clDefault: l'accent du theme
    Color: TColor;
    // texte libre: guillemets, espaces visibles, modifiable sur place
    Quoted: Boolean;
    Closable: Boolean;
    Tag: PtrInt;
  end;

  TRtChipEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  TRtChipClickEvent = procedure(Sender: TObject; AIndex: Integer; AButton: TMouseButton) of object;
  TRtChipEditEvent = procedure(Sender: TObject; AIndex: Integer; const AText: string) of object;
  // ATo: rang du jeton une fois deplace
  TRtChipMoveEvent = procedure(Sender: TObject; AFrom, ATo: Integer) of object;

  TRtChipBar = class(TCustomControl)
  private
    FChips: array of TRtChip;
    FRects: array of TRect;
    FActionCaptions, FActionIcons: array of string;
    FActionRects: array of TRect;
    FNote: string;
    FNoteRect: TRect;
    FNoteColor: TColor;
    FLaidWidth: Integer;
    FNeeded: Integer;
    FHot, FHotAction, FFocus: Integer;
    FHotClose: Boolean;
    FDownChip, FDownAction: Integer;
    FDownClose: Boolean;
    FDownAt: TPoint;
    FDragging: Boolean;
    FDropAt: Integer;
    FEdit: TEdit;
    FEditIndex: Integer;
    FEditClosing: Boolean;
    FReorder: Boolean;
    FOnChipClick: TRtChipClickEvent;
    FOnChipClose, FOnActionClick: TRtChipEvent;
    FOnChipEdited: TRtChipEditEvent;
    FOnChipMoved: TRtChipMoveEvent;
    FOnLayoutChanged: TNotifyEvent;
    function GetChip(AIndex: Integer): TRtChip;
    procedure SetChip(AIndex: Integer; const AValue: TRtChip);
    procedure SetNote(const AValue: string);
    function ChipHeight: Integer;
    function EditWidth: Integer;
    procedure PlaceEditor;
    function ChipWidth(const AChip: TRtChip): Integer;
    function ShownText(const AChip: TRtChip): string;
    function ChipColor(const AChip: TRtChip): TColor;
    function BackColor: TColor;
    procedure Layout(AWidth: Integer);
    procedure Relayout;
    function ChipAt(X, Y: Integer; out AOnClose: Boolean): Integer;
    function ActionAt(X, Y: Integer): Integer;
    function DropIndexAt(X, Y: Integer): Integer;
    procedure SetHot(AChip, AAction: Integer; AClose: Boolean);
    procedure DrawChip(AIndex: Integer);
    procedure DrawAction(AIndex: Integer);
    procedure EditExit(Sender: TObject);
    procedure EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure EditChange(Sender: TObject);
    procedure CloseEditor(ACommit: Boolean);
    procedure Moved(AFrom, ATo: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Clear;
    function AddChip(const ACaption: string; AColor: TColor = clDefault; const ABadge: string = '';
      AClosable: Boolean = True): Integer;
    function AddTextChip(const AText: string): Integer;
    procedure ClearActions;
    procedure AddAction(const AIconId, ACaption: string);
    function PreferredHeight(AWidth: Integer): Integer;
    function ChipRect(AIndex: Integer): TRect;
    function ActionRect(AIndex: Integer): TRect;
    procedure EditChip(AIndex: Integer);
    function Editing: Boolean;
    // Echap et Entree d'un dialogue passent par ici avant de le fermer.
    procedure EndEdit(ACommit: Boolean);
    function Count: Integer;
    property Chips[AIndex: Integer]: TRtChip read GetChip write SetChip;
    property FocusedChip: Integer read FFocus write FFocus;
    property Note: string read FNote write SetNote;
    property NoteColor: TColor read FNoteColor write FNoteColor;
    property Reorder: Boolean read FReorder write FReorder;
    // clic gauche sur un jeton ordinaire, clic droit sur n'importe lequel
    property OnChipClick: TRtChipClickEvent read FOnChipClick write FOnChipClick;
    property OnChipClose: TRtChipEvent read FOnChipClose write FOnChipClose;
    property OnChipEdited: TRtChipEditEvent read FOnChipEdited write FOnChipEdited;
    property OnChipMoved: TRtChipMoveEvent read FOnChipMoved write FOnChipMoved;
    property OnActionClick: TRtChipEvent read FOnActionClick write FOnActionClick;
    property OnLayoutChanged: TNotifyEvent read FOnLayoutChanged write FOnLayoutChanged;
    property Color;
    property Font;
    property ParentFont;
    property TabStop;
    property Enabled;
    property OnEnter;
    property OnExit;
  end;

// Un texte fixe d'un seul espace ne doit pas passer pour vide.
function VisibleSpaces(const S: string): string;

implementation

uses
  Math, uTheme, uIcons, uUiKit, uRtButton;

const
  PAD_H = 9;
  GAP = 6;
  LINE_GAP = 4;
  CLOSE_W = 16;
  ICON_LOGICAL = 14;
  DRAG_THRESHOLD = 6;
  EDIT_MIN_W = 90;
  MIDDLE_DOT = #$C2#$B7;

function VisibleSpaces(const S: string): string;
begin
  Result := StringReplace(S, ' ', MIDDLE_DOT, [rfReplaceAll]);
end;

constructor TRtChipBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csClickEvents, csDoubleClicks, csAcceptsControls];
  TabStop := True;
  FHot := -1;
  FHotAction := -1;
  FFocus := -1;
  FDownChip := -1;
  FDownAction := -1;
  FDropAt := -1;
  FEditIndex := -1;
  FNoteColor := clDefault;
  FReorder := True;
  FLaidWidth := -1;
  Width := 300;
  Height := 30;
end;

procedure TRtChipBar.Clear;
begin
  CloseEditor(False);
  FChips := nil;
  FRects := nil;
  FHot := -1;
  FDownChip := -1;
  FDragging := False;
  if FFocus >= 0 then FFocus := -1;
  Relayout;
end;

function TRtChipBar.AddChip(const ACaption: string; AColor: TColor; const ABadge: string;
  AClosable: Boolean): Integer;
begin
  SetLength(FChips, Length(FChips) + 1);
  Result := High(FChips);
  FChips[Result] := Default(TRtChip);
  FChips[Result].Caption := ACaption;
  FChips[Result].Color := AColor;
  FChips[Result].Badge := ABadge;
  FChips[Result].Closable := AClosable;
  Relayout;
end;

function TRtChipBar.AddTextChip(const AText: string): Integer;
begin
  Result := AddChip(AText);
  FChips[Result].Quoted := True;
  Relayout;
end;

procedure TRtChipBar.ClearActions;
begin
  FActionCaptions := nil;
  FActionIcons := nil;
  FActionRects := nil;
  FHotAction := -1;
  Relayout;
end;

procedure TRtChipBar.AddAction(const AIconId, ACaption: string);
begin
  SetLength(FActionCaptions, Length(FActionCaptions) + 1);
  SetLength(FActionIcons, Length(FActionIcons) + 1);
  FActionCaptions[High(FActionCaptions)] := ACaption;
  FActionIcons[High(FActionIcons)] := AIconId;
  Relayout;
end;

function TRtChipBar.Count: Integer;
begin
  Result := Length(FChips);
end;

function TRtChipBar.GetChip(AIndex: Integer): TRtChip;
begin
  if (AIndex >= 0) and (AIndex <= High(FChips)) then Result := FChips[AIndex]
  else Result := Default(TRtChip);
end;

procedure TRtChipBar.SetChip(AIndex: Integer; const AValue: TRtChip);
begin
  if (AIndex < 0) or (AIndex > High(FChips)) then Exit;
  FChips[AIndex] := AValue;
  Relayout;
end;

procedure TRtChipBar.SetNote(const AValue: string);
begin
  if FNote = AValue then Exit;
  FNote := AValue;
  Relayout;
end;

function TRtChipBar.BackColor: TColor;
begin
  Result := Color;
  if (Result = clDefault) or (Result = clNone) then
  begin
    if Parent <> nil then Result := Parent.Brush.Color else Result := clAppBg;
  end;
end;

function TRtChipBar.ChipColor(const AChip: TRtChip): TColor;
begin
  if AChip.Color = clDefault then Result := clAccent else Result := AChip.Color;
end;

function TRtChipBar.ChipHeight: Integer;
begin
  Result := FontTextHeight(Font) + 10;
end;

function TRtChipBar.ShownText(const AChip: TRtChip): string;
begin
  if AChip.Quoted then Result := '"' + VisibleSpaces(AChip.Caption) + '"'
  else Result := AChip.Caption;
end;

function TRtChipBar.ChipWidth(const AChip: TRtChip): Integer;
begin
  Result := 2 * PAD_H + MeasureText(Font, ShownText(AChip));
  if AChip.IconId <> '' then Inc(Result, ScreenIconSize(ICON_LOGICAL) + 5);
  if AChip.Badge <> '' then Inc(Result, MeasureText(Font, AChip.Badge) + 12 + 5);
  if AChip.Closable then Inc(Result, CLOSE_W);
end;

procedure TRtChipBar.Layout(AWidth: Integer);
var
  x, y, h, w, i: Integer;

  procedure Place(AW: Integer; out ARect: TRect);
  begin
    if (x > 0) and (x + AW > AWidth) then
    begin
      x := 0;
      Inc(y, h + LINE_GAP);
    end;
    ARect := Rect(x, y, x + AW, y + h);
    Inc(x, AW + GAP);
  end;

begin
  h := ChipHeight;
  x := 0;
  y := 0;
  SetLength(FRects, Length(FChips));
  for i := 0 to High(FChips) do
    // Le jeton en cours de saisie prend la place de son champ: les suivants sont pousses, pas
    // recouverts.
    if (i = FEditIndex) and (FEdit <> nil) then
      Place(Min(EditWidth, Max(AWidth, 60)), FRects[i])
    else
      Place(ChipWidth(FChips[i]), FRects[i]);
  SetLength(FActionRects, Length(FActionCaptions));
  for i := 0 to High(FActionCaptions) do
  begin
    w := 2 * PAD_H + MeasureText(Font, FActionCaptions[i]);
    if FActionIcons[i] <> '' then Inc(w, ScreenIconSize(ICON_LOGICAL) + 5);
    Place(w, FActionRects[i]);
  end;
  FNoteRect := Rect(0, 0, 0, 0);
  if FNote <> '' then
  begin
    w := MeasureText(Font, FNote) + 8;
    if w > AWidth then w := AWidth;
    Place(w, FNoteRect);
  end;
  FNeeded := y + h;
  FLaidWidth := AWidth;
end;

function TRtChipBar.EditWidth: Integer;
begin
  Result := Max(EDIT_MIN_W, MeasureText(Font, FEdit.Text) + 24) + 12;
end;

procedure TRtChipBar.PlaceEditor;
var
  r: TRect;
begin
  if (FEditIndex < 0) or (FEditIndex > High(FRects)) or (FEdit = nil) then Exit;
  r := FRects[FEditIndex];
  FEdit.SetBounds(r.Left + 6, r.Top + 4, Max(20, r.Right - r.Left - 12), r.Bottom - r.Top - 8);
end;

procedure TRtChipBar.Relayout;
var
  before: Integer;
begin
  before := FNeeded;
  Layout(ClientWidth);
  PlaceEditor;
  Invalidate;
  if (FNeeded <> before) and Assigned(FOnLayoutChanged) and not (csDestroying in ComponentState) then
    FOnLayoutChanged(Self);
end;

function TRtChipBar.PreferredHeight(AWidth: Integer): Integer;
var
  keepWidth: Integer;
begin
  keepWidth := FLaidWidth;
  Layout(AWidth);
  Result := FNeeded;
  if (keepWidth >= 0) and (keepWidth <> AWidth) then Layout(keepWidth);
end;

function TRtChipBar.ChipRect(AIndex: Integer): TRect;
begin
  if (AIndex >= 0) and (AIndex <= High(FRects)) then Result := FRects[AIndex]
  else Result := Rect(0, 0, 0, 0);
end;

function TRtChipBar.ActionRect(AIndex: Integer): TRect;
begin
  if (AIndex >= 0) and (AIndex <= High(FActionRects)) then Result := FActionRects[AIndex]
  else Result := Rect(0, 0, 0, 0);
end;

procedure TRtChipBar.Resize;
begin
  inherited Resize;
  if ClientWidth <> FLaidWidth then
  begin
    Layout(ClientWidth);
    PlaceEditor;
  end;
end;

function TRtChipBar.ChipAt(X, Y: Integer; out AOnClose: Boolean): Integer;
var
  i: Integer;
begin
  AOnClose := False;
  for i := 0 to High(FRects) do
    if PtInRect(FRects[i], Point(X, Y)) then
    begin
      AOnClose := FChips[i].Closable and (X >= FRects[i].Right - CLOSE_W - 2);
      Exit(i);
    end;
  Result := -1;
end;

function TRtChipBar.ActionAt(X, Y: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FActionRects) do
    if PtInRect(FActionRects[i], Point(X, Y)) then Exit(i);
  Result := -1;
end;

function TRtChipBar.DropIndexAt(X, Y: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FRects) do
    if (Y < FRects[i].Bottom + LINE_GAP div 2) and
       ((Y < FRects[i].Top - LINE_GAP div 2) or (X < (FRects[i].Left + FRects[i].Right) div 2)) then
      Exit(i);
  Result := Length(FRects);
end;

procedure TRtChipBar.SetHot(AChip, AAction: Integer; AClose: Boolean);
begin
  if (AChip = FHot) and (AAction = FHotAction) and (AClose = FHotClose) then Exit;
  FHot := AChip;
  FHotAction := AAction;
  FHotClose := AClose;
  Invalidate;
end;

procedure TRtChipBar.DrawChip(AIndex: Integer);
var
  c: TRtChip;
  r, b: TRect;
  back, ink, fill, edge: TColor;
  x, ty, px, bw, cx, cy: Integer;
  bmp: TBitmap;
  hot: Boolean;
begin
  c := FChips[AIndex];
  r := FRects[AIndex];
  back := BackColor;
  hot := Enabled and (AIndex = FHot) and not FDragging;
  if c.Quoted then
  begin
    fill := clEditorBg;
    ink := clEditorFg;
    edge := BlendColor(clAppFg, back, 30);
    if hot then edge := BlendColor(clAppFg, back, 55);
  end
  else
  begin
    ink := ChipColor(c);
    fill := BlendColor(ink, back, 14);
    if hot then fill := BlendColor(ink, back, 24);
    edge := BlendColor(ink, back, 45);
  end;
  if not Enabled then ink := BlendColor(ink, back, 45);
  if FDragging and (AIndex = FDownChip) then
  begin
    fill := back;
    edge := BlendColor(clAppFg, back, 20);
    ink := BlendColor(ink, back, 40);
  end;
  if Focused and (AIndex = FFocus) and (FEditIndex < 0) then edge := clAccent;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := fill;
  Canvas.Pen.Color := edge;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, 10, 10);
  x := r.Left + PAD_H;
  ty := r.Top + (r.Bottom - r.Top - Canvas.TextHeight('Ag')) div 2;
  if c.IconId <> '' then
  begin
    px := ScreenIconSize(ICON_LOGICAL);
    bmp := IconBitmap(c.IconId, px, ink);
    if bmp <> nil then Canvas.Draw(x, (r.Top + r.Bottom - px) div 2, bmp);
    Inc(x, px + 5);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ink;
  Canvas.Font.Style := [];
  Canvas.TextOut(x, ty, ShownText(c));
  Inc(x, Canvas.TextWidth(ShownText(c)));
  if c.Badge <> '' then
  begin
    bw := Canvas.TextWidth(c.Badge) + 12;
    b := Rect(x + 5, r.Top + 3, x + 5 + bw, r.Bottom - 3);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ink;
    Canvas.Pen.Color := ink;
    Canvas.RoundRect(b.Left, b.Top, b.Right, b.Bottom, 8, 8);
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := back;
    Canvas.TextOut(b.Left + 6, ty, c.Badge);
  end;
  if c.Closable then
  begin
    cx := r.Right - CLOSE_W div 2 - 3;
    cy := (r.Top + r.Bottom) div 2;
    if hot and FHotClose then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := BlendColor(ink, fill, 30);
      Canvas.Pen.Color := Canvas.Brush.Color;
      Canvas.Ellipse(cx - 7, cy - 7, cx + 8, cy + 8);
      Canvas.Pen.Color := ink;
    end
    else
      Canvas.Pen.Color := BlendColor(ink, fill, 55);
    Canvas.Line(cx - 3, cy - 3, cx + 4, cy + 4);
    Canvas.Line(cx - 3, cy + 3, cx + 4, cy - 4);
  end;
end;

procedure TRtChipBar.DrawAction(AIndex: Integer);
var
  r: TRect;
  back, ink: TColor;
  x, px: Integer;
  bmp: TBitmap;
begin
  r := FActionRects[AIndex];
  back := BackColor;
  ink := clAccent;
  if not Enabled then ink := BlendColor(ink, back, 45);
  Canvas.Brush.Style := bsSolid;
  if Enabled and (AIndex = FHotAction) then Canvas.Brush.Color := BlendColor(ink, back, 14)
  else Canvas.Brush.Color := back;
  Canvas.Pen.Color := BlendColor(ink, back, 40);
  Canvas.Pen.Style := psDot;
  if Focused and (FFocus = Length(FChips) + AIndex) then
  begin
    Canvas.Pen.Color := clAccent;
    Canvas.Pen.Style := psSolid;
  end;
  Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, 10, 10);
  Canvas.Pen.Style := psSolid;
  x := r.Left + PAD_H;
  if FActionIcons[AIndex] <> '' then
  begin
    px := ScreenIconSize(ICON_LOGICAL);
    bmp := IconBitmap(FActionIcons[AIndex], px, ink);
    if bmp <> nil then Canvas.Draw(x, (r.Top + r.Bottom - px) div 2, bmp);
    Inc(x, px + 5);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ink;
  Canvas.TextOut(x, r.Top + (r.Bottom - r.Top - Canvas.TextHeight('Ag')) div 2, FActionCaptions[AIndex]);
end;

procedure TRtChipBar.Paint;
var
  i, x: Integer;
  r: TRect;
begin
  if ClientWidth <> FLaidWidth then Layout(ClientWidth);
  Canvas.Font.Assign(Font);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := BackColor;
  Canvas.FillRect(ClientRect);
  for i := 0 to High(FChips) do
    if i <> FEditIndex then DrawChip(i)
    else
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := clEditorBg;
      Canvas.Pen.Color := clAccent;
      Canvas.RoundRect(FRects[i].Left, FRects[i].Top, FRects[i].Right, FRects[i].Bottom, 10, 10);
    end;
  for i := 0 to High(FActionCaptions) do
    DrawAction(i);
  if FNote <> '' then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Style := [];
    if FNoteColor = clDefault then Canvas.Font.Color := BlendColor(clAppFg, BackColor, 58)
    else Canvas.Font.Color := FNoteColor;
    r := FNoteRect;
    Canvas.TextRect(r, r.Left + 4, r.Top + (r.Bottom - r.Top - Canvas.TextHeight('Ag')) div 2, FNote);
  end;
  if FDragging and (FDropAt >= 0) then
  begin
    if FDropAt <= High(FRects) then
    begin
      r := FRects[FDropAt];
      x := r.Left - GAP div 2 - 1;
    end
    else if Length(FRects) > 0 then
    begin
      r := FRects[High(FRects)];
      x := r.Right + GAP div 2 - 1;
    end
    else
      Exit;
    if x < 0 then x := 0;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := clAccent;
    Canvas.FillRect(Rect(x, r.Top, x + 2, r.Bottom));
  end;
end;

procedure TRtChipBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if not Enabled then Exit;
  if FEditIndex >= 0 then CloseEditor(True);
  if CanFocus and not Focused then SetFocus;
  FDownChip := ChipAt(X, Y, FDownClose);
  FDownAction := -1;
  if FDownChip < 0 then FDownAction := ActionAt(X, Y);
  FDownAt := Point(X, Y);
  FDragging := False;
  if FDownChip >= 0 then FFocus := FDownChip
  else if FDownAction >= 0 then FFocus := Length(FChips) + FDownAction;
  Invalidate;
end;

procedure TRtChipBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  chip, drop: Integer;
  onClose: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  if (ssLeft in Shift) and (FDownChip >= 0) and FReorder and not FDownClose and
     (Length(FChips) > 1) then
  begin
    if not FDragging and ((Abs(X - FDownAt.X) > DRAG_THRESHOLD) or
      (Abs(Y - FDownAt.Y) > DRAG_THRESHOLD)) then
      FDragging := True;
    if FDragging then
    begin
      drop := DropIndexAt(X, Y);
      if drop <> FDropAt then
      begin
        FDropAt := drop;
        Invalidate;
      end;
      Exit;
    end;
  end;
  chip := ChipAt(X, Y, onClose);
  if chip >= 0 then SetHot(chip, -1, onClose)
  else SetHot(-1, ActionAt(X, Y), False);
end;

procedure TRtChipBar.Moved(AFrom, ATo: Integer);
begin
  if (AFrom = ATo) or (ATo < 0) or (ATo > High(FChips)) then Exit;
  FFocus := ATo;
  if Assigned(FOnChipMoved) then FOnChipMoved(Self, AFrom, ATo);
end;

procedure TRtChipBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  chip, act, target, from: Integer;
  onClose, wasDrag: Boolean;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not Enabled then Exit;
  wasDrag := FDragging;
  from := FDownChip;
  target := FDropAt;
  act := FDownAction;
  FDragging := False;
  FDropAt := -1;
  FDownChip := -1;
  FDownAction := -1;
  Invalidate;
  if wasDrag then
  begin
    // L'insertion se compte jeton retire: deposer juste apres soi ne deplace rien.
    if target > from then Dec(target);
    Moved(from, target);
    Exit;
  end;
  chip := ChipAt(X, Y, onClose);
  // L'hote peut tout reconstruire dans son gestionnaire: plus rien n'est lu apres l'appel.
  if (chip >= 0) and (chip = from) then
  begin
    if Button = mbRight then
    begin
      if Assigned(FOnChipClick) then FOnChipClick(Self, chip, mbRight);
    end
    else if Button = mbLeft then
    begin
      if onClose and FDownClose then
      begin
        if Assigned(FOnChipClose) then FOnChipClose(Self, chip);
      end
      else if FChips[chip].Quoted then EditChip(chip)
      else if Assigned(FOnChipClick) then FOnChipClick(Self, chip, mbLeft);
    end;
  end
  else if (Button = mbLeft) and (act >= 0) and (ActionAt(X, Y) = act) then
  begin
    if Assigned(FOnActionClick) then FOnActionClick(Self, act);
  end;
end;

procedure TRtChipBar.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1, -1, False);
end;

procedure TRtChipBar.KeyDown(var Key: Word; Shift: TShiftState);
var
  total, k: Integer;
begin
  inherited KeyDown(Key, Shift);
  if not Enabled or (FEditIndex >= 0) then Exit;
  total := Length(FChips) + Length(FActionCaptions);
  if total = 0 then Exit;
  k := Key;
  if (k = VK_LEFT) or (k = VK_RIGHT) then
  begin
    Key := 0;
    if (Shift = [ssShift]) and FReorder and (FFocus >= 0) and (FFocus <= High(FChips)) then
    begin
      if k = VK_LEFT then Moved(FFocus, FFocus - 1) else Moved(FFocus, FFocus + 1);
      Exit;
    end;
    if k = VK_LEFT then FFocus := Max(0, FFocus - 1)
    else FFocus := Min(total - 1, FFocus + 1);
    Invalidate;
    Exit;
  end;
  if (FFocus < 0) or (FFocus >= total) then Exit;
  if (k in [VK_RETURN, VK_SPACE, VK_F2]) and (Shift = []) then
  begin
    Key := 0;
    if FFocus > High(FChips) then
    begin
      if Assigned(FOnActionClick) then FOnActionClick(Self, FFocus - Length(FChips));
    end
    else if FChips[FFocus].Quoted then EditChip(FFocus)
    else if Assigned(FOnChipClick) then FOnChipClick(Self, FFocus, mbLeft);
  end
  else if (k in [VK_DELETE, VK_BACK]) and (Shift = []) and (FFocus <= High(FChips)) and
    FChips[FFocus].Closable then
  begin
    Key := 0;
    if Assigned(FOnChipClose) then FOnChipClose(Self, FFocus);
  end
  else if (k = VK_APPS) or ((k = VK_F10) and (Shift = [ssShift])) then
  begin
    Key := 0;
    if (FFocus <= High(FChips)) and Assigned(FOnChipClick) then FOnChipClick(Self, FFocus, mbRight);
  end;
end;

procedure TRtChipBar.DoEnter;
begin
  inherited DoEnter;
  if (FFocus < 0) and (Length(FChips) + Length(FActionCaptions) > 0) then FFocus := 0;
  Invalidate;
end;

procedure TRtChipBar.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

function TRtChipBar.Editing: Boolean;
begin
  Result := FEditIndex >= 0;
end;

procedure TRtChipBar.EditChip(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FChips)) or not FChips[AIndex].Quoted or not Enabled then Exit;
  CloseEditor(True);
  if AIndex > High(FChips) then Exit;
  if FEdit = nil then
  begin
    FEdit := TEdit.Create(Self);
    FEdit.Parent := Self;
    FEdit.BorderStyle := bsNone;
    FEdit.AutoSize := False;
    FEdit.OnExit := @EditExit;
    FEdit.OnKeyDown := @EditKeyDown;
    FEdit.OnChange := @EditChange;
  end;
  FEdit.Color := clEditorBg;
  FEdit.Font.Assign(Font);
  FEdit.Font.Color := clEditorFg;
  FEditIndex := AIndex;
  FFocus := AIndex;
  FEditClosing := True;
  try
    FEdit.Text := FChips[AIndex].Caption;
  finally
    FEditClosing := False;
  end;
  Relayout;
  FEdit.Visible := True;
  if FEdit.CanFocus then
  begin
    FEdit.SetFocus;
    FEdit.SelectAll;
  end;
end;

procedure TRtChipBar.EditChange(Sender: TObject);
begin
  if FEditClosing or (FEditIndex < 0) then Exit;
  Relayout;
end;

procedure TRtChipBar.CloseEditor(ACommit: Boolean);
var
  index: Integer;
  txt: string;
begin
  if (FEditIndex < 0) or FEditClosing then Exit;
  FEditClosing := True;
  try
    index := FEditIndex;
    txt := FEdit.Text;
    FEditIndex := -1;
    FEdit.Visible := False;
  finally
    FEditClosing := False;
  end;
  Relayout;
  if (index > High(FChips)) or not Assigned(FOnChipEdited) then Exit;
  if not ACommit then txt := FChips[index].Caption;
  // Un jeton reste vide est signale meme sans changement: a l'hote de le retirer.
  if (txt <> FChips[index].Caption) or (txt = '') then FOnChipEdited(Self, index, txt);
end;

procedure TRtChipBar.EndEdit(ACommit: Boolean);
begin
  if FEditIndex < 0 then Exit;
  // Le champ rend le focus avant de disparaitre, sinon il file au premier controle venu.
  if ACommit then
  begin
    if CanFocus then SetFocus;
    CloseEditor(True);
  end
  else
  begin
    CloseEditor(False);
    if CanFocus then SetFocus;
  end;
end;

procedure TRtChipBar.EditExit(Sender: TObject);
begin
  CloseEditor(True);
end;

procedure TRtChipBar.EditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    EndEdit(True);
  end
  else if Key = VK_ESCAPE then
  begin
    Key := 0;
    EndEdit(False);
  end;
end;

end.
