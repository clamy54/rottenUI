// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtCombo;

{$mode objfpc}{$H+}

// Liste de choix de la coque, dessinee aux couleurs du theme: la liste
// deroulante native de Windows impose un cadre et un bouton clairs.
// Interface volontairement proche de TComboBox en lecture seule.
//
// Le choix s'ouvre dans une liste deroulante dediee (TRtDropList), et non
// plus dans un menu contextuel: un menu plus haut que l'ecran n'avait que les
// fleches de defilement natives de Windows (claires, sans recherche), cas
// signale sur les attributs d'une classe (une cinquantaine pour
// inetOrgPerson, des centaines pour un compte AD). La liste tient dans la
// zone de travail de l'ecran (20 lignes au plus), s'ouvre vers le haut s'il y
// a plus de place, defile (barre, molette, clavier) et, longue, se filtre en
// tapant.

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Graphics, Forms, LCLType, Types;

const
  // lignes visibles au plus; au-dela la liste defile
  DROP_MAX_ROWS = 20;
  // a partir de ce nombre d'elements, un champ de filtre en tete
  DROP_FILTER_MIN = 16;

type
  TRtComboBox = class;

  TRtDropList = class(TForm)
  private
    FCombo: TRtComboBox;
    FFrame: TPanel;
    FFilter: TEdit;
    FList: TListBox;
    FMap: array of Integer;    // ligne affichee -> index dans les elements
    // identite de chaque ligne au moment du remplissage: l'objet associe
    // (Items.Objects), pour retrouver une ligne apres une mise a jour meme
    // quand deux libelles sont identiques
    FRowObjs: array of TObject;
    FRowHeight: Integer;
    FDone: Boolean;
    procedure Refill;
    procedure FilterChange(Sender: TObject);
    procedure KeysDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ListDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure FormDeactivate(Sender: TObject);
    procedure Choose(ARow: Integer);
    procedure MoveBy(ADelta: Integer);
  public
    constructor CreateFor(ACombo: TRtComboBox);
    // position et taille: sous la liste ou au-dessus, dans la zone de travail
    procedure Place;
    procedure CloseDrop;
    // elements changes pendant que la liste est ouverte (arrivee asynchrone
    // des suffixes UPN, par exemple): lignes et table d'index reconstruites,
    // sinon choisir une ligne pourrait selectionner l'element qui occupe
    // desormais son ancien index; la selection est conservee par valeur
    procedure ItemsUpdated;
    // tests: memes chemins que la frappe et le clavier
    procedure SetFilterText(const AText: string);
    procedure PressKey(AKey: Word);
    function VisibleCount: Integer;
    function VisibleItem(ARow: Integer): string;
    function HasFilter: Boolean;
    function SelectedRow: Integer;
    property RowHeight: Integer read FRowHeight;
  end;

  TRtComboBox = class(TCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FOnChange: TNotifyEvent;
    FOnDropDown: TNotifyEvent;
    FDrop: TRtDropList;
    FDropClosedAt: QWord;
    FHot: Boolean;
    FStyle: TComboBoxStyle;
    procedure SetItemIndex(AValue: Integer);
    function GetItems: TStrings;
    function GetText: string;
    procedure ItemsChanged(Sender: TObject);
    procedure SelectIndex(AIndex: Integer);
    procedure DropClosed;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure DropDown;
    function PreferredHeight: Integer;
    property Items: TStrings read GetItems;
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property Text: string read GetText;
    // liste ouverte (nil sinon)
    property DropList: TRtDropList read FDrop;
    // compatibilite TComboBox: sans effet, la liste n'est jamais editable
    property Style: TComboBoxStyle read FStyle write FStyle;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnDropDown: TNotifyEvent read FOnDropDown write FOnDropDown;
  end;

implementation

uses
  Math, LCLIntf, uTheme, uUiKit;

{ TRtDropList }

constructor TRtDropList.CreateFor(ACombo: TRtComboBox);
var
  pf: TCustomForm;
  box: TPanel;
begin
  inherited CreateNew(ACombo);
  FCombo := ACombo;
  BorderStyle := bsNone;
  ShowInTaskBar := stNever;
  // au-dessus du dialogue (modal compris) qui porte la liste
  pf := GetParentForm(ACombo);
  if pf <> nil then
  begin
    PopupMode := pmExplicit;
    PopupParent := pf;
  end;
  Font.Assign(ACombo.Font);
  KeyPreview := True;
  OnKeyDown := @KeysDown;
  OnDeactivate := @FormDeactivate;
  // cadre d'un pixel: le fond du formulaire autour du panneau
  Color := clMenuSep;
  FFrame := TPanel.Create(Self);
  FFrame.Parent := Self;
  FFrame.Align := alClient;
  FFrame.BevelOuter := bvNone;
  FFrame.BorderSpacing.Around := 1;
  FFrame.ParentColor := False;
  FFrame.Color := clMenuPopupBg;
  FRowHeight := Max(FontTextHeight(Font) + 8, 20);
  if ACombo.Items.Count >= DROP_FILTER_MIN then
  begin
    // champ plat aux couleurs de l'editeur (la bordure native reste claire
    // en theme sombre)
    box := TPanel.Create(Self);
    box.Parent := FFrame;
    box.Align := alTop;
    box.BevelOuter := bvNone;
    box.BorderSpacing.Around := 4;
    box.Height := FontTextHeight(Font) + 10;
    box.ParentColor := False;
    box.Color := clEditorBg;
    FFilter := TEdit.Create(Self);
    FFilter.Parent := box;
    FFilter.Align := alClient;
    FFilter.BorderSpacing.Left := 6;
    FFilter.BorderSpacing.Top := 4;
    FFilter.BorderStyle := bsNone;
    FFilter.Color := clEditorBg;
    FFilter.Font.Assign(Font);
    FFilter.Font.Color := clEditorFg;
    FFilter.TextHint := 'Type to filter';
    FFilter.OnChange := @FilterChange;
  end;
  FList := TListBox.Create(Self);
  FList.Parent := FFrame;
  FList.Align := alClient;
  FList.BorderStyle := bsNone;
  FList.Style := lbOwnerDrawFixed;
  FList.ItemHeight := FRowHeight;
  FList.Color := clMenuPopupBg;
  FList.Font.Assign(Font);
  FList.OnDrawItem := @ListDrawItem;
  FList.OnMouseMove := @ListMouseMove;
  FList.OnMouseUp := @ListMouseUp;
  Refill;
end;

procedure TRtDropList.Refill;
var
  i, keep: Integer;
  f: string;
begin
  f := '';
  if FFilter <> nil then f := AnsiLowerCase(Trim(FFilter.Text));
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    SetLength(FMap, 0);
    SetLength(FRowObjs, 0);
    keep := -1;
    for i := 0 to FCombo.Items.Count - 1 do
      if (f = '') or (Pos(f, AnsiLowerCase(FCombo.Items[i])) > 0) then
      begin
        SetLength(FMap, Length(FMap) + 1);
        FMap[High(FMap)] := i;
        SetLength(FRowObjs, Length(FRowObjs) + 1);
        FRowObjs[High(FRowObjs)] := FCombo.Items.Objects[i];
        FList.Items.Add(FCombo.Items[i]);
        if i = FCombo.ItemIndex then keep := FList.Items.Count - 1;
      end;
  finally
    FList.Items.EndUpdate;
  end;
  // choix courant s'il est affiche, sinon la premiere ligne
  if keep < 0 then keep := 0;
  if FList.Items.Count > 0 then FList.ItemIndex := keep;
end;

procedure TRtDropList.Place;
var
  pt: TPoint;
  wa: TRect;
  rows, want, h, w, below, above, i, tw, filterH: Integer;
  bmp: Graphics.TBitmap;
begin
  pt := FCombo.ClientToScreen(Point(0, 0));
  wa := Screen.MonitorFromPoint(pt).WorkareaRect;
  rows := EnsureRange(FCombo.Items.Count, 1, DROP_MAX_ROWS);
  filterH := 0;
  if FFilter <> nil then filterH := FontTextHeight(Font) + 18;  // champ et ses marges
  want := rows * FRowHeight + filterH + 4;
  below := wa.Bottom - (pt.Y + FCombo.Height);
  above := pt.Y - wa.Top;
  // largeur du plus long libelle, au moins celle de la liste fermee
  tw := 0;
  bmp := Graphics.TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(Font);
    for i := 0 to FCombo.Items.Count - 1 do
      tw := Max(tw, bmp.Canvas.TextWidth(FCombo.Items[i]));
  finally
    bmp.Free;
  end;
  w := Min(Max(FCombo.Width, tw + 28 + 16 + GetSystemMetrics(SM_CXVSCROLL)), wa.Right - wa.Left);
  // en dessous s'il y a la place, sinon du cote le plus grand; jamais hors
  // de l'ecran (la liste defile)
  if (want <= below) or (below >= above) then
  begin
    h := Min(want, below);
    SetBounds(EnsureRange(pt.X, wa.Left, wa.Right - w), pt.Y + FCombo.Height, w, h);
  end
  else
  begin
    h := Min(want, above);
    SetBounds(EnsureRange(pt.X, wa.Left, wa.Right - w), pt.Y - h, w, h);
  end;
end;

procedure TRtDropList.ListDrawItem(Control: TWinControl; Index: Integer; ARect: TRect;
  State: TOwnerDrawState);
var
  c: TCanvas;
  ty: Integer;
begin
  c := FList.Canvas;
  c.Font.Assign(Font);
  if odSelected in State then c.Brush.Color := clMenuHover else c.Brush.Color := clMenuPopupBg;
  c.FillRect(ARect);
  c.Brush.Style := bsClear;
  c.Font.Color := clMenuText;
  ty := ARect.Top + (ARect.Bottom - ARect.Top - c.TextHeight('Ag')) div 2;
  // puce du choix courant, comme le menu qu'elle remplace
  if (Index >= 0) and (Index <= High(FMap)) and (FMap[Index] = FCombo.ItemIndex) then
    c.TextOut(ARect.Left + 10, ty, #$E2#$80#$A2);
  if (Index >= 0) and (Index < FList.Items.Count) then
    c.TextRect(Classes.Rect(ARect.Left + 28, ARect.Top, ARect.Right - 4, ARect.Bottom), ARect.Left + 28, ty,
      FList.Items[Index]);
  c.Brush.Style := bsSolid;
end;

procedure TRtDropList.ListMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  // survol: la ligne sous la souris est mise en valeur
  i := FList.ItemAtPos(Point(X, Y), True);
  if (i >= 0) and (i <> FList.ItemIndex) then FList.ItemIndex := i;
end;

procedure TRtDropList.ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  if Button <> mbLeft then Exit;
  i := FList.ItemAtPos(Point(X, Y), True);
  if i >= 0 then Choose(i);
end;

procedure TRtDropList.MoveBy(ADelta: Integer);
begin
  if FList.Items.Count = 0 then Exit;
  FList.ItemIndex := EnsureRange(FList.ItemIndex + ADelta, 0, FList.Items.Count - 1);
end;

procedure TRtDropList.KeysDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  page: Integer;
begin
  page := Max(1, FList.ClientHeight div FRowHeight - 1);
  case Key of
    VK_ESCAPE:
      begin
        CloseDrop;
        Key := 0;
      end;
    VK_RETURN:
      begin
        Choose(FList.ItemIndex);
        Key := 0;
      end;
    VK_DOWN: begin MoveBy(1); Key := 0; end;
    VK_UP: begin MoveBy(-1); Key := 0; end;
    VK_NEXT: begin MoveBy(page); Key := 0; end;
    VK_PRIOR: begin MoveBy(-page); Key := 0; end;
    VK_HOME:
      // dans le filtre, Debut et Fin restent ceux du texte
      if FFilter = nil then begin MoveBy(-FList.Items.Count); Key := 0; end;
    VK_END:
      if FFilter = nil then begin MoveBy(FList.Items.Count); Key := 0; end;
  end;
end;

procedure TRtDropList.FilterChange(Sender: TObject);
begin
  Refill;
end;

procedure TRtDropList.FormDeactivate(Sender: TObject);
begin
  // clic ailleurs: la liste se ferme sans choisir
  CloseDrop;
end;

procedure TRtDropList.Choose(ARow: Integer);
var
  combo: TRtComboBox;
  idx: Integer;
begin
  if FDone or (ARow < 0) or (ARow > High(FMap)) then Exit;
  combo := FCombo;
  idx := FMap[ARow];
  CloseDrop;
  combo.SelectIndex(idx);
  if combo.CanFocus then combo.SetFocus;
end;

procedure TRtDropList.ItemsUpdated;
var
  sel: string;
  obj: TObject;
  occ, cnt, i, match: Integer;
begin
  if FDone then Exit;
  // liste videe pendant l'ouverture: fermee sans choisir, une liste vide
  // n'offre aucun choix valable
  if FCombo.Items.Count = 0 then
  begin
    CloseDrop;
    Exit;
  end;
  // identite de la ligne surlignee AVANT la reconstruction: objet associe,
  // et rang parmi les doublons du meme libelle (le texte seul pourrait
  // designer un autre element apres un reordonnancement)
  sel := '';
  obj := nil;
  occ := 0;
  i := FList.ItemIndex;
  if (i >= 0) and (i < FList.Items.Count) then
  begin
    sel := FList.Items[i];
    if i <= High(FRowObjs) then obj := FRowObjs[i];
    for cnt := 0 to i - 1 do
      if FList.Items[cnt] = sel then Inc(occ);
  end;
  Refill;
  if sel <> '' then
  begin
    match := -1;
    if obj <> nil then
    begin
      // l'objet est l'identite: restauree seulement s'il est present une
      // fois exactement
      for i := 0 to High(FRowObjs) do
        if FRowObjs[i] = obj then
          if match < 0 then match := i
          else
          begin
            match := -1;
            Break;
          end;
    end
    else
    begin
      // sans objet: meme libelle, meme rang de doublon, sinon rien
      cnt := 0;
      for i := 0 to FList.Items.Count - 1 do
        if FList.Items[i] = sel then
        begin
          if cnt = occ then
          begin
            match := i;
            Break;
          end;
          Inc(cnt);
        end;
    end;
    if match >= 0 then FList.ItemIndex := match;
  end;
  Place;
end;

procedure TRtDropList.CloseDrop;
begin
  if FDone then Exit;
  FDone := True;
  FCombo.DropClosed;
  Hide;
  // liberee hors de ses propres gestionnaires
  Release;
end;

procedure TRtDropList.SetFilterText(const AText: string);
begin
  if FFilter = nil then Exit;
  FFilter.Text := AText;
  Refill;
end;

procedure TRtDropList.PressKey(AKey: Word);
var
  k: Word;
begin
  k := AKey;
  KeysDown(Self, k, []);
end;

function TRtDropList.VisibleCount: Integer;
begin
  Result := FList.Items.Count;
end;

function TRtDropList.VisibleItem(ARow: Integer): string;
begin
  Result := FList.Items[ARow];
end;

function TRtDropList.HasFilter: Boolean;
begin
  Result := FFilter <> nil;
end;

function TRtDropList.SelectedRow: Integer;
begin
  Result := FList.ItemIndex;
end;

{ TRtComboBox }

constructor TRtComboBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FStyle := csDropDownList;
  TabStop := True;
  Width := 120;
  Height := 26;
  ControlStyle := ControlStyle + [csOpaque];
end;

destructor TRtComboBox.Destroy;
begin
  if FDrop <> nil then
  begin
    FDrop.FDone := True;
    FDrop := nil;
  end;
  FItems.Free;
  inherited Destroy;
end;

function TRtComboBox.GetItems: TStrings;
begin
  Result := FItems;
end;

procedure TRtComboBox.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := -1;
  // liste ouverte: ses lignes et sa table d'index suivent les elements
  if FDrop <> nil then FDrop.ItemsUpdated;
  Invalidate;
end;

function TRtComboBox.GetText: string;
begin
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
    Result := FItems[FItemIndex]
  else
    Result := '';
end;

procedure TRtComboBox.SetItemIndex(AValue: Integer);
begin
  if (AValue < -1) or (AValue >= FItems.Count) then
    AValue := -1;
  if AValue = FItemIndex then Exit;
  FItemIndex := AValue;
  Invalidate;
end;

procedure TRtComboBox.SelectIndex(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) or (AIndex = FItemIndex) then Exit;
  FItemIndex := AIndex;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

function TRtComboBox.PreferredHeight: Integer;
var
  bmp: Graphics.TBitmap;
begin
  bmp := Graphics.TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(Font);
    Result := bmp.Canvas.TextHeight('Ag') + 10;
  finally
    bmp.Free;
  end;
end;

procedure TRtComboBox.Paint;
var
  r: TRect;
  cx, cy, ty: Integer;
  bg: TColor;
begin
  Canvas.Brush.Style := bsSolid;
  if Parent <> nil then
    Canvas.Brush.Color := Parent.Brush.Color
  else
    Canvas.Brush.Color := clAppBg;
  Canvas.FillRect(ClientRect);
  r := ClientRect;
  bg := clEditorBg;
  if FHot and Enabled then
    bg := BlendColor(clEditorBg, clAppFg, 92);
  Canvas.Brush.Color := bg;
  if Focused or (FDrop <> nil) then
    Canvas.Pen.Color := clAccent
  else
    Canvas.Pen.Color := BlendColor(clAppFg, clAppBg, 35);
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, 6, 6);
  Canvas.Font.Assign(Font);
  if Enabled then
    Canvas.Font.Color := clEditorFg
  else
    Canvas.Font.Color := BlendColor(clEditorFg, clEditorBg, 45);
  Canvas.Brush.Style := bsClear;
  ty := (ClientHeight - Canvas.TextHeight('Ag')) div 2;
  Canvas.TextRect(Classes.Rect(r.Left + 8, r.Top, r.Right - 22, r.Bottom), r.Left + 8, ty, GetText);
  // chevron
  cx := r.Right - 12;
  cy := ClientHeight div 2;
  Canvas.Pen.Color := Canvas.Font.Color;
  Canvas.Pen.Width := 2;
  Canvas.Line(cx - 4, cy - 2, cx, cy + 2);
  Canvas.Line(cx, cy + 2, cx + 4, cy - 2);
  Canvas.Pen.Width := 1;
end;

procedure TRtComboBox.DropDown;
begin
  if not Enabled or (FDrop <> nil) then Exit;
  // clic sur la liste fermee a l'instant par ce meme clic (perte du focus
  // de la liste ouverte): bascule, pas de reouverture
  if (FDropClosedAt <> 0) and (GetTickCount64 - FDropClosedAt < 250) then Exit;
  if Assigned(FOnDropDown) then FOnDropDown(Self);
  if FItems.Count = 0 then Exit;
  FDrop := TRtDropList.CreateFor(Self);
  FDrop.Place;
  FDrop.Show;
  {$IFDEF WINDOWS}
  ApplyNativeDarkMode(FDrop.FList);
  {$ENDIF}
  if FDrop.FFilter <> nil then FDrop.FFilter.SetFocus else FDrop.FList.SetFocus;
  Invalidate;
end;

procedure TRtComboBox.DropClosed;
begin
  FDrop := nil;
  FDropClosedAt := GetTickCount64;
  Invalidate;
end;

procedure TRtComboBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  if Button = mbLeft then DropDown;
end;

procedure TRtComboBox.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TRtComboBox.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TRtComboBox.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_UP:
      begin
        SelectIndex(FItemIndex - 1);
        Key := 0;
      end;
    VK_DOWN:
      begin
        if ssAlt in Shift then DropDown else SelectIndex(FItemIndex + 1);
        Key := 0;
      end;
    VK_SPACE, VK_F4:
      begin
        DropDown;
        Key := 0;
      end;
  end;
end;

procedure TRtComboBox.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TRtComboBox.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

end.
