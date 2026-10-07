// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
{ Les natifs ne se recolorent pas: sous Windows a styles visuels, TCheckBox
  ignore Font.Color (noir sur noir), TButton et TComboBox restent clairs.
  Ceux-ci se peignent seuls et relisent le theme a chaque dessin.

  Copyright (C) 2024 - 2026 Cyril LAMY
  SPDX-License-Identifier: GPL-3.0-or-later }
unit uThemedControls;

{$mode objfpc}{$H+}
{$IFDEF LCLCocoa}{$modeswitch objectivec1}{$ENDIF}

interface

uses
  Classes, SysUtils, Types, Controls, StdCtrls, ExtCtrls, Forms, Graphics,
  Menus, LCLType, uTheme, uRtGauge;

const
  // Tag d'un TLabel: couleur secondaire (aide) ou d'avertissement.
  THEME_TAG_SECONDARY = 7101;
  THEME_TAG_WARN = 7102;

type
  TThemedButtonGlyph = (tbgNone, tbgEye, tbgEyeCrossed);

  TThemedButton = class(TCustomControl)
  private
    FDefault: Boolean;
    FCancel: Boolean;
    FModalResult: TModalResult;
    FGlyph: TThemedButtonGlyph;
    FHot: Boolean;
    FDown: Boolean;
    procedure SetDefault(AValue: Boolean);
    procedure SetGlyph(AValue: TThemedButtonGlyph);
    procedure DrawEye(ACx, ACy: Integer; AColor: TColor);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure TextChanged; override;
    procedure EnabledChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Click; override;
    property Caption;
    property OnClick;
    // Visuel seulement: Entree n'arrive qu'au focus, la fenetre la route
    // (TNodeDialog.KeyDown).
    property Default: Boolean read FDefault write SetDefault;
    property Cancel: Boolean read FCancel write FCancel;
    property ModalResult: TModalResult read FModalResult write FModalResult;
    property Glyph: TThemedButtonGlyph read FGlyph write SetGlyph;
  end;

  TThemedCheck = class(TCustomControl)
  private
    FChecked: Boolean;
    FGrayed: Boolean;
    FAllowGrayed: Boolean;
    FHot: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetChecked(AValue: Boolean);
    function GetState: TCheckBoxState;
    procedure SetState(AValue: TCheckBoxState);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure TextChanged; override;
    procedure EnabledChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Click; override;
    property Caption;
    property Checked: Boolean read FChecked write SetChecked;
    property State: TCheckBoxState read GetState write SetState;
    property AllowGrayed: Boolean read FAllowGrayed write FAllowGrayed;
    // Clic ou Espace seulement: Checked par code ne notifie pas.
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  // Surface du TComboBox remplace (Items, ItemIndex, OnChange, Style); la
  // liste s'ouvre en menu theme.
  TThemedCombo = class(TCustomControl)
  private
    FItems: TStringList;
    FItemIndex: Integer;
    FOnChange: TNotifyEvent;
    FStyle: TComboBoxStyle;
    FHot: Boolean;
    FPopup: TPopupMenu;
    procedure SetItemIndex(AValue: Integer);
    function GetItems: TStrings;
    procedure ItemsChanged(Sender: TObject);
    procedure ItemPicked(Sender: TObject);
    procedure PopupClosed(Sender: TObject);
    procedure Pick(AIndex: Integer);
  protected
    procedure Paint; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure EnabledChanged; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure DropDown;
    function Text: string;
    property Items: TStrings read GetItems;
    // Poser ItemIndex par code ne notifie pas: comme un TComboBox.
    property ItemIndex: Integer read FItemIndex write SetItemIndex;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Decoratif: un seul style.
    property Style: TComboBoxStyle read FStyle write FStyle;
  end;

  TThemedTabs = class(TCustomControl)
  private
    FTabs: TStringList;
    FTabIndex: Integer;
    FHot: Integer;
    // Focus a la souris: pas de cadre, il ne sert qu'au clavier.
    FMouseFocus: Boolean;
    FOnChange: TNotifyEvent;
    function TabRect(AIndex: Integer): TRect;
    function TabAt(X, Y: Integer): Integer;
    procedure SetTabIndex(AValue: Integer);
    function GetTabs: TStrings;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Tabs: TStrings read GetTabs;
    // Par code: notifie aussi, l'hote affiche la page correspondante.
    property TabIndex: Integer read FTabIndex write SetTabIndex;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  // La jauge vit dans uRtGauge: la tirer d'ici embarquerait aussi les reglages Cocoa de cette unite.
  TThemedGauge = TRtGauge;

function ThemeFieldColor: TColor;
function ContrastTextColor(AColor: TColor): TColor;
procedure ThemeField(AEdit: TWinControl);
// Recursif. Les controles peints de cette unite se debrouillent seuls.
procedure ThemeControls(AControl: TControl);
// police, couleurs, Echap (bouton Cancel) et Entree (bouton Default)
procedure ThemeDialog(AForm: TCustomForm);
// les touches seulement
procedure DialogKeys(AForm: TCustomForm);

{$IFDEF LCLGtk2}
// Les themes GTK2 a moteur (Yaru) ignorent modify_base: d'ou un GtkStyle neuf.
procedure ForceGtk2EntryColors(AEdit: TWinControl; ABase, AText: TColor;
  AZeroPadding: Boolean);
{$ENDIF}

implementation

uses
  uMenuBar
  {$IFDEF LCLGtk2}, gtk2, gdk2, glib2{$ENDIF}
  {$IFDEF LCLCocoa}, CocoaAll, CocoaConfig{$ENDIF};

const
  RADIUS = 6;

function ThemeFieldColor: TColor;
begin
  Result := BlendColor(clAppFg, clAppBg, 7);
end;

function ContrastTextColor(AColor: TColor): TColor;
var
  c: LongInt;
  lum: Integer;
begin
  c := ColorToRGB(AColor);
  lum := ((c and $FF) * 299 + ((c shr 8) and $FF) * 587 +
    ((c shr 16) and $FF) * 114) div 1000;
  if lum > 150 then
    Result := RgbHexToColor($1A1A1A)
  else
    Result := RgbHexToColor($FFFFFF);
end;

function BorderColor: TColor;
begin
  Result := BlendColor(clAppFg, clAppBg, 30);
end;

function DisabledText: TColor;
begin
  Result := BlendColor(clAppFg, clAppBg, 45);
end;

{$IFDEF LCLGtk2}
procedure ForceGtk2EntryColors(AEdit: TWinControl; ABase, AText: TColor;
  AZeroPadding: Boolean);
  function GC(c: TColor): TGdkColor;
  var r: LongInt;
  begin
    r := ColorToRGB(c);
    Result.pixel := 0;
    Result.red   := (r and $FF) * 257;         // 0..255 -> 0..65535
    Result.green := ((r shr 8) and $FF) * 257;
    Result.blue  := ((r shr 16) and $FF) * 257;
  end;
var
  w: PGtkWidget;
  cb, ct: TGdkColor;
  st: TGtkStateType;
  style: PGtkStyle;
begin
  AEdit.HandleNeeded;
  if not AEdit.HandleAllocated then Exit;
  w := PGtkWidget(AEdit.Handle);
  cb := GC(ABase);
  ct := GC(AText);
  style := gtk_style_new;
  for st := GTK_STATE_NORMAL to GTK_STATE_INSENSITIVE do
  begin
    style^.base[st] := cb;
    style^.bg[st]   := cb;
    style^.text[st] := ct;
    style^.fg[st]   := ct;
  end;
  if AZeroPadding then
  begin
    // padding a zero: sinon l'entry depasse son cadre et recouvre la bordure
    style^.xthickness := 0;
    style^.ythickness := 0;
  end;
  gtk_widget_set_style(w, style);
  g_object_unref(style);   // le widget en detient desormais une reference
  gtk_widget_queue_resize(w);
end;
{$ENDIF}

procedure ThemeField(AEdit: TWinControl);
begin
  AEdit.Color := ThemeFieldColor;
  AEdit.Font.Color := clAppFg;
  {$IFDEF LCLGtk2}
  if AEdit is TCustomEdit then
    ForceGtk2EntryColors(AEdit, ThemeFieldColor, clAppFg, False);
  {$ENDIF}
end;

type
  // La LCL veut des methodes, pas des procedures.
  TFieldFramer = class
    procedure PanelPaint(Sender: TObject);
    procedure FieldFocus(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

var
  GFramer: TFieldFramer = nil;

const
  // Tag pose sur un champ dont le cadre est peint par son panneau
  THEME_TAG_FRAMED = 7103;
  FIELD_PAD_X = 7;
  FIELD_PAD_Y = 4;

// Deduit des bornes du champ DEJA rentre.
function FieldFrame(AEdit: TControl): TRect;
begin
  if AEdit is TCustomMemo then
    Result := Rect(AEdit.Left - FIELD_PAD_X, AEdit.Top - FIELD_PAD_Y,
      AEdit.Left + AEdit.Width + FIELD_PAD_X,
      AEdit.Top + AEdit.Height + FIELD_PAD_Y)
  else
    Result := Rect(AEdit.Left - FIELD_PAD_X,
      AEdit.Top + AEdit.Height div 2 - 13,
      AEdit.Left + AEdit.Width + FIELD_PAD_X,
      AEdit.Top + AEdit.Height div 2 + 13);
end;

procedure TFieldFramer.PanelPaint(Sender: TObject);
var
  p: TWinControl;
  cv: TCanvas;
  i: Integer;
  c: TControl;
  r: TRect;
begin
  p := TWinControl(Sender);
  if Sender is TCustomForm then cv := TCustomForm(Sender).Canvas
  else cv := TPanel(Sender).Canvas;
  for i := 0 to p.ControlCount - 1 do
  begin
    c := p.Controls[i];
    if (c.Tag <> THEME_TAG_FRAMED) or (not c.Visible) then Continue;
    r := FieldFrame(c);
    cv.Brush.Style := bsSolid;
    cv.Brush.Color := ThemeFieldColor;
    if TWinControl(c).Focused then
    begin
      cv.Pen.Color := clAccent;
      cv.Pen.Width := 2;
      cv.RoundRect(r.Left + 1, r.Top + 1, r.Right, r.Bottom,
        RADIUS, RADIUS);
      cv.Pen.Width := 1;
    end
    else
    begin
      if c.Enabled then
        cv.Pen.Color := BorderColor
      else
        cv.Pen.Color := BlendColor(clAppFg, clAppBg, 16);
      cv.RoundRect(r.Left, r.Top, r.Right, r.Bottom, RADIUS, RADIUS);
    end;
  end;
end;

procedure TFieldFramer.FieldFocus(Sender: TObject);
begin
  if (Sender is TControl) and (TControl(Sender).Parent <> nil) then
    TControl(Sender).Parent.Invalidate;
end;

{$IFDEF LCLCocoa}
type
  // Cocoa: changer de fenetre active ne declenche ni OnEnter ni OnExit, le cadre restait fige.
  TKeyWindowWatch = objcclass(NSObject)
    procedure keyChanged(ANote: NSNotification); message 'keyChanged:';
  end;

procedure TKeyWindowWatch.keyChanged(ANote: NSNotification);
var
  i: Integer;
  c: TWinControl;
begin
  for i := 0 to Screen.CustomFormCount - 1 do
  begin
    c := Screen.CustomForms[i].ActiveControl;
    if (c <> nil) and (c.Tag = THEME_TAG_FRAMED) and (c.Parent <> nil) then
      c.Parent.Invalidate;
  end;
end;

procedure WatchKeyWindow;
var
  w: TKeyWindowWatch;
begin
  w := TKeyWindowWatch.alloc.init;
  NSNotificationCenter.defaultCenter.addObserver_selector_name_object(w,
    ObjCSelector('keyChanged:'), NSWindowDidBecomeKeyNotification, nil);
  NSNotificationCenter.defaultCenter.addObserver_selector_name_object(w,
    ObjCSelector('keyChanged:'), NSWindowDidResignKeyNotification, nil);
end;
{$ENDIF}

// Cadre natif blanc et epais sous Windows en sombre: retire, champ rentre dans
// ses bornes, le panneau peint un cadre arrondi a la place.
procedure FrameField(AEdit: TCustomEdit);
var
  l, t, w, h, eh: Integer;
begin
  if not ((AEdit.Parent is TPanel) or (AEdit.Parent is TForm)) then Exit;
  if AEdit.Tag = THEME_TAG_FRAMED then Exit;
  l := AEdit.Left;
  t := AEdit.Top;
  w := AEdit.Width;
  h := AEdit.Height;
  AEdit.BorderStyle := bsNone;
  if AEdit is TCustomMemo then
    AEdit.SetBounds(l + FIELD_PAD_X, t + FIELD_PAD_Y, w - 2 * FIELD_PAD_X,
      h - 2 * FIELD_PAD_Y)
  else
  begin
    // hauteur posee, pas calculee: sans handle, AutoSize ne sait pas encore
    AEdit.AutoSize := False;
    eh := UiTextHeight('Ag') + 2;
    {$IFDEF LCLGtk3}
    // GTK3: hauteur minimale du theme
    AEdit.Constraints.MaxHeight := eh;
    {$ENDIF}
    AEdit.SetBounds(l + FIELD_PAD_X, t + (h - eh) div 2, w - 2 * FIELD_PAD_X,
      eh);
  end;
  AEdit.Tag := THEME_TAG_FRAMED;
  if GFramer = nil then
  begin
    GFramer := TFieldFramer.Create;
    {$IFDEF LCLCocoa}
    WatchKeyWindow;
    {$ENDIF}
  end;
  if AEdit.Parent is TPanel then
    TPanel(AEdit.Parent).OnPaint := @GFramer.PanelPaint
  else if not Assigned(TForm(AEdit.Parent).OnPaint) then
    TForm(AEdit.Parent).OnPaint := @GFramer.PanelPaint;
  if not Assigned(AEdit.OnEnter) then
    AEdit.OnEnter := @GFramer.FieldFocus;
  if not Assigned(AEdit.OnExit) then
    AEdit.OnExit := @GFramer.FieldFocus;
end;

procedure ThemeControls(AControl: TControl);
var
  i: Integer;
begin
  if AControl = nil then Exit;
  if AControl is TCustomForm then
  begin
    TCustomForm(AControl).Color := clAppBg;
    TCustomForm(AControl).Font.Color := clAppFg;
  end
  else if AControl is TPanel then
  begin
    TPanel(AControl).BevelOuter := bvNone;
    TPanel(AControl).ParentColor := False;
    TPanel(AControl).Color := clAppBg;
    TPanel(AControl).Font.Color := clAppFg;
  end
  else if AControl is TLabel then
  begin
    // Pas de ParentFont (ApplyUiFont): couleur posee a la main, sinon noir systeme.
    case AControl.Tag of
      THEME_TAG_SECONDARY: AControl.Font.Color := clTextSecondary;
      THEME_TAG_WARN: AControl.Font.Color := clScpWarn;
    else
      AControl.Font.Color := clAppFg;
    end;
    TLabel(AControl).Transparent := True;
  end
  else if (AControl is TCustomEdit) then
  begin
    ThemeField(TWinControl(AControl));
    FrameField(TCustomEdit(AControl));
  end
  else if (AControl is TListBox) and (TListBox(AControl).Style = lbStandard) then
  begin
    TListBox(AControl).Color := ThemeFieldColor;
    AControl.Font.Color := clAppFg;
  end;
  if AControl is TWinControl then
    for i := 0 to TWinControl(AControl).ControlCount - 1 do
      ThemeControls(TWinControl(AControl).Controls[i]);
end;

function DialogButton(AParent: TWinControl; ACancel: Boolean): TThemedButton;
var
  i: Integer;
  c: TControl;
begin
  Result := nil;
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    if not c.Visible then Continue;
    if c is TThemedButton then
    begin
      if (ACancel and TThemedButton(c).Cancel) or
         ((not ACancel) and TThemedButton(c).Default) then
        Exit(TThemedButton(c));
    end
    else if c is TWinControl then
    begin
      Result := DialogButton(TWinControl(c), ACancel);
      if Result <> nil then Exit;
    end;
  end;
end;

procedure TFieldFramer.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  f: TCustomForm;
  b: TThemedButton;
begin
  if (Shift <> []) or not (Sender is TCustomForm) then Exit;
  f := TCustomForm(Sender);
  if Key = VK_ESCAPE then
  begin
    b := DialogButton(f, True);
    if b <> nil then
    begin
      Key := 0;
      b.Click;
    end
    else if fsModal in f.FormState then
    begin
      Key := 0;
      f.ModalResult := mrCancel;
    end;
  end
  else if (Key = VK_RETURN) and not (f.ActiveControl is TCustomMemo) and
    not (f.ActiveControl is TThemedButton) then
  begin
    b := DialogButton(f, False);
    if (b <> nil) and b.Enabled then
    begin
      Key := 0;
      b.Click;
    end;
  end;
end;

procedure ThemeDialog(AForm: TCustomForm);
begin
  if AForm = nil then Exit;
  ApplyUiFont(AForm);
  ThemeControls(AForm);
  DialogKeys(AForm);
end;

procedure DialogKeys(AForm: TCustomForm);
begin
  if AForm = nil then Exit;
  if GFramer = nil then
    GFramer := TFieldFramer.Create;
  AForm.KeyPreview := True;
  if (AForm is TForm) and not Assigned(TForm(AForm).OnKeyDown) then
    TForm(AForm).OnKeyDown := @GFramer.FormKeyDown;
end;

procedure FocusRing(ACanvas: TCanvas; const R: TRect);
begin
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Width := 2;
  ACanvas.Pen.Color := clAccent;
  ACanvas.RoundRect(R.Left + 1, R.Top + 1, R.Right, R.Bottom,
    RADIUS, RADIUS);
  ACanvas.Pen.Width := 1;
end;

constructor TThemedButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  Width := 110;
  Height := 30;
end;

procedure TThemedButton.SetDefault(AValue: Boolean);
begin
  if FDefault = AValue then Exit;
  FDefault := AValue;
  Invalidate;
end;

procedure TThemedButton.SetGlyph(AValue: TThemedButtonGlyph);
begin
  if FGlyph = AValue then Exit;
  FGlyph := AValue;
  Invalidate;
end;

procedure TThemedButton.Click;
var
  f: TCustomForm;
begin
  if not Enabled then Exit;
  // comme TButton: le resultat d'abord, puis le OnClick qui peut l'annuler
  if FModalResult <> mrNone then
  begin
    f := GetParentForm(Self);
    if f <> nil then
      f.ModalResult := FModalResult;
  end;
  inherited Click;
end;

procedure TThemedButton.DrawEye(ACx, ACy: Integer; AColor: TColor);
begin
  Canvas.Pen.Color := AColor;
  Canvas.Pen.Width := 1;
  Canvas.Brush.Style := bsClear;
  Canvas.Ellipse(ACx - 7, ACy - 4, ACx + 8, ACy + 5);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := AColor;
  Canvas.Ellipse(ACx - 2, ACy - 2, ACx + 3, ACy + 3);
  if FGlyph = tbgEyeCrossed then
  begin
    Canvas.Pen.Width := 2;
    Canvas.Line(ACx - 6, ACy + 6, ACx + 7, ACy - 6);
    Canvas.Pen.Width := 1;
  end;
end;

procedure TThemedButton.Paint;
var
  r: TRect;
  bg, border, fg: TColor;
  tw, th: Integer;
begin
  r := ClientRect;
  // fond du parent sous les coins arrondis
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clAppBg;
  Canvas.FillRect(r);

  if not Enabled then
  begin
    bg := BlendColor(clAppFg, clAppBg, 6);
    border := BlendColor(clAppFg, clAppBg, 16);
    fg := DisabledText;
  end
  else if FDefault then
  begin
    bg := clAccent;
    if FDown then
      bg := BlendColor(clAppBg, clAccent, 22)
    else if FHot then
      bg := BlendColor(clAppFg, clAccent, 14);
    border := bg;
    fg := ContrastTextColor(bg);
  end
  else
  begin
    if FDown then
      bg := BlendColor(clAppFg, clAppBg, 24)
    else if FHot then
      bg := BlendColor(clAppFg, clAppBg, 17)
    else
      bg := BlendColor(clAppFg, clAppBg, 11);
    border := BorderColor;
    fg := clAppFg;
  end;
  if FGlyph <> tbgNone then
  begin
    // bouton-icone: invisible hors survol
    if not (FHot or FDown) then
    begin
      bg := clAppBg;
      border := clAppBg;
    end;
  end;

  Canvas.Brush.Color := bg;
  Canvas.Pen.Color := border;
  Canvas.Pen.Width := 1;
  Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, RADIUS, RADIUS);

  if FGlyph <> tbgNone then
    DrawEye(r.Width div 2, r.Height div 2, fg)
  else
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := fg;
    Canvas.Brush.Style := bsClear;
    tw := Canvas.TextWidth(Caption);
    th := Canvas.TextHeight('Ag');
    Canvas.TextOut((r.Width - tw) div 2, (r.Height - th) div 2, Caption);
  end;
  if Focused then
    FocusRing(Canvas, r);
  Canvas.Brush.Style := bsSolid;
end;

procedure TThemedButton.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TThemedButton.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  FDown := False;
  Invalidate;
end;

procedure TThemedButton.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDown := True;
    if CanFocus then SetFocus;
    Invalidate;
  end;
end;

procedure TThemedButton.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  // le clic lui-meme vient de la LCL (csClickEvents), si on relache DEDANS
  FDown := False;
  Invalidate;
  inherited MouseUp(Button, Shift, X, Y);
end;

procedure TThemedButton.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key in [VK_SPACE, VK_RETURN]) and (Shift = []) then
  begin
    Key := 0;
    Click;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TThemedButton.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TThemedButton.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TThemedButton.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TThemedButton.EnabledChanged;
begin
  inherited EnabledChanged;
  Invalidate;
end;

constructor TThemedCheck.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  Height := 22;
  Width := 200;
end;

procedure TThemedCheck.SetChecked(AValue: Boolean);
begin
  if (FChecked = AValue) and not FGrayed then Exit;
  FChecked := AValue;
  FGrayed := False;
  Invalidate;
end;

function TThemedCheck.GetState: TCheckBoxState;
begin
  if FGrayed then Result := cbGrayed
  else if FChecked then Result := cbChecked
  else Result := cbUnchecked;
end;

procedure TThemedCheck.SetState(AValue: TCheckBoxState);
begin
  if AValue = GetState then Exit;
  FGrayed := AValue = cbGrayed;
  FChecked := AValue = cbChecked;
  Invalidate;
end;

procedure TThemedCheck.Click;
begin
  if not Enabled then Exit;
  // comme TCheckBox: decoche, coche, puis grise si AllowGrayed
  if FGrayed then
    SetState(cbUnchecked)
  else if FChecked and FAllowGrayed then
    SetState(cbGrayed)
  else
    SetState(TCheckBoxState(Ord(not FChecked)));
  if Assigned(FOnChange) then
    FOnChange(Self);
  inherited Click;
end;

procedure TThemedCheck.Paint;
const
  BOX = 16;
var
  r, b: TRect;
  boxY, th: Integer;
  fg: TColor;
begin
  r := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clAppBg;
  Canvas.FillRect(r);

  boxY := (r.Height - BOX) div 2;
  b := Rect(1, boxY, 1 + BOX, boxY + BOX);
  if FChecked and Enabled then
  begin
    Canvas.Brush.Color := clAccent;
    Canvas.Pen.Color := clAccent;
  end
  else
  begin
    Canvas.Brush.Color := ThemeFieldColor;
    if FHot and Enabled then
      Canvas.Pen.Color := BlendColor(clAppFg, clAppBg, 55)
    else
      Canvas.Pen.Color := BorderColor;
  end;
  if FChecked and (not Enabled) then
    Canvas.Brush.Color := BlendColor(clAppFg, clAppBg, 25);
  Canvas.RoundRect(b.Left, b.Top, b.Right, b.Bottom, 4, 4);
  if FGrayed then
  begin
    Canvas.Pen.Color := clAppFg;
    Canvas.Pen.Width := 2;
    Canvas.Line(b.Left + 4, b.Top + 8, b.Left + 12, b.Top + 8);
    Canvas.Pen.Width := 1;
  end;
  if FChecked then
  begin
    Canvas.Pen.Color := ContrastTextColor(Canvas.Brush.Color);
    Canvas.Pen.Width := 2;
    Canvas.Line(b.Left + 4, b.Top + 8, b.Left + 7, b.Top + 11);
    Canvas.Line(b.Left + 7, b.Top + 11, b.Left + 12, b.Top + 4);
    Canvas.Pen.Width := 1;
  end;
  if Focused then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Color := clAccent;
    Canvas.Pen.Width := 2;
    Canvas.RoundRect(b.Left - 1, b.Top - 1, b.Right + 1, b.Bottom + 1, 5, 5);
    Canvas.Pen.Width := 1;
  end;

  if Enabled then fg := clAppFg else fg := DisabledText;
  Canvas.Font := Font;
  Canvas.Font.Color := fg;
  Canvas.Brush.Style := bsClear;
  th := Canvas.TextHeight('Ag');
  Canvas.TextOut(BOX + 10, (r.Height - th) div 2, Caption);
  Canvas.Brush.Style := bsSolid;
end;

procedure TThemedCheck.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TThemedCheck.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TThemedCheck.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_SPACE) and (Shift = []) then
  begin
    Key := 0;
    Click;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TThemedCheck.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TThemedCheck.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TThemedCheck.TextChanged;
begin
  inherited TextChanged;
  Invalidate;
end;

procedure TThemedCheck.EnabledChanged;
begin
  inherited EnabledChanged;
  Invalidate;
end;

constructor TThemedCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  FItems := TStringList.Create;
  FItems.OnChange := @ItemsChanged;
  FItemIndex := -1;
  FStyle := csDropDownList;
  Height := 26;
  Width := 200;
end;

destructor TThemedCombo.Destroy;
begin
  FItems.OnChange := nil;
  FItems.Free;
  inherited Destroy;
end;

function TThemedCombo.GetItems: TStrings;
begin
  Result := FItems;
end;

procedure TThemedCombo.ItemsChanged(Sender: TObject);
begin
  if FItemIndex >= FItems.Count then
    FItemIndex := -1;
  Invalidate;
end;

procedure TThemedCombo.SetItemIndex(AValue: Integer);
begin
  if (AValue < -1) or (AValue >= FItems.Count) then
    AValue := -1;
  if FItemIndex = AValue then Exit;
  FItemIndex := AValue;
  Invalidate;
end;

function TThemedCombo.Text: string;
begin
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then
    Result := FItems[FItemIndex]
  else
    Result := '';
end;

procedure TThemedCombo.Pick(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) or (AIndex = FItemIndex) then
    Exit;
  FItemIndex := AIndex;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TThemedCombo.ItemPicked(Sender: TObject);
begin
  Pick(TMenuItem(Sender).Tag);
end;

procedure TThemedCombo.PopupClosed(Sender: TObject);
begin
  Invalidate;
end;

procedure TThemedCombo.DropDown;
var
  i: Integer;
  mi: TMenuItem;
  p: TPoint;
begin
  if (not Enabled) or (FItems.Count = 0) then Exit;
  // reconstruit a chaque ouverture: Items a pu changer entre-temps
  FreeAndNil(FPopup);
  FPopup := TPopupMenu.Create(Self);
  FPopup.OnClose := @PopupClosed;
  for i := 0 to FItems.Count - 1 do
  begin
    mi := TMenuItem.Create(FPopup);
    mi.Caption := StringReplace(FItems[i], '&', '&&', [rfReplaceAll]);
    mi.Tag := i;
    mi.RadioItem := True;
    mi.Checked := i = FItemIndex;
    mi.OnClick := @ItemPicked;
    FPopup.Items.Add(mi);
  end;
  ThemePopupMenu(FPopup);
  p := ClientToScreen(Point(0, Height));
  FPopup.PopUp(p.X, p.Y);
end;

procedure TThemedCombo.Paint;
var
  r: TRect;
  th, cx, cy: Integer;
  fg: TColor;
begin
  r := ClientRect;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clAppBg;
  Canvas.FillRect(r);
  if Enabled and FHot then
    Canvas.Brush.Color := BlendColor(clAppFg, clAppBg, 11)
  else
    Canvas.Brush.Color := ThemeFieldColor;
  Canvas.Pen.Color := BorderColor;
  Canvas.RoundRect(r.Left, r.Top, r.Right, r.Bottom, RADIUS, RADIUS);

  if Enabled then fg := clAppFg else fg := DisabledText;
  Canvas.Font := Font;
  Canvas.Font.Color := fg;
  Canvas.Brush.Style := bsClear;
  th := Canvas.TextHeight('Ag');
  Canvas.TextRect(Rect(8, 0, r.Right - 26, r.Bottom), 8,
    (r.Height - th) div 2, Text);

  // chevron
  cx := r.Right - 14;
  cy := r.Height div 2;
  Canvas.Pen.Color := fg;
  Canvas.Pen.Width := 2;
  Canvas.Line(cx - 4, cy - 2, cx, cy + 2);
  Canvas.Line(cx, cy + 2, cx + 4, cy - 2);
  Canvas.Pen.Width := 1;
  if Focused then
    FocusRing(Canvas, r);
  Canvas.Brush.Style := bsSolid;
end;

procedure TThemedCombo.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TThemedCombo.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TThemedCombo.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  if CanFocus then SetFocus;
  DropDown;
end;

procedure TThemedCombo.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_UP:
      begin
        Pick(FItemIndex - 1);
        Key := 0;
      end;
    VK_DOWN:
      begin
        if ssAlt in Shift then
          DropDown
        else
          Pick(FItemIndex + 1);
        Key := 0;
      end;
    VK_SPACE, VK_F4:
      begin
        DropDown;
        Key := 0;
      end;
  end;
  if Key <> 0 then
    inherited KeyDown(Key, Shift);
end;

procedure TThemedCombo.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TThemedCombo.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

procedure TThemedCombo.EnabledChanged;
begin
  inherited EnabledChanged;
  Invalidate;
end;

constructor TThemedTabs.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  DoubleBuffered := True;
  FTabs := TStringList.Create;
  FTabIndex := 0;
  FHot := -1;
  Height := 32;
end;

destructor TThemedTabs.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

function TThemedTabs.GetTabs: TStrings;
begin
  Result := FTabs;
end;

function TThemedTabs.TabRect(AIndex: Integer): TRect;
var
  i, x, w: Integer;
begin
  x := 0;
  Result := Rect(0, 0, 0, 0);
  for i := 0 to FTabs.Count - 1 do
  begin
    w := UiTextWidth(FTabs[i]) + 32;
    if i = AIndex then
      Exit(Rect(x, 0, x + w, ClientHeight));
    Inc(x, w + 2);
  end;
end;

function TThemedTabs.TabAt(X, Y: Integer): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to FTabs.Count - 1 do
    if PtInRect(TabRect(i), Point(X, Y)) then
      Exit(i);
end;

procedure TThemedTabs.SetTabIndex(AValue: Integer);
begin
  if (AValue < 0) or (AValue >= FTabs.Count) or (AValue = FTabIndex) then
    Exit;
  FTabIndex := AValue;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TThemedTabs.Paint;
var
  i, th: Integer;
  r: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := clAppBg;
  Canvas.FillRect(ClientRect);
  // filet de base: les onglets reposent dessus
  Canvas.Brush.Color := BlendColor(clAppFg, clAppBg, 18);
  Canvas.FillRect(Rect(0, ClientHeight - 1, ClientWidth, ClientHeight));

  Canvas.Font := Font;
  th := Canvas.TextHeight('Ag');
  for i := 0 to FTabs.Count - 1 do
  begin
    r := TabRect(i);
    if (i = FHot) and (i <> FTabIndex) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := BlendColor(clAppFg, clAppBg, 7);
      Canvas.FillRect(Rect(r.Left, r.Top, r.Right, r.Bottom - 1));
    end;
    Canvas.Brush.Style := bsClear;
    if i = FTabIndex then
    begin
      Canvas.Font.Color := clAppFg;
      Canvas.Font.Style := [fsBold];
    end
    else
    begin
      Canvas.Font.Color := clTextSecondary;
      Canvas.Font.Style := [];
    end;
    Canvas.TextOut(r.Left + (r.Width - Canvas.TextWidth(FTabs[i])) div 2,
      (r.Height - th) div 2 - 1, FTabs[i]);
    if i = FTabIndex then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := clAccent;
      Canvas.FillRect(Rect(r.Left + 4, r.Bottom - 3, r.Right - 4, r.Bottom));
      if Focused and (not FMouseFocus) then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Pen.Color := clAccent;
        Canvas.RoundRect(r.Left + 2, r.Top + 2, r.Right - 2, r.Bottom - 5,
          RADIUS, RADIUS);
      end;
    end;
  end;
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
end;

procedure TThemedTabs.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  h: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  h := TabAt(X, Y);
  if h <> FHot then
  begin
    FHot := h;
    Invalidate;
  end;
end;

procedure TThemedTabs.MouseLeave;
begin
  inherited MouseLeave;
  if FHot <> -1 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TThemedTabs.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  i: Integer;
begin
  FMouseFocus := True;
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  i := TabAt(X, Y);
  if i >= 0 then
    SetTabIndex(i);
  Invalidate;
end;

procedure TThemedTabs.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if FMouseFocus then
  begin
    FMouseFocus := False;
    Invalidate;
  end;
  case Key of
    VK_LEFT:
      begin
        SetTabIndex(FTabIndex - 1);
        Key := 0;
      end;
    VK_RIGHT:
      begin
        SetTabIndex(FTabIndex + 1);
        Key := 0;
      end;
  end;
  if Key <> 0 then
    inherited KeyDown(Key, Shift);
end;

procedure TThemedTabs.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TThemedTabs.DoExit;
begin
  inherited DoExit;
  FMouseFocus := False;
  Invalidate;
end;

{$IFDEF LCLCocoa}
initialization
  // Cocoa: l'anneau de focus natif survit sur les champs mot de passe et double le cadre.
  // Par classe: basculer PasswordChar recree la vue.
  CocoaConfigFocusRing.setStrategy(TCocoaConfigFocusRing.Strategy.none,
    NSSTR('TCocoaSecureTextField'));
{$ENDIF}

end.
