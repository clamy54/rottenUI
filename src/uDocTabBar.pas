// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uDocTabBar;

{$mode objfpc}{$H+}

// Onglets de documents dessines a la main, sans TPageControl. La liste vit dans
// l'application, relue par evenements; la barre signale les gestes et n'execute rien.

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, ExtCtrls, LCLType, LCLIntf,
  LazUTF8, uTheme;

type
  TDocTabInfo = record
    Caption: string;
    Active: Boolean;
    Modified: Boolean;
    ReadOnly: Boolean;
    Recording: Boolean;   // pastille clignotante a la place de la croix
  end;

  TDocTabCountEvent = function(Sender: TObject): Integer of object;
  // AInfo arrive vide: ne remplir que ce qui s'applique
  TDocTabInfoEvent = procedure(Sender: TObject; AIndex: Integer;
    var AInfo: TDocTabInfo) of object;
  TDocTabEvent = procedure(Sender: TObject; AIndex: Integer) of object;
  // ANewIndex: position finale, l'onglet etant retire avant reinsertion
  TDocTabMoveEvent = procedure(Sender: TObject; AIndex, ANewIndex: Integer) of object;
  // AIndex = -1: bande vide (menu contextuel seulement)
  TDocTabPointEvent = procedure(Sender: TObject; AIndex: Integer;
    const AScreenPt: TPoint) of object;

  TDocTabSlot = record
    Info: TDocTabInfo;
    Full: TRect;
    Close: TRect;
  end;

  TDocTabBar = class(TCustomControl)
  private
    FSlots: array of TDocTabSlot;
    FScroll: Integer;
    FHoverTab: Integer;
    FLeftArrow, FRightArrow, FPlus: TRect;
    FShowArrows: Boolean;
    FTabsLeft, FTabsRight: Integer;
    FContentW: Integer;
    FDimmed: Boolean;
    FReveal: Boolean;
    FBlinkOn: Boolean;
    FBlink: TTimer;
    FDragTab: Integer;
    FDragStartX: Integer;
    FDragX: Integer;
    FDragging: Boolean;
    FOnTabCount: TDocTabCountEvent;
    FOnTabInfo: TDocTabInfoEvent;
    FOnTabActivate: TDocTabEvent;
    FOnTabClose: TDocTabEvent;
    FOnNewTab: TNotifyEvent;
    FOnTabMove: TDocTabMoveEvent;
    FOnTabDropOutside: TDocTabPointEvent;
    FOnTabContextMenu: TDocTabPointEvent;
    procedure SetDimmed(AValue: Boolean);
    procedure BlinkTick(Sender: TObject);
    procedure BuildLayout;
    procedure RevealActive;
    function GapIndex(X: Integer): Integer;
    function DropTargetPos(X, ADragTab: Integer): Integer;
    function GapX(AGap: Integer): Integer;
    procedure DrawTab(ASlot: Integer);
    procedure DrawGlyphClose(const R: TRect; AColor: TColor);
    procedure DrawGlyphPlus(const R: TRect; AColor: TColor);
    procedure DrawGlyphArrow(const R: TRect; ALeft: Boolean; AColor: TColor);
    procedure DrawDot(const R: TRect; AColor: TColor);
    procedure DrawGlyphLock(const R: TRect; AColor: TColor);
    function TabAt(X: Integer; out AClose: Boolean): Integer;
    procedure ClampScroll;
    procedure NewTab;
    procedure CloseTab(AIndex: Integer);
    procedure ContextMenu(AIndex, X, Y: Integer);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    // liste ou onglet actif change. Simple changement d'etat: Invalidate suffit
    procedure RefreshBar;
    // onglet actif attenue: ce groupe n'a pas le focus
    property Dimmed: Boolean read FDimmed write SetDimmed;
    property OnTabCount: TDocTabCountEvent read FOnTabCount write FOnTabCount;
    property OnTabInfo: TDocTabInfoEvent read FOnTabInfo write FOnTabInfo;
    property OnTabActivate: TDocTabEvent read FOnTabActivate write FOnTabActivate;
    property OnTabClose: TDocTabEvent read FOnTabClose write FOnTabClose;
    // bouton '+' ou double-clic sur la bande vide
    property OnNewTab: TNotifyEvent read FOnNewTab write FOnNewTab;
    property OnTabMove: TDocTabMoveEvent read FOnTabMove write FOnTabMove;
    property OnTabDropOutside: TDocTabPointEvent read FOnTabDropOutside write FOnTabDropOutside;
    // clic droit: la barre n'active rien et n'a pas de menu a elle
    property OnTabContextMenu: TDocTabPointEvent read FOnTabContextMenu write FOnTabContextMenu;
  end;

implementation

const
  TAB_MAXW = 220;
  TAB_MINW = 90;
  PADX     = 11;
  CLOSE_SZ = 16;
  ARROW_W  = 24;
  PLUS_W   = 34;
  DOT_D    = 8;
  DRAG_THRESH = 6;

constructor TDocTabBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHoverTab := -1;
  FScroll := 0;
  FDragTab := -1;
  FBlink := TTimer.Create(Self);
  FBlink.Interval := 500;
  FBlink.Enabled := False;
  FBlink.OnTimer := @BlinkTick;
end;

procedure TDocTabBar.SetDimmed(AValue: Boolean);
begin
  if AValue = FDimmed then Exit;
  FDimmed := AValue;
  Invalidate;
end;

procedure TDocTabBar.RefreshBar;
begin
  FReveal := True;
  Invalidate;
end;

procedure TDocTabBar.BlinkTick(Sender: TObject);
begin
  // barre masquee: plus de peinture pour l'arreter, elle le relancera au besoin
  if not IsVisible then
  begin
    FBlink.Enabled := False;
    Exit;
  end;
  FBlinkOn := not FBlinkOn;
  Invalidate;
end;

procedure TDocTabBar.ClampScroll;
var
  maxScroll: Integer;
begin
  maxScroll := FContentW - (FTabsRight - FTabsLeft);
  if maxScroll < 0 then maxScroll := 0;
  if FScroll > maxScroll then FScroll := maxScroll;
  if FScroll < 0 then FScroll := 0;
end;

procedure TDocTabBar.BuildLayout;

  function TabW(const ACap: string): Integer;
  begin
    Result := Canvas.TextWidth(ACap) + PADX * 2 + CLOSE_SZ + 6;
    if Result > TAB_MAXW then Result := TAB_MAXW;
    if Result < TAB_MINW then Result := TAB_MINW;
  end;

var
  i, x, tw, n: Integer;
  rec: Boolean;
begin
  n := 0;
  if Assigned(FOnTabCount) then n := FOnTabCount(Self);
  if n < 0 then n := 0;
  SetLength(FSlots, 0);
  SetLength(FSlots, n);

  Canvas.Font := Font;
  if RSUiFontName <> '' then Canvas.Font.Name := RSUiFontName;
  if RSUiFontSize > 0 then Canvas.Font.Size := RSUiFontSize;
  Canvas.Font.Quality := fqCleartype;

  FPlus := Rect(ClientWidth - PLUS_W, 0, ClientWidth, ClientHeight);

  FContentW := 0;
  rec := False;
  for i := 0 to n - 1 do
  begin
    if Assigned(FOnTabInfo) then FOnTabInfo(Self, i, FSlots[i].Info);
    FSlots[i].Full := Rect(0, 0, TabW(FSlots[i].Info.Caption), ClientHeight);
    Inc(FContentW, FSlots[i].Full.Right);
    if FSlots[i].Info.Recording then rec := True;
  end;

  FTabsLeft := 0;
  FTabsRight := FPlus.Left;
  FShowArrows := FContentW > (FTabsRight - FTabsLeft);
  if FShowArrows then
  begin
    FLeftArrow := Rect(0, 0, ARROW_W, ClientHeight);
    FRightArrow := Rect(ARROW_W, 0, ARROW_W * 2, ClientHeight);
    FTabsLeft := ARROW_W * 2;
  end;

  ClampScroll;

  x := FTabsLeft - FScroll;
  for i := 0 to n - 1 do
  begin
    tw := FSlots[i].Full.Right;
    FSlots[i].Full := Rect(x, 0, x + tw, ClientHeight);
    FSlots[i].Close := Rect(x + tw - CLOSE_SZ - 6,
      (ClientHeight - CLOSE_SZ) div 2, x + tw - 6,
      (ClientHeight - CLOSE_SZ) div 2 + CLOSE_SZ);
    Inc(x, tw);
  end;

  // le clignotement ne tourne que si un onglet de CETTE barre enregistre
  if rec <> FBlink.Enabled then
  begin
    FBlinkOn := True;
    FBlink.Enabled := rec;
  end;
end;

procedure TDocTabBar.RevealActive;
var
  s, i, old, slotLeft, slotRight, viewW: Integer;
begin
  s := -1;
  for i := 0 to High(FSlots) do
    if FSlots[i].Info.Active then
    begin
      s := i;
      Break;
    end;
  if s < 0 then Exit;
  old := FScroll;
  viewW := FTabsRight - FTabsLeft;
  slotLeft := FSlots[s].Full.Left - (FTabsLeft - FScroll);
  slotRight := FSlots[s].Full.Right - (FTabsLeft - FScroll);
  if slotLeft < FScroll then
    FScroll := slotLeft
  else if slotRight > FScroll + viewW then
    FScroll := slotRight - viewW;
  ClampScroll;
  if FScroll = old then Exit;
  for i := 0 to High(FSlots) do
  begin
    Types.OffsetRect(FSlots[i].Full, old - FScroll, 0);
    Types.OffsetRect(FSlots[i].Close, old - FScroll, 0);
  end;
end;

function TDocTabBar.GapIndex(X: Integer): Integer;
var
  i, mid: Integer;
begin
  for i := 0 to High(FSlots) do
  begin
    mid := (FSlots[i].Full.Left + FSlots[i].Full.Right) div 2;
    if X < mid then Exit(i);
  end;
  Result := Length(FSlots);
end;

// l'onglet est retire avant reinsertion: un gap au-dela de sa position decale de 1
function TDocTabBar.DropTargetPos(X, ADragTab: Integer): Integer;
var
  gap: Integer;
begin
  BuildLayout;
  // la liste a pu fondre pendant le glissement
  if ADragTab > High(FSlots) then Exit(-1);
  gap := GapIndex(X);
  if gap > ADragTab then Result := gap - 1 else Result := gap;
end;

function TDocTabBar.GapX(AGap: Integer): Integer;
begin
  if Length(FSlots) = 0 then
    Result := FTabsLeft
  else if AGap <= 0 then
    Result := FSlots[0].Full.Left
  else if AGap > High(FSlots) then
    Result := FSlots[High(FSlots)].Full.Right
  else
    Result := FSlots[AGap].Full.Left;
end;

procedure TDocTabBar.DrawGlyphClose(const R: TRect; AColor: TColor);
var
  m: Integer;
begin
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  m := 4;
  Canvas.Line(R.Left + m, R.Top + m, R.Right - m, R.Bottom - m);
  Canvas.Line(R.Right - m, R.Top + m, R.Left + m, R.Bottom - m);
end;

procedure TDocTabBar.DrawGlyphPlus(const R: TRect; AColor: TColor);
var
  cx, cy, s: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  s := 6;
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  Canvas.Line(cx - s, cy, cx + s + 1, cy);
  Canvas.Line(cx, cy - s, cx, cy + s + 1);
end;

procedure TDocTabBar.DrawGlyphArrow(const R: TRect; ALeft: Boolean; AColor: TColor);
var
  cx, cy, s: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  s := 4;
  Canvas.Brush.Color := AColor;
  Canvas.Pen.Color := AColor;
  if ALeft then
    Canvas.Polygon([Point(cx + s, cy - s), Point(cx - s, cy), Point(cx + s, cy + s)])
  else
    Canvas.Polygon([Point(cx - s, cy - s), Point(cx + s, cy), Point(cx - s, cy + s)]);
end;

procedure TDocTabBar.DrawDot(const R: TRect; AColor: TColor);
begin
  Canvas.Brush.Color := AColor;
  Canvas.Pen.Color := AColor;
  Canvas.Ellipse(R.Left, R.Top, R.Left + DOT_D, R.Top + DOT_D);
end;

procedure TDocTabBar.DrawGlyphLock(const R: TRect; AColor: TColor);
var
  cx, cy: Integer;
begin
  cx := (R.Left + R.Right) div 2;
  cy := (R.Top + R.Bottom) div 2;
  Canvas.Pen.Color := AColor;
  Canvas.Brush.Style := bsClear;
  Canvas.Arc(cx - 3, cy - 6, cx + 3, cy + 1, 0, 180 * 16);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.FillRect(cx - 5, cy - 2, cx + 5, cy + 6);
end;

procedure TDocTabBar.DrawTab(ASlot: Integer);
var
  info: TDocTabInfo;
  r, dot: TRect;
  active, hovered: Boolean;
  cap: string;
  bg, iconCol: TColor;
  ty, availW: Integer;
begin
  info := FSlots[ASlot].Info;
  r := FSlots[ASlot].Full;
  active := info.Active;
  hovered := ASlot = FHoverTab;

  if active and not FDimmed then bg := clTabActive
  else if active then bg := clTabActiveDim
  else if hovered then bg := clTabHover
  else bg := clTabInactive;
  Canvas.Brush.Color := bg;
  Canvas.Pen.Color := bg;
  Canvas.RoundRect(r.Left, r.Top, r.Right, ClientHeight + 8, 7, 7);

  if active and FDimmed then
    Canvas.Font.Color := clTabActiveTextDim
  else if active or hovered then
    Canvas.Font.Color := clTabActiveText
  else
    Canvas.Font.Color := clTabInactiveText;
  Canvas.Brush.Style := bsClear;
  cap := info.Caption;
  availW := (r.Right - PADX - CLOSE_SZ - 6) - (r.Left + PADX);
  while (Canvas.TextWidth(cap) > availW) and (UTF8Length(cap) > 1) do
    cap := UTF8Copy(cap, 1, UTF8Length(cap) - 1);
  if cap <> info.Caption then
    cap := UTF8Copy(cap, 1, UTF8Length(cap) - 1) + '…';
  ty := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  Canvas.TextOut(r.Left + PADX, ty, cap);
  Canvas.Brush.Style := bsSolid;

  if active or hovered then iconCol := clTabIconHi else iconCol := clTabIcon;
  dot := Rect(FSlots[ASlot].Close.Left + (CLOSE_SZ - DOT_D) div 2,
    (ClientHeight - DOT_D) div 2, 0, 0);
  if info.Recording and not hovered then
  begin
    if FBlinkOn then DrawDot(dot, clMacroRec);
  end
  else if info.ReadOnly and not hovered then
  begin
    if info.Modified then
      DrawGlyphLock(FSlots[ASlot].Close, clTabLockMod)
    else
      DrawGlyphLock(FSlots[ASlot].Close, clTabLock);
  end
  else if info.Modified and not hovered then
    DrawDot(dot, iconCol)
  else
    DrawGlyphClose(FSlots[ASlot].Close, iconCol);
end;

procedure TDocTabBar.Paint;
var
  i, mx: Integer;
begin
  BuildLayout;
  if FReveal then
  begin
    FReveal := False;
    RevealActive;
  end;

  Canvas.Brush.Color := clTabStrip;
  Canvas.FillRect(ClientRect);

  for i := 0 to High(FSlots) do
    if (FSlots[i].Full.Right > FTabsLeft) and (FSlots[i].Full.Left < FTabsRight) then
      DrawTab(i);

  if FShowArrows then
  begin
    Canvas.Brush.Color := clTabStrip;
    Canvas.FillRect(Rect(0, 0, FTabsLeft, ClientHeight));
    DrawGlyphArrow(FLeftArrow, True, clTabGlyph);
    DrawGlyphArrow(FRightArrow, False, clTabGlyph);
    Canvas.Pen.Color := clBorder;
    Canvas.Line(FTabsLeft - 1, 4, FTabsLeft - 1, ClientHeight - 4);
  end;

  Canvas.Brush.Color := clTabStrip;
  Canvas.FillRect(FPlus);
  DrawGlyphPlus(FPlus, clTabGlyph);

  if FDragging and (FDragX >= 0) and (FDragX < ClientWidth) then
  begin
    mx := GapX(GapIndex(FDragX));
    if mx < FTabsLeft then mx := FTabsLeft;
    if mx > FTabsRight then mx := FTabsRight;
    Canvas.Pen.Color := clCaret;
    Canvas.Pen.Width := 2;
    Canvas.Line(mx, 3, mx, ClientHeight - 3);
    Canvas.Pen.Width := 1;
  end;
end;

procedure TDocTabBar.Resize;
begin
  inherited Resize;
  // gtk2 n'invalide que la bande nouvellement exposee: le '+' (ancre a droite)
  // et les fleches restaient peints a leur ancienne position
  Invalidate;
end;

function TDocTabBar.TabAt(X: Integer; out AClose: Boolean): Integer;
var
  i: Integer;
begin
  AClose := False;
  Result := -1;
  for i := 0 to High(FSlots) do
    if (X >= FSlots[i].Full.Left) and (X < FSlots[i].Full.Right)
       and (X >= FTabsLeft) and (X < FTabsRight) then
    begin
      Result := i;
      AClose := (X >= FSlots[i].Close.Left) and (X < FSlots[i].Close.Right);
      Exit;
    end;
end;

procedure TDocTabBar.NewTab;
begin
  if Assigned(FOnNewTab) then FOnNewTab(Self);
end;

procedure TDocTabBar.CloseTab(AIndex: Integer);
begin
  if Assigned(FOnTabClose) then FOnTabClose(Self, AIndex);
end;

procedure TDocTabBar.ContextMenu(AIndex, X, Y: Integer);
begin
  if Assigned(FOnTabContextMenu) then
    FOnTabContextMenu(Self, AIndex, ClientToScreen(Point(X, Y)));
end;

// les evenements partent en dernier: l'application peut refaire la liste dedans
procedure TDocTabBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
  onClose: Boolean;
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragTab := -1;
  FDragging := False;

  if FShowArrows and PtInRect(FLeftArrow, Point(X, Y)) then
  begin
    Dec(FScroll, 120); ClampScroll; Invalidate; Exit;
  end;
  if FShowArrows and PtInRect(FRightArrow, Point(X, Y)) then
  begin
    Inc(FScroll, 120); ClampScroll; Invalidate; Exit;
  end;
  if PtInRect(FPlus, Point(X, Y)) then
  begin
    NewTab; Exit;
  end;

  idx := TabAt(X, onClose);
  if idx < 0 then
  begin
    if ssDouble in Shift then
      NewTab
    else if Button = mbRight then
      ContextMenu(-1, X, Y);
    Exit;
  end;

  if Button = mbLeft then
  begin
    if onClose then
      CloseTab(idx)
    else
    begin
      FDragTab := idx;
      FDragStartX := X;
      if Assigned(FOnTabActivate) then FOnTabActivate(Self, idx);
    end;
  end
  else if Button = mbMiddle then
    CloseTab(idx)
  else if Button = mbRight then
    ContextMenu(idx, X, Y);
end;

procedure TDocTabBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  idx: Integer;
  onClose: Boolean;
begin
  inherited MouseMove(Shift, X, Y);
  // la capture souris LCL garde MouseMove/MouseUp ici meme hors bornes
  if (FDragTab >= 0) and (ssLeft in Shift) and not FDragging then
    if Abs(X - FDragStartX) > DRAG_THRESH then
    begin
      FDragging := True;
      Cursor := crDrag;
    end;
  if FDragging then
  begin
    FDragX := X;
    Invalidate;
    Exit;
  end;

  idx := TabAt(X, onClose);
  if idx <> FHoverTab then
  begin
    FHoverTab := idx;
    Invalidate;
  end;
end;

procedure TDocTabBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  d, p: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if not FDragging then
  begin
    FDragTab := -1;
    Exit;
  end;
  FDragging := False;
  Cursor := crDefault;
  d := FDragTab;
  FDragTab := -1;
  Invalidate;
  if d < 0 then Exit;
  if (X >= 0) and (X < ClientWidth) and (Y >= 0) and (Y < ClientHeight) then
  begin
    p := DropTargetPos(X, d);
    if (p >= 0) and (p <> d) and Assigned(FOnTabMove) then
      FOnTabMove(Self, d, p);
  end
  else if Assigned(FOnTabDropOutside) then
    FOnTabDropOutside(Self, d, ClientToScreen(Point(X, Y)));
end;

procedure TDocTabBar.MouseLeave;
begin
  inherited MouseLeave;
  if FHoverTab <> -1 then
  begin
    FHoverTab := -1;
    Invalidate;
  end;
end;

function TDocTabBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if not FShowArrows then Exit;
  if WheelDelta > 0 then Dec(FScroll, 60) else Inc(FScroll, 60);
  ClampScroll;
  Invalidate;
end;

end.
