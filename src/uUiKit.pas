// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uUiKit;

{$mode objfpc}{$H+}

// Construction par code des controles (pas de .lfm, comme dans RottenSSHrimp)
// et dialogue de base. Comme dans RottenSSHrimp, la coque et ses onglets sont
// themes, et les dialogues aussi (TRtDialog.ShellThemed, actif par defaut):
// couleurs, polices, onglets dessines, themes clairs comme sombres.
// Tout dialogue d'operation affiche le serveur cible en tete; les
// confirmations d'ecriture affichent DN, type d'operation et nombre d'entrees.

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, ExtCtrls, Graphics, ComCtrls, Grids,
  Buttons, LCLType, uTheme, uRtCheck;

type
  // En-tete d'onglets dessine aux couleurs du theme, pour un TPageControl sans
  // onglets natifs (les onglets Win32 ignorent les couleurs).
  TRtPageHeader = class(TCustomControl)
  private
    FPages: TPageControl;
    function TabRect(AIndex: Integer): TRect;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Pages: TPageControl read FPages write FPages;
  end;

  TUiState = (usOk, usWarning, usError, usMuted);

  // Hote qui deborde le TPageControl de quelques pixels: sans onglets, Win32
  // dessine encore un cadre clair que les couleurs du theme ne couvrent pas
  TBorderlessHost = class(TCustomPanel)
  protected
    procedure Resize; override;
  end;

const
  // Tag d'un controle dont la police (taille, graisse) est choisie par son createur
  TAG_KEEP_FONT = 7701;
  // Tag d'une ligne "libelle: champ" (MakeFieldRow): largeur du libelle ajustee
  TAG_FIELD_ROW = 7702;
  // grille d'un dialogue entouree du cadre arrondi du theme (StyleGrid)
  TAG_FRAMED_GRID = 7703;

type

  TRtDialog = class(TForm)
  private
    FHeader: TPanel;
    FHeaderLabel: TLabel;
    FBadgeLabel: TLabel;
    FButtons: TPanel;
    FBody: TPanel;
    FShellThemed: Boolean;
    FFitOnShow: Boolean;
    FHeaderIcon: TGraphicControl;
    FTarget: string;
    procedure RefreshHeader;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoShow; override;
    // couleurs et polices du theme de la coque (ShellThemed); appele par
    // ApplyTheme puis a l'affichage, quand les controles natifs ont leur
    // handle (cases a cocher, listes). Une surcharge recolore ensuite ses
    // libelles d'etat
    procedure ApplyShellColors; virtual;
  public
    constructor CreateDialog(AOwner: TComponent; const ACaption: string; AWidth, AHeight: Integer);
    procedure SetTarget(const AServer, ABadge: string);
    // Icone Tabler de l'en-tete: le bandeau s'affiche avec elle, suivie du
    // serveur cible s'il y en a un, sinon du titre du dialogue
    procedure SetIcon(const AId: string);
    function HeaderIconId: string;
    function HeaderText: string;
    function AddButton(const ACaption: string; AResult: TModalResult; ADefault: Boolean = False;
      ACancel: Boolean = False): TButton;
    procedure ApplyTheme; virtual;
    // Hauteur ajustee au contenu du corps (controles alTop), bornee a la
    // zone de travail de l'ecran; appele aussi a l'affichage si FitOnShow
    procedure FitHeightToContent;
    property Body: TPanel read FBody;
    property ButtonBar: TPanel read FButtons;
    // le dialogue suit le theme de la coque au lieu des controles du systeme
    property ShellThemed: Boolean read FShellThemed write FShellThemed;
    // la hauteur suit le contenu (polices du theme, libelles sur deux lignes)
    property FitOnShow: Boolean read FFitOnShow write FFitOnShow;
  end;

function MakePanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer = 0): TPanel;
function MakeLabel(AParent: TWinControl; const ACaption: string; AAlign: TAlign = alTop): TLabel;
function MakeEdit(AParent: TWinControl; AAlign: TAlign = alTop): TEdit;
function MakeCheck(AParent: TWinControl; const ACaption: string; AAlign: TAlign = alTop): TRtCheckBox;
function MakeCombo(AParent: TWinControl; const AItems: array of string; AAlign: TAlign = alTop): TComboBox;
function MakeButton(AParent: TWinControl; const ACaption: string; AOnClick: TNotifyEvent;
  AAlign: TAlign = alLeft): TButton;
function MakeMemo(AParent: TWinControl; AAlign: TAlign = alClient): TMemo;
// Ligne "libelle: champ" empilee en haut d'un conteneur. ALabelWidth est un
// minimum: FitFieldLabels elargit les libelles d'un meme conteneur a la
// largeur du plus long, dans la police reelle
function MakeFieldRow(AParent: TWinControl; const ACaption: string; ALabelWidth: Integer = 150): TPanel;
// Aligne les libelles des lignes de champ de chaque conteneur sous ARoot: meme
// largeur, celle du texte le plus long; au-dela d'AMaxWidth, le libelle passe
// sur deux lignes au lieu d'etre tronque
procedure FitFieldLabels(ARoot: TWinControl; AMaxWidth: Integer);
procedure ThemeControlTree(AControl: TControl);
// Polices embarquees pour ce que l'application ne cree pas elle-meme: aides
// (info-bulles) de tous les controles. A appeler a chaque theme
procedure ApplyGlobalFonts;
procedure StackTop(AControl: TControl);
// alLeft: ordre de creation de gauche a droite; alRight: le premier cree a droite
procedure ArrangeByCreation(AParent: TWinControl);
function MonoFontName: string;
// Zone de texte: police de l'interface, cadre du theme (voir ThemeControlTree)
procedure StyleMemo(AMemo: TCustomMemo);
// TPageControl de la coque avec en-tete dessine
function MakePages(AParent: TWinControl): TPageControl;
// Nouvel onglet et son panneau de contenu aux couleurs du theme (le fond
// natif d'un onglet reste blanc); le contenu se construit dans le panneau,
// l'onglet est son Parent
function AddPageBody(APages: TPageControl; const ACaption: string): TPanel;
function FontTextHeight(AFont: TFont): Integer;
// Hauteur des libelles empiles (alTop) de AParent, chacun dans sa police,
// marges comprises: un bandeau dimensionne ainsi n'est jamais coupe par une
// police plus grande, contrairement a une hauteur fixe
function StackedLabelsHeight(AParent: TWinControl): Integer;
// Place un TPageControl sans onglets dans un hote qui masque son cadre natif
procedure HostWithoutBorder(APages: TPageControl);
procedure ThemeSplitter(ASplitter: TSplitter);
// Barres de defilement et en-tetes natifs sombres ou clairs selon le fond du
// theme (Windows 10 1809+); sans effet ailleurs
procedure ApplyNativeDarkMode(AControl: TWinControl);
procedure SelectPage(APages: TPageControl; AIndex: Integer);
// Couleur d'etat des dialogues (themes comme la coque: ShellStateColor)
function DialogStateColor(AState: TUiState): TColor;
// Couleur d'etat sur le fond de la coque (theme)
function ShellStateColor(AState: TUiState): TColor;

implementation

uses
  {$IFDEF WINDOWS}Windows, UxTheme,{$ENDIF} uFontEmbed, uRtCombo, uIcons;

const
  // icone d'en-tete de dialogue (taille logique)
  DIALOG_ICON = 20;

function DialogStateColor(AState: TUiState): TColor;
begin
  // les dialogues suivent le theme de la coque: memes couleurs d'etat
  Result := ShellStateColor(AState);
end;

// Couleur d'etat posee sur un libelle: le theme la conserve
function IsStateColor(AColor: TColor): Boolean;
begin
  Result := (AColor = ShellStateColor(usOk)) or (AColor = ShellStateColor(usWarning)) or
    (AColor = ShellStateColor(usError)) or (AColor = ShellStateColor(usMuted));
end;

function ShellStateColor(AState: TUiState): TColor;
begin
  case AState of
    usOk: Result := clDiffEqual;
    usWarning: Result := clDiffWarning;
    usError: Result := clDiffAbsent;
  else
    Result := clStatusText;
  end;
end;

{ TRtPageHeader }

constructor TRtPageHeader.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Height := 28;
  ControlStyle := ControlStyle + [csOpaque];
end;

function TRtPageHeader.TabRect(AIndex: Integer): TRect;
var
  i, x: Integer;
begin
  Canvas.Font := Font;
  x := 0;
  for i := 0 to AIndex - 1 do
    if FPages.Pages[i].TabVisible then
      Inc(x, Canvas.TextWidth(FPages.Pages[i].Caption) + 28);
  Result := Classes.Rect(x, 0, x + Canvas.TextWidth(FPages.Pages[AIndex].Caption) + 28, ClientHeight);
end;

procedure TRtPageHeader.Paint;
var
  i: Integer;
  r: TRect;
begin
  Canvas.Brush.Color := clTabStrip;
  Canvas.FillRect(ClientRect);
  if FPages = nil then Exit;
  Canvas.Font := Font;
  for i := 0 to FPages.PageCount - 1 do
  begin
    if not FPages.Pages[i].TabVisible then Continue;
    r := TabRect(i);
    if i = FPages.ActivePageIndex then
    begin
      Canvas.Brush.Color := clTabActive;
      Canvas.FillRect(r);
      Canvas.Brush.Color := clAccent;
      Canvas.FillRect(Classes.Rect(r.Left, r.Bottom - 2, r.Right, r.Bottom));
      Canvas.Font.Color := clTabActiveText;
    end
    else
      Canvas.Font.Color := clTabInactiveText;
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(r.Left + 14, (ClientHeight - Canvas.TextHeight('Ag')) div 2,
      FPages.Pages[i].Caption);
    Canvas.Brush.Style := bsSolid;
  end;
end;

procedure TRtPageHeader.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
  r: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if FPages = nil then Exit;
  for i := 0 to FPages.PageCount - 1 do
  begin
    if not FPages.Pages[i].TabVisible then Continue;
    r := TabRect(i);
    if (X >= r.Left) and (X < r.Right) then
    begin
      SelectPage(FPages, i);
      if Assigned(FPages.OnChange) then FPages.OnChange(FPages);
      Exit;
    end;
  end;
end;

function MakePages(AParent: TWinControl): TPageControl;
var
  hdr: TRtPageHeader;
begin
  hdr := TRtPageHeader.Create(AParent);
  hdr.Parent := AParent;
  StackTop(hdr);
  hdr.Align := alTop;
  Result := TPageControl.Create(AParent);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ShowTabs := False;
  HostWithoutBorder(Result);
  hdr.Pages := Result;
  // l'en-tete se retrouve par le TPageControl: meme parent, Tag pointe dessus
  Result.Tag := PtrInt(hdr);
end;

function AddPageBody(APages: TPageControl; const ACaption: string): TPanel;
var
  sheet: TTabSheet;
begin
  sheet := APages.AddTabSheet;
  sheet.Caption := ACaption;
  // Windows peint le fond d'un onglet avec son theme (blanc), sans tenir
  // compte de sa couleur: un panneau colore porte le contenu
  Result := TPanel.Create(sheet);
  Result.Parent := sheet;
  Result.Align := alClient;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.ParentColor := False;
  Result.Color := clAppBg;
end;

procedure SelectPage(APages: TPageControl; AIndex: Integer);
begin
  APages.ActivePageIndex := AIndex;
  if APages.Tag <> 0 then
    TRtPageHeader(Pointer(APages.Tag)).Invalidate;
end;

var
  GStackCounter: Integer = 0;

procedure StackTop(AControl: TControl);
var
  i, bottom: Integer;
  c: TControl;
begin
  // alTop empile dans l'ordre des Top croissants: le nouveau controle sous
  // ses freres deja empiles = ordre de creation. Borne par le contenu du
  // parent: un compteur global depassait a la longue la limite SmallInt
  // des positions Windows (WM_MOVE)
  if AControl.Parent = nil then
  begin
    GStackCounter := (GStackCounter + 1) mod 7000;
    AControl.Top := GStackCounter * 4;
    Exit;
  end;
  bottom := 0;
  for i := 0 to AControl.Parent.ControlCount - 1 do
  begin
    c := AControl.Parent.Controls[i];
    if (c <> AControl) and (c.Align = alTop) and (c.Top + c.Height > bottom) then
      bottom := c.Top + c.Height;
  end;
  AControl.Top := bottom + 1;
end;

const
  // au-dela de toute largeur de fenetre, sous la limite SmallInt de Windows
  RIGHT_ORDER_BASE = 30000;

procedure ArrangeByCreation(AParent: TWinControl);
var
  i, nl, nr: Integer;
  c: TControl;
begin
  if AParent = nil then Exit;
  nl := 0;
  nr := 0;
  AParent.DisableAlign;
  try
    for i := 0 to AParent.ControlCount - 1 do
    begin
      c := AParent.Controls[i];
      if c.Align = alLeft then
      begin
        c.Left := nl;
        Inc(nl, c.Width + 1);
      end
      else if c.Align = alRight then
      begin
        // position provisoire (seul l'ordre compte, l'alignement la corrige),
        // mais transmise a Windows si le handle existe (changement de theme):
        // elle doit tenir dans un SmallInt (WM_MOVE), sinon debordement
        Inc(nr, c.Width + 1);
        c.Left := RIGHT_ORDER_BASE - nr;
      end;
      if c is TWinControl then
        ArrangeByCreation(TWinControl(c));
    end;
  finally
    AParent.EnableAlign;
  end;
end;

type
  // cadre des champs de saisie de la coque, dessine par le panneau parent
  TFieldPainter = class
    procedure PanelPaint(Sender: TObject);
    procedure SplitterPaint(Sender: TObject);
    procedure SplitterCanResize(Sender: TObject; var NewSize: Integer; var Accept: Boolean);
    procedure SplitterMoved(Sender: TObject);
  end;

var
  GFieldPainter: TFieldPainter = nil;

const
  PAGE_BORDER_CLIP = 4;
  // marge d'une zone de texte dans son cadre arrondi
  MEMO_FRAME = 4;

procedure TBorderlessHost.Resize;
begin
  inherited Resize;
  if ControlCount > 0 then
    Controls[0].SetBounds(-PAGE_BORDER_CLIP, -PAGE_BORDER_CLIP,
      ClientWidth + 2 * PAGE_BORDER_CLIP, ClientHeight + 2 * PAGE_BORDER_CLIP);
end;

procedure HostWithoutBorder(APages: TPageControl);
var
  host: TBorderlessHost;
begin
  host := TBorderlessHost.Create(APages.Owner);
  host.Parent := APages.Parent;
  host.BevelOuter := bvNone;
  host.Caption := '';
  host.Align := APages.Align;
  host.ParentColor := True;
  APages.Align := alNone;
  APages.Parent := host;
  host.Resize;
end;

function FontTextHeight(AFont: TFont): Integer;
var
  bmp: Graphics.TBitmap;
begin
  bmp := Graphics.TBitmap.Create;
  try
    bmp.Canvas.Font.Assign(AFont);
    Result := bmp.Canvas.TextHeight('Ag');
  finally
    bmp.Free;
  end;
end;

function StackedLabelsHeight(AParent: TWinControl): Integer;
var
  i: Integer;
  l: TLabel;
begin
  Result := 0;
  for i := 0 to AParent.ControlCount - 1 do
    if (AParent.Controls[i] is TLabel) and AParent.Controls[i].Visible then
    begin
      l := TLabel(AParent.Controls[i]);
      Inc(Result, FontTextHeight(l.Font) + l.BorderSpacing.Top + l.BorderSpacing.Bottom +
        2 * l.BorderSpacing.Around);
    end;
end;

function IsShellField(AControl: TControl): Boolean;
begin
  Result := (AControl.ClassType = TEdit) and (AControl.Parent is TCustomPanel) and
    (AControl.Align in [alLeft, alRight, alClient]);
end;

function IsFramedMemo(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomMemo) and (AControl.Parent is TCustomPanel) and
    (TCustomMemo(AControl).BorderStyle = bsNone);
end;

procedure TFieldPainter.PanelPaint(Sender: TObject);
var
  p: TCustomPanel;
  i: Integer;
  c: TControl;
  r: TRect;
begin
  p := TCustomPanel(Sender);
  for i := 0 to p.ControlCount - 1 do
  begin
    c := p.Controls[i];
    // zone de texte ou grille: meme cadre arrondi que les champs, a 4 pixels
    if (IsFramedMemo(c) or ((c is TCustomGrid) and (c.Tag = TAG_FRAMED_GRID))) and c.Visible then
    begin
      r := Classes.Rect(c.Left - MEMO_FRAME, c.Top - MEMO_FRAME, c.Left + c.Width + MEMO_FRAME,
        c.Top + c.Height + MEMO_FRAME);
      p.Canvas.Brush.Style := bsSolid;
      p.Canvas.Brush.Color := TWinControl(c).Color;
      p.Canvas.Pen.Color := BlendColor(clAppFg, clAppBg, 30);
      p.Canvas.Pen.Width := 1;
      p.Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, 8, 8);
      Continue;
    end;
    if not (IsShellField(c) and c.Visible and (TEdit(c).BorderStyle = bsNone)) then Continue;
    r := Classes.Rect(c.Left - 6, c.Top - 4, c.Left + c.Width + 6, c.Top + c.Height + 4);
    p.Canvas.Brush.Style := bsSolid;
    p.Canvas.Brush.Color := TEdit(c).Color;
    p.Canvas.Pen.Color := BlendColor(clAppFg, clAppBg, 35);
    p.Canvas.Pen.Width := 1;
    p.Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, 6, 6);
  end;
end;

{$IFDEF WINDOWS}
// Windows 10 1809+: themes systeme sombres des listes (en-tete de colonnes,
// barres de defilement). Sans effet sur les versions qui ne les connaissent pas.
procedure ApplyNativeDarkMode(AControl: TWinControl);
const
  LVM_GETHEADER = $1000 + 31;
var
  dark: Boolean;
  hdr: HWND;
begin
  if not AControl.HandleAllocated then
  begin
    if (AControl.Parent = nil) or not AControl.Parent.HandleAllocated then Exit;
    AControl.HandleNeeded;
  end;
  dark := IsDarkColor(clAppBg);
  if dark then
    SetWindowTheme(AControl.Handle, 'DarkMode_Explorer', nil)
  else
    SetWindowTheme(AControl.Handle, 'Explorer', nil);
  if AControl is TCustomListView then
  begin
    hdr := HWND(SendMessage(AControl.Handle, LVM_GETHEADER, 0, 0));
    if hdr <> 0 then
    begin
      if dark then
        SetWindowTheme(hdr, 'DarkMode_ItemsView', nil)
      else
        SetWindowTheme(hdr, 'ItemsView', nil);
      InvalidateRect(hdr, nil, True);
    end;
  end;
end;
{$ELSE}
procedure ApplyNativeDarkMode(AControl: TWinControl);
begin
end;
{$ENDIF}

// Separateur: sans OnPaint, la LCL dessine le motif clair du systeme
// Tout le conteneur du separateur, enfants compris, est a redessiner: les
// controles dessines par l'application (arbre, en-tetes d'onglets, grille)
// ne repeignent pas d'eux-memes la zone gagnee pendant un glissement, d'ou
// des restes de l'ancienne disposition
procedure RepaintContainer(AControl: TWinControl);
{$IFNDEF WINDOWS}
var
  i: Integer;
{$ENDIF}
begin
  if (AControl = nil) or not AControl.HandleAllocated then Exit;
  {$IFDEF WINDOWS}
  RedrawWindow(AControl.Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN);
  {$ELSE}
  AControl.Invalidate;
  for i := 0 to AControl.ControlCount - 1 do
    if AControl.Controls[i] is TWinControl then
      RepaintContainer(TWinControl(AControl.Controls[i]))
    else
      AControl.Controls[i].Invalidate;
  {$ENDIF}
end;

procedure TFieldPainter.SplitterCanResize(Sender: TObject; var NewSize: Integer;
  var Accept: Boolean);
begin
  // appele juste avant chaque redimensionnement du glissement: le dessin
  // suivant se fait sur la nouvelle disposition, zone entiere effacee
  RepaintContainer(TSplitter(Sender).Parent);
end;

procedure TFieldPainter.SplitterMoved(Sender: TObject);
begin
  RepaintContainer(TSplitter(Sender).Parent);
  TSplitter(Sender).Parent.Update;
end;

procedure TFieldPainter.SplitterPaint(Sender: TObject);
var
  sp: TSplitter;
  i, c: Integer;
begin
  sp := TSplitter(Sender);
  sp.Canvas.Brush.Color := clBorder;
  sp.Canvas.FillRect(sp.ClientRect);
  sp.Canvas.Brush.Color := BlendColor(clAppFg, clBorder, 40);
  if sp.Align in [alLeft, alRight] then
  begin
    c := sp.ClientHeight div 2;
    for i := -3 to 3 do
      sp.Canvas.FillRect(Classes.Rect(sp.ClientWidth div 2 - 1, c + i * 4, sp.ClientWidth div 2 + 1, c + i * 4 + 2));
  end
  else
  begin
    c := sp.ClientWidth div 2;
    for i := -3 to 3 do
      sp.Canvas.FillRect(Classes.Rect(c + i * 4, sp.ClientHeight div 2 - 1, c + i * 4 + 2, sp.ClientHeight div 2 + 1));
  end;
end;

procedure ThemeSplitter(ASplitter: TSplitter);
begin
  if GFieldPainter = nil then
    GFieldPainter := TFieldPainter.Create;
  ASplitter.Color := clBorder;
  ASplitter.OnPaint := @GFieldPainter.SplitterPaint;
  ASplitter.OnCanResize := @GFieldPainter.SplitterCanResize;
  ASplitter.OnMoved := @GFieldPainter.SplitterMoved;
  ASplitter.Invalidate;
end;

// Champ de la coque: sans bordure native (blanche sur fond sombre), texte
// centre verticalement, cadre dessine par le panneau
procedure StyleShellField(AEdit: TEdit);
var
  p: TCustomPanel;
  eh, rowH, top: Integer;
begin
  p := TCustomPanel(AEdit.Parent);
  AEdit.BorderStyle := bsNone;
  eh := FontTextHeight(AEdit.Font) + 2;
  if (p.Align = alTop) and (p.Height < eh + 14) then
    p.Height := eh + 14;
  rowH := p.ClientHeight;
  top := (rowH - eh) div 2;
  if top < 4 then top := 4;
  AEdit.BorderSpacing.Around := 0;
  AEdit.BorderSpacing.Left := 10;
  AEdit.BorderSpacing.Right := 10;
  AEdit.BorderSpacing.Top := top;
  AEdit.BorderSpacing.Bottom := rowH - eh - top;
  if GFieldPainter = nil then
    GFieldPainter := TFieldPainter.Create;
  TPanel(p).OnPaint := @GFieldPainter.PanelPaint;
  p.Invalidate;
end;

// Controle aligne a gauche ou a droite dans une ligne: centre verticalement
// Zone de texte (TMemo): police et taille de l'interface (pas celles de
// l'editeur LDIF), sans bordure native (claire sur fond sombre): le panneau
// parent dessine un cadre arrondi comme celui des champs. Un parent qui
// n'est pas un panneau garde la bordure native, au theme sombre du systeme.
procedure StyleMemo(AMemo: TCustomMemo);
var
  p: TPanel;
  m: TMethod;
begin
  if RSUiFontName <> '' then AMemo.Font.Name := RSUiFontName;
  AMemo.Font.Size := RSUiFontSize;
  if AMemo.Parent is TCustomPanel then
  begin
    p := TPanel(AMemo.Parent);
    m := TMethod(p.OnPaint);
    if GFieldPainter = nil then
      GFieldPainter := TFieldPainter.Create;
    // un panneau qui dessine deja autre chose garde son dessin et le memo
    // sa bordure
    if (m.Code = nil) or (m.Data = Pointer(GFieldPainter)) then
    begin
      if AMemo.BorderStyle <> bsNone then AMemo.BorderStyle := bsNone;
      if AMemo.BorderSpacing.Around < MEMO_FRAME + 2 then
        AMemo.BorderSpacing.Around := MEMO_FRAME + 2;
      p.OnPaint := @GFieldPainter.PanelPaint;
      p.Invalidate;
    end;
  end;
  {$IFDEF WINDOWS}
  // barres de defilement (et bordure native restante) au theme du systeme
  if AMemo.HandleAllocated then ApplyNativeDarkMode(AMemo);
  {$ENDIF}
end;

// Grille (liste) d'un dialogue posee dans un panneau: sans bordure, dans le
// cadre arrondi du theme, comme les zones de texte. Les vues principales
// (onglets) gardent leurs grilles bord a bord.
procedure StyleGrid(AGrid: TCustomGrid);
var
  p: TPanel;
  m: TMethod;
begin
  if not (AGrid.Parent is TCustomPanel) then Exit;
  if not (GetParentForm(AGrid) is TRtDialog) then Exit;
  if (AGrid.Tag <> 0) and (AGrid.Tag <> TAG_FRAMED_GRID) then Exit;
  p := TPanel(AGrid.Parent);
  m := TMethod(p.OnPaint);
  if GFieldPainter = nil then
    GFieldPainter := TFieldPainter.Create;
  if (m.Code <> nil) and (m.Data <> Pointer(GFieldPainter)) then Exit;
  AGrid.Tag := TAG_FRAMED_GRID;
  if AGrid is TStringGrid then TStringGrid(AGrid).BorderStyle := bsNone
  else if AGrid is TDrawGrid then TDrawGrid(AGrid).BorderStyle := bsNone;
  if AGrid.BorderSpacing.Around < MEMO_FRAME + 2 then
    AGrid.BorderSpacing.Around := MEMO_FRAME + 2;
  p.OnPaint := @GFieldPainter.PanelPaint;
  p.Invalidate;
end;

procedure CenterInRow(AControl: TControl; AHeight: Integer);
var
  rowH, top: Integer;
begin
  rowH := AControl.Parent.ClientHeight;
  top := (rowH - AHeight) div 2;
  if top < 1 then top := 1;
  AControl.BorderSpacing.Top := top;
  AControl.BorderSpacing.Bottom := rowH - AHeight - top;
  if AControl.BorderSpacing.Bottom < 0 then AControl.BorderSpacing.Bottom := 0;
end;

function MonoFontName: string;
begin
  Result := RSEditorFontName;
end;

function MakePanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer): TPanel;
begin
  Result := TPanel.Create(AParent);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  if AAlign = alTop then StackTop(Result);
  Result.Align := AAlign;
  if ASize > 0 then
    case AAlign of
      alTop, alBottom: Result.Height := ASize;
      alLeft, alRight: Result.Width := ASize;
    end;
  Result.ParentColor := True;
end;

function MakeLabel(AParent: TWinControl; const ACaption: string; AAlign: TAlign): TLabel;
begin
  Result := TLabel.Create(AParent);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  if AAlign = alTop then StackTop(Result);
  Result.Align := AAlign;
  Result.BorderSpacing.Around := 4;
  Result.WordWrap := AAlign in [alTop, alBottom, alClient];
end;

function MakeEdit(AParent: TWinControl; AAlign: TAlign): TEdit;
begin
  Result := TEdit.Create(AParent);
  Result.Parent := AParent;
  if AAlign = alTop then StackTop(Result);
  Result.Align := AAlign;
  Result.BorderSpacing.Around := 2;
end;

function MakeCheck(AParent: TWinControl; const ACaption: string; AAlign: TAlign): TRtCheckBox;
begin
  Result := TRtCheckBox.Create(AParent);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  if AAlign = alTop then StackTop(Result);
  Result.Align := AAlign;
  Result.BorderSpacing.Around := 3;
end;

function MakeCombo(AParent: TWinControl; const AItems: array of string; AAlign: TAlign): TComboBox;
var
  i: Integer;
begin
  Result := TComboBox.Create(AParent);
  Result.Parent := AParent;
  if AAlign = alTop then StackTop(Result);
  Result.Align := AAlign;
  Result.Style := csDropDownList;
  Result.BorderSpacing.Around := 2;
  for i := 0 to High(AItems) do
    Result.Items.Add(AItems[i]);
  if Result.Items.Count > 0 then
    Result.ItemIndex := 0;
end;

function MakeButton(AParent: TWinControl; const ACaption: string; AOnClick: TNotifyEvent;
  AAlign: TAlign): TButton;
begin
  Result := TButton.Create(AParent);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  Result.Align := AAlign;
  Result.BorderSpacing.Around := 3;
  Result.AutoSize := True;
  Result.Constraints.MinWidth := 80;
end;

function MakeMemo(AParent: TWinControl; AAlign: TAlign): TMemo;
begin
  Result := TMemo.Create(AParent);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.ScrollBars := ssAutoBoth;
  Result.WordWrap := False;
  Result.Color := clEditorBg;
  Result.Font.Color := clEditorFg;
  StyleMemo(Result);
end;

function MakeFieldRow(AParent: TWinControl; const ACaption: string; ALabelWidth: Integer): TPanel;
var
  lbl: TLabel;
begin
  Result := MakePanel(AParent, alTop, 30);
  Result.BorderSpacing.Top := 1;
  Result.Tag := TAG_FIELD_ROW;
  lbl := TLabel.Create(Result);
  lbl.Parent := Result;
  lbl.Caption := ACaption;
  lbl.Align := alLeft;
  lbl.Width := ALabelWidth;
  lbl.AutoSize := False;
  lbl.Layout := tlCenter;
  lbl.BorderSpacing.Left := 6;
end;

function RowLabel(ARow: TWinControl): TLabel;
var
  i: Integer;
begin
  for i := 0 to ARow.ControlCount - 1 do
    if ARow.Controls[i] is TLabel then Exit(TLabel(ARow.Controls[i]));
  Result := nil;
end;

procedure FitFieldLabels(ARoot: TWinControl; AMaxWidth: Integer);
var
  bmp: Graphics.TBitmap;

  procedure FitContainer(AContainer: TWinControl);
  var
    i, w, maxW, lines: Integer;
    row: TWinControl;
    lbl: TLabel;
  begin
    maxW := 0;
    for i := 0 to AContainer.ControlCount - 1 do
      if (AContainer.Controls[i].Tag = TAG_FIELD_ROW) and (AContainer.Controls[i] is TWinControl) then
      begin
        lbl := RowLabel(TWinControl(AContainer.Controls[i]));
        if lbl = nil then Continue;
        bmp.Canvas.Font.Assign(lbl.Font);
        w := bmp.Canvas.TextWidth(lbl.Caption) + lbl.BorderSpacing.Left + 12;
        if w > maxW then maxW := w;
        if lbl.Width > maxW then maxW := lbl.Width;
      end;
    if maxW = 0 then Exit;
    if maxW > AMaxWidth then maxW := AMaxWidth;
    for i := 0 to AContainer.ControlCount - 1 do
      if (AContainer.Controls[i].Tag = TAG_FIELD_ROW) and (AContainer.Controls[i] is TWinControl) then
      begin
        row := TWinControl(AContainer.Controls[i]);
        lbl := RowLabel(row);
        if lbl = nil then Continue;
        lbl.Width := maxW;
        bmp.Canvas.Font.Assign(lbl.Font);
        w := bmp.Canvas.TextWidth(lbl.Caption) + lbl.BorderSpacing.Left + 12;
        if w > maxW then
        begin
          // libelle trop long: deux lignes, jamais un texte coupe
          lbl.WordWrap := True;
          lines := (w + maxW - 1) div maxW;
          row.Height := lines * (bmp.Canvas.TextHeight('Ag') + 2) + 8;
        end;
      end;
  end;

  procedure Walk(AControl: TWinControl);
  var
    i: Integer;
  begin
    FitContainer(AControl);
    for i := 0 to AControl.ControlCount - 1 do
      if (AControl.Controls[i] is TWinControl) and (AControl.Controls[i].Tag <> TAG_FIELD_ROW) then
        Walk(TWinControl(AControl.Controls[i]));
  end;

begin
  bmp := Graphics.TBitmap.Create;
  try
    Walk(ARoot);
  finally
    bmp.Free;
  end;
end;

procedure ApplyGlobalFonts;
begin
  if RSUiFontName <> '' then Screen.HintFont.Name := RSUiFontName;
  if RSUiFontSize > 0 then Screen.HintFont.Size := RSUiFontSize;
end;

procedure ThemeControlTree(AControl: TControl);
var
  i: Integer;
  wc: TWinControl;
begin
  if AControl = nil then Exit;
  // liste deroulante native: fond clair impose par Windows; la variante
  // editable en lecture seule respecte les couleurs du theme
  if (AControl is TComboBox) and (TComboBox(AControl).Style = csDropDownList) then
  begin
    TComboBox(AControl).Style := csDropDown;
    TComboBox(AControl).ReadOnly := True;
  end;
  if AControl is TCustomMemo then
    // zones de texte: police de l'interface, cadre du theme
    StyleMemo(TCustomMemo(AControl))
  else if AControl.Tag <> TAG_KEEP_FONT then
  begin
    if RSUiFontName <> '' then
      AControl.Font.Name := RSUiFontName;
    AControl.Font.Size := RSUiFontSize;
  end;
  if IsShellField(AControl) then
    StyleShellField(TEdit(AControl))
  else if (AControl is TRtComboBox) and (AControl.Parent <> nil) then
  begin
    CenterInRow(AControl, TRtComboBox(AControl).PreferredHeight);
    AControl.Invalidate;
  end
  else if AControl is TSplitter then
    ThemeSplitter(TSplitter(AControl))
  else if (AControl.Parent is TCustomPanel) and (AControl.Align in [alLeft, alRight]) then
  begin
    if AControl is TComboBox then
      CenterInRow(AControl, AControl.Height)
    else if AControl is TCustomButton then
    begin
      // Around s'ajoute aux marges haute et basse posees par CenterInRow:
      // il ecrasait le bouton de 2 x Around. Garde a gauche et a droite
      // seulement (espacement entre boutons); 0 ensuite: sans effet au
      // passage suivant du theme
      if AControl.BorderSpacing.Around > 0 then
      begin
        AControl.BorderSpacing.Left := AControl.BorderSpacing.Left + AControl.BorderSpacing.Around;
        AControl.BorderSpacing.Right := AControl.BorderSpacing.Right + AControl.BorderSpacing.Around;
        AControl.BorderSpacing.Around := 0;
      end;
      CenterInRow(AControl, FontTextHeight(AControl.Font) + 12);
    end
    else if AControl is TCustomLabel then
    begin
      TLabel(AControl).Layout := tlCenter;
      AControl.BorderSpacing.Left := 8;
      AControl.BorderSpacing.Right := 2;
    end;
  end;
  {$IFDEF WINDOWS}
  // cases a cocher et listes deroulantes themees par Windows ignorent les
  // couleurs: style classique pour que le texte reste lisible sur fond sombre
  if ((AControl is TCustomCheckBox) or (AControl is TRadioButton) or
      (AControl is TCustomComboBox)) and TWinControl(AControl).HandleAllocated then
    SetWindowTheme(TWinControl(AControl).Handle, ' ', ' ');
  {$ENDIF}
  if AControl is TRtPageHeader then
    AControl.Invalidate
  else if AControl is TTabSheet then
    AControl.Color := clAppBg
  else if AControl is TCustomEdit then
  begin
    TCustomEdit(AControl).Color := clEditorBg;
    AControl.Font.Color := clEditorFg;
  end
  else if AControl is TCustomComboBox then
  begin
    TCustomComboBox(AControl).Color := clEditorBg;
    AControl.Font.Color := clEditorFg;
  end
  else if (AControl is TCustomListBox) or (AControl is TCustomListView) or
    (AControl is TCustomTreeView) then
  begin
    AControl.Color := clSideBg;
    AControl.Font.Color := clSideText;
    // bordure native claire sur fond sombre
    if AControl is TCustomListView then TCustomListView(AControl).BorderStyle := bsNone
    else if AControl is TCustomTreeView then TCustomTreeView(AControl).BorderStyle := bsNone
    else TCustomListBox(AControl).BorderStyle := bsNone;
    // arbre: le dessin theme de Windows ignore Font.Color (texte noir sur
    // fond sombre); dessin LCL aux couleurs du theme, selection comprise
    if AControl is TCustomTreeView then
      with TCustomTreeView(AControl) do
      begin
        Options := Options - [tvoThemedDraw];
        BackgroundColor := clSideBg;
        SelectionColor := clSideSel;
        SelectionFontColor := clSideTextHi;
        SelectionFontColorUsed := True;
        ExpandSignType := tvestPlusMinus;
        ExpandSignColor := BlendColor(clSideText, clSideBg, 60);
        TreeLineColor := BlendColor(clSideText, clSideBg, 35);
      end;
    // arbres: rendu de RottenSSHrimp (signes plus/moins, pas le theme Explorer)
    {$IFDEF WINDOWS}
    if not (AControl is TCustomTreeView) then
      ApplyNativeDarkMode(TWinControl(AControl));
    {$ENDIF}
  end
  else if AControl is TCustomGrid then
  begin
    AControl.Color := clAppBg;
    AControl.Font.Color := clAppFg;
    if AControl is TStringGrid then
      TStringGrid(AControl).FixedColor := clSideBg;
    StyleGrid(TCustomGrid(AControl));
    {$IFDEF WINDOWS}
    ApplyNativeDarkMode(TWinControl(AControl));
    {$ENDIF}
  end
  else if (AControl is TCustomLabel) or (AControl is TCustomCheckBox) or
    (AControl is TRtCheckBox) or
    (AControl is TRadioButton) then
  begin
    // un libelle d'etat (erreur, avertissement, note) garde sa couleur
    if not IsStateColor(AControl.Font.Color) then
      AControl.Font.Color := clAppFg;
  end
  else if AControl is TCustomPanel then
  begin
    if not TCustomPanel(AControl).ParentColor then
      AControl.Color := clAppBg;
  end;
  if AControl is TWinControl then
  begin
    wc := TWinControl(AControl);
    for i := 0 to wc.ControlCount - 1 do
      ThemeControlTree(wc.Controls[i]);
  end;
end;

{ TRtDialog }

constructor TRtDialog.CreateDialog(AOwner: TComponent; const ACaption: string;
  AWidth, AHeight: Integer);
begin
  inherited CreateNew(AOwner);
  // tous les dialogues suivent le theme de la coque (clair ou sombre)
  FShellThemed := True;
  Caption := ACaption;
  BorderStyle := bsSizeable;
  Position := poOwnerFormCenter;
  Width := AWidth;
  Height := AHeight;
  KeyPreview := True;
  if RSUiFontName <> '' then
    Font.Name := RSUiFontName;
  Font.Size := RSUiFontSize;
  FHeader := MakePanel(Self, alTop, 30);
  FHeader.ParentColor := False;
  FHeader.Color := clBtnShadow;
  FHeader.Visible := False;
  FHeaderLabel := MakeLabel(FHeader, '', alClient);
  FHeaderLabel.Layout := tlCenter;
  FHeaderLabel.BorderSpacing.Left := 10;
  FHeaderLabel.Font.Color := clBtnHighlight;
  FBadgeLabel := MakeLabel(FHeader, '', alRight);
  FBadgeLabel.Layout := tlCenter;
  FBadgeLabel.Font.Style := [fsBold];
  FButtons := MakePanel(Self, alBottom, 44);
  FButtons.BorderSpacing.Around := 4;
  FBody := MakePanel(Self, alClient);
  FBody.BorderSpacing.Around := 8;
end;

procedure TRtDialog.SetTarget(const AServer, ABadge: string);
begin
  FTarget := AServer;
  FBadgeLabel.Caption := ABadge;
  if ABadge <> '' then
    FBadgeLabel.Font.Color := clBtnHighlight;
  RefreshHeader;
end;

procedure TRtDialog.SetIcon(const AId: string);
var
  hdrIcon: TRtIcon;
  before: Integer;
begin
  if FHeader.Visible then before := FHeader.Height else before := 0;
  if FHeaderIcon = nil then
  begin
    hdrIcon := TRtIcon.Create(FHeader);
    hdrIcon.Parent := FHeader;
    hdrIcon.Align := alLeft;
    hdrIcon.BorderSpacing.Left := 10;
    FHeaderIcon := hdrIcon;
    // l'icone precede le libelle: meme ordre que la creation
    FHeaderLabel.Align := alNone;
    FHeaderLabel.Align := alClient;
  end;
  TRtIcon(FHeaderIcon).SetIcon(AId, DIALOG_ICON, FHeaderLabel.Font.Color);
  FHeaderLabel.BorderSpacing.Left := 8;
  if TRtIcon(FHeaderIcon).PixelSize + 12 > 30 then
    FHeader.Height := TRtIcon(FHeaderIcon).PixelSize + 12
  else
    FHeader.Height := 30;
  RefreshHeader;
  // le bandeau prend sa place sur la fenetre, pas sur le contenu
  Height := Height + FHeader.Height - before;
end;

function TRtDialog.HeaderIconId: string;
begin
  if FHeaderIcon = nil then Result := '' else Result := TRtIcon(FHeaderIcon).IconId;
end;

function TRtDialog.HeaderText: string;
begin
  if FHeader.Visible then Result := FHeaderLabel.Caption else Result := '';
end;

// Bandeau: serveur cible (a toujours montrer), ou titre du dialogue quand
// seule l'icone le demande
procedure TRtDialog.RefreshHeader;
begin
  FHeader.Visible := (FTarget <> '') or (FHeaderIcon <> nil);
  if FTarget <> '' then
    FHeaderLabel.Caption := FTarget
  else
    FHeaderLabel.Caption := Caption;
  if FHeaderIcon <> nil then
    TRtIcon(FHeaderIcon).IconColor := FHeaderLabel.Font.Color;
end;

function TRtDialog.AddButton(const ACaption: string; AResult: TModalResult; ADefault,
  ACancel: Boolean): TButton;
begin
  Result := TButton.Create(FButtons);
  Result.Parent := FButtons;
  Result.Caption := ACaption;
  Result.ModalResult := AResult;
  Result.Default := ADefault;
  Result.Cancel := ACancel;
  Result.Align := alRight;
  // largeur ajustee au libelle dans la police reelle (theme, echelle): un
  // libelle long n'est jamais tronque; 100 px au moins pour des boutons
  // homogenes
  Result.AutoSize := True;
  Result.Constraints.MinWidth := 100;
  Result.BorderSpacing.Around := 5;
  // alRight empile de droite a gauche: le premier bouton ajoute reste a droite
  Result.Left := 10000 - FButtons.ControlCount * 10;
end;

procedure TRtDialog.ApplyTheme;
begin
  // dialogues: controles du systeme (voir en-tete), sauf ShellThemed; seules
  // les zones d'edition (MakeMemo) gardent les couleurs de l'editeur
  if FShellThemed then ApplyShellColors;
  ArrangeByCreation(Self);
  // libelles a la largeur de leur texte dans la police choisie, champs alignes
  FitFieldLabels(FBody, (Width * 55) div 100);
end;

// Controles alTop replaces dans leur ordre de creation. Le theme agrandit
// les lignes de champ (StyleShellField): la LCL range alors la ligne
// redimensionnee d'apres son Top d'origine (StackTop), apres ses voisines
// deja placees, et l'ordre voulu se perd
procedure StackByCreation(AParent: TWinControl);
var
  i, y: Integer;
  c: TControl;
begin
  AParent.DisableAlign;
  try
    y := 0;
    for i := 0 to AParent.ControlCount - 1 do
    begin
      c := AParent.Controls[i];
      if c.Align = alTop then
      begin
        c.Top := y;
        Inc(y, c.Height + 1);
      end;
      if c is TWinControl then
        StackByCreation(TWinControl(c));
    end;
  finally
    AParent.EnableAlign;
  end;
end;

procedure TRtDialog.ApplyShellColors;
begin
  Color := clAppBg;
  Font.Color := clAppFg;
  ThemeControlTree(FBody);
  ThemeControlTree(FButtons);
  StackByCreation(FBody);
  // bandeau du serveur cible: celui des onglets de la coque
  FHeader.Color := clTabStrip;
  FHeaderLabel.Font.Color := clTabActiveText;
  FBadgeLabel.Font.Color := clAccent;
  RefreshHeader;
end;

procedure TRtDialog.FitHeightToContent;
var
  i, need, h, maxH, oldH: Integer;
  c: TControl;
begin
  need := 0;
  for i := 0 to FBody.ControlCount - 1 do
  begin
    c := FBody.Controls[i];
    if (not c.Visible) or (c.Align <> alTop) then Continue;
    Inc(need, c.Height + c.BorderSpacing.Top + c.BorderSpacing.Bottom + 2 * c.BorderSpacing.Around);
  end;
  // le reste de la fenetre (bandeau, boutons, marges) garde sa taille
  h := ClientHeight - FBody.Height + need + 4;
  maxH := Screen.WorkAreaHeight - (Height - ClientHeight) - 20;
  if h > maxH then h := maxH;
  if h = ClientHeight then Exit;
  oldH := Height;
  ClientHeight := h;
  // reste centree sur sa position d'origine
  if Visible then Top := Top - (Height - oldH) div 2;
  if Top < Screen.WorkAreaTop then Top := Screen.WorkAreaTop;
end;

procedure TRtDialog.DoShow;
begin
  inherited DoShow;
  // hauteurs des libelles replies connues une fois les handles crees
  if FFitOnShow then FitHeightToContent;
  // les controles natifs n'ont leur handle qu'a l'affichage: le style
  // classique des cases a cocher (texte lisible sur fond sombre) et le mode
  // sombre des listes ne s'appliquent qu'a partir de la
  if FShellThemed then ApplyShellColors;
end;

procedure TRtDialog.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

end.
