// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtDatePicker;

// Champ de date du theme: une saisie qui montre la date comme l'utilisateur
// la lit (jj/mm/aaaa en francais) et un bouton qui ouvre un calendrier du
// mois dessine aux couleurs et polices du theme (le calendrier natif ignore
// le theme). Les dates sont gardees en ISO aaaa-mm-jj. Clavier: fleches d'un
// jour ou d'une semaine, Page haut / bas d'un mois, Entree choisit, Echap ferme.

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, Forms, StdCtrls, ExtCtrls, LCLType, DateUtils;

type
  TDateField = class(TPanel)
  private
    FEdit: TEdit;
    FButton: TButton;
    procedure ButtonClick(Sender: TObject);
    function GetIso: string;
    procedure SetIso(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    { True when the text is empty or a date. }
    function IsValid: Boolean;
    { ISO yyyy-mm-dd, '' when empty; the raw text when it is not a date. }
    property IsoValue: string read GetIso write SetIso;
    property Edit: TEdit read FEdit;
  end;

{ 'dd/mm/yyyy', 'dd/mm/yy', 'dd.mm.yyyy', 'dd-mm-yyyy' or 'yyyy-mm-dd'. }
function ParseUserDate(const S: string; out ADate: TDateTime): Boolean;
function IsoOf(ADate: TDateTime): string;
{ An ISO date as the user reads it ('' stays ''; anything else unchanged). }
function DisplayOfIso(const AIso: string): string;

resourcestring
  rsDateToday = 'Today';
  rsDateClear = 'Clear';
  rsDatePick = 'Choose a date';
  rsDateHint = 'dd/mm/yyyy';
  rsValDate = '%s: type a date (dd/mm/yyyy) or choose it in the calendar.';

implementation

uses
  uTheme, uUiKit;

function IsoOf(ADate: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', ADate);
end;

function ParseUserDate(const S: string; out ADate: TDateTime): Boolean;
var
  t: string;
  parts: TStringArray;
  d, m, y: Integer;
begin
  Result := False;
  ADate := 0;
  t := Trim(S);
  if t = '' then Exit;
  t := StringReplace(StringReplace(t, '.', '/', [rfReplaceAll]), ' ', '', [rfReplaceAll]);
  if (Length(t) >= 8) and (t[5] = '-') then
  begin
    // ISO: yyyy-mm-dd
    parts := t.Split(['-']);
    if Length(parts) <> 3 then Exit;
    y := StrToIntDef(parts[0], -1); m := StrToIntDef(parts[1], -1); d := StrToIntDef(parts[2], -1);
  end
  else
  begin
    parts := StringReplace(t, '-', '/', [rfReplaceAll]).Split(['/']);
    if Length(parts) <> 3 then Exit;
    d := StrToIntDef(parts[0], -1); m := StrToIntDef(parts[1], -1); y := StrToIntDef(parts[2], -1);
    if (y >= 0) and (y < 100) then Inc(y, 2000);
  end;
  Result := IsValidDate(y, m, d);
  if Result then ADate := EncodeDate(y, m, d);
end;

function DisplayOfIso(const AIso: string): string;
var
  d: TDateTime;
begin
  if (AIso <> '') and ParseUserDate(AIso, d) then
    Result := FormatDateTime('dd"/"mm"/"yyyy', d)
  else
    Result := AIso;
end;

{ --- the month grid ------------------------------------------------------ }

type
  TPickEvent = procedure(Sender: TObject; ADate: TDateTime) of object;

  TMonthGrid = class(TCustomControl)
  private
    FYear, FMonth: Word;
    FDayCursor: TDateTime;       // the day under the keyboard cursor
    FSelected: TDateTime;     // 0: none
    FHover: Integer;          // cell index 0..41, -1 none
    FOnPick: TPickEvent;
    function CellH: Integer;
    function CellW: Integer;
    function FirstShown: TDateTime;
    function CellRect(AIndex: Integer): TRect;
    function CellAt(X, Y: Integer): Integer;
    function HeaderRect: TRect;
    procedure ShowMonthOf(ADate: TDateTime);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start(ADate: TDateTime);
    function PreferredSize: TPoint;
    property OnPick: TPickEvent read FOnPick write FOnPick;
  end;

constructor TMonthGrid.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FHover := -1;
end;

function TMonthGrid.CellH: Integer;
begin
  Result := FontTextHeight(Font) + 10;
end;

function TMonthGrid.CellW: Integer;
begin
  Result := Canvas.TextWidth('00') + 22;
  if Result < CellH + 8 then Result := CellH + 8;
end;

function TMonthGrid.PreferredSize: TPoint;
begin
  Canvas.Font.Assign(Font);
  // Header + weekday row + 6 weeks.
  Result := Point(CellW * 7 + 8, CellH * 8 + 8);
end;

function TMonthGrid.HeaderRect: TRect;
begin
  Result := Rect(4, 4, ClientWidth - 4, 4 + CellH);
end;

function TMonthGrid.FirstShown: TDateTime;
var
  first: TDateTime;
begin
  // Weeks start on Monday (ISO, as in France).
  first := EncodeDate(FYear, FMonth, 1);
  Result := first - (DayOfTheWeek(first) - 1);
end;

function TMonthGrid.CellRect(AIndex: Integer): TRect;
var
  x, y: Integer;
begin
  x := 4 + (AIndex mod 7) * CellW;
  y := 4 + CellH * 2 + (AIndex div 7) * CellH;
  Result := Rect(x, y, x + CellW, y + CellH);
end;

function TMonthGrid.CellAt(X, Y: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to 41 do
    if PtInRect(CellRect(i), Point(X, Y)) then Exit(i);
  Result := -1;
end;

procedure TMonthGrid.ShowMonthOf(ADate: TDateTime);
var
  d: Word;
begin
  DecodeDate(ADate, FYear, FMonth, d);
  Invalidate;
end;

procedure TMonthGrid.Start(ADate: TDateTime);
begin
  FSelected := ADate;
  if ADate = 0 then ADate := Date;
  FDayCursor := ADate;
  ShowMonthOf(ADate);
end;

procedure TMonthGrid.Paint;
var
  r, h: TRect;
  i, dow: Integer;
  day: TDateTime;
  s: string;
  fg, dim: TColor;
begin
  Canvas.Font.Assign(Font);
  fg := clAppFg;
  dim := BlendColor(clAppFg, clAppBg, 40);
  Canvas.Brush.Color := clAppBg;
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := BlendColor(clAppFg, clAppBg, 30);
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(ClientRect);
  // Header: < Month Year >
  h := HeaderRect;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := fg;
  s := FormatDateTime('mmmm yyyy', EncodeDate(FYear, FMonth, 1));
  if s <> '' then s[1] := UpCase(s[1]);
  Canvas.TextOut((h.Left + h.Right - Canvas.TextWidth(s)) div 2, h.Top + (CellH - Canvas.TextHeight(s)) div 2, s);
  Canvas.TextOut(h.Left + 10, h.Top + (CellH - Canvas.TextHeight('<')) div 2, '<');
  Canvas.TextOut(h.Right - 10 - Canvas.TextWidth('>'), h.Top + (CellH - Canvas.TextHeight('>')) div 2, '>');
  Canvas.Font.Style := [];
  // Weekday initials, Monday first.
  Canvas.Font.Color := dim;
  for dow := 1 to 7 do
  begin
    s := Copy(DefaultFormatSettings.ShortDayNames[(dow mod 7) + 1], 1, 2);
    r := Rect(4 + (dow - 1) * CellW, 4 + CellH, 4 + dow * CellW, 4 + CellH * 2);
    Canvas.TextOut((r.Left + r.Right - Canvas.TextWidth(s)) div 2, r.Top + (CellH - Canvas.TextHeight(s)) div 2, s);
  end;
  // Days.
  for i := 0 to 41 do
  begin
    day := FirstShown + i;
    r := CellRect(i);
    InflateRect(r, -2, -2);
    if (FSelected <> 0) and (Trunc(day) = Trunc(FSelected)) then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := clAccent;
      Canvas.Pen.Color := clAccent;
      Canvas.RoundRect(r, 6, 6);
      Canvas.Font.Color := clAppBg;
    end
    else
    begin
      if (i = FHover) or (Trunc(day) = Trunc(FDayCursor)) then
      begin
        Canvas.Brush.Style := bsSolid;
        Canvas.Brush.Color := BlendColor(clAccent, clAppBg, 22);
        Canvas.Pen.Color := Canvas.Brush.Color;
        Canvas.RoundRect(r, 6, 6);
      end;
      if MonthOf(day) = FMonth then Canvas.Font.Color := fg else Canvas.Font.Color := dim;
    end;
    // Today framed.
    if Trunc(day) = Trunc(Date) then
    begin
      Canvas.Brush.Style := bsClear;
      Canvas.Pen.Color := clAccent;
      Canvas.RoundRect(r, 6, 6);
    end;
    Canvas.Brush.Style := bsClear;
    s := IntToStr(DayOf(day));
    Canvas.TextOut((r.Left + r.Right - Canvas.TextWidth(s)) div 2, r.Top + (r.Bottom - r.Top - Canvas.TextHeight(s)) div 2, s);
  end;
end;

procedure TMonthGrid.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
  h: TRect;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  h := HeaderRect;
  if PtInRect(h, Point(X, Y)) then
  begin
    // The arrows at both ends of the header change the month.
    if X < h.Left + CellW then FDayCursor := IncMonth(FDayCursor, -1)
    else if X > h.Right - CellW then FDayCursor := IncMonth(FDayCursor, 1)
    else Exit;
    ShowMonthOf(FDayCursor);
    Exit;
  end;
  i := CellAt(X, Y);
  if (i >= 0) and Assigned(FOnPick) then FOnPick(Self, FirstShown + i);
end;

procedure TMonthGrid.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  i: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  i := CellAt(X, Y);
  if i <> FHover then
  begin
    FHover := i;
    Invalidate;
  end;
end;

procedure TMonthGrid.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_LEFT: FDayCursor := FDayCursor - 1;
    VK_RIGHT: FDayCursor := FDayCursor + 1;
    VK_UP: FDayCursor := FDayCursor - 7;
    VK_DOWN: FDayCursor := FDayCursor + 7;
    VK_PRIOR: FDayCursor := IncMonth(FDayCursor, -1);
    VK_NEXT: FDayCursor := IncMonth(FDayCursor, 1);
    VK_HOME: FDayCursor := Date;
    VK_RETURN:
      begin
        if Assigned(FOnPick) then FOnPick(Self, FDayCursor);
        Key := 0;
        Exit;
      end;
  else
    begin
      inherited KeyDown(Key, Shift);
      Exit;
    end;
  end;
  Key := 0;
  ShowMonthOf(FDayCursor);
end;

{ --- the popup ------------------------------------------------------------- }

type
  TCalendarPopup = class(TForm)
  private
    FGrid: TMonthGrid;
    FPicked: TDateTime;
    FCleared: Boolean;
    procedure GridPick(Sender: TObject; ADate: TDateTime);
    procedure TodayClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure PopupDeactivate(Sender: TObject);
    procedure PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor CreatePopup(AOwner: TComponent; AFont: TFont; ADate: TDateTime);
  end;

constructor TCalendarPopup.CreatePopup(AOwner: TComponent; AFont: TFont; ADate: TDateTime);
var
  bar: TPanel;
  sz: TPoint;
begin
  inherited CreateNew(AOwner);
  BorderStyle := bsNone;
  KeyPreview := True;
  Color := clAppBg;
  Font.Assign(AFont);
  OnDeactivate := @PopupDeactivate;
  OnKeyDown := @PopupKeyDown;
  FGrid := TMonthGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Font.Assign(AFont);
  FGrid.Align := alClient;
  FGrid.OnPick := @GridPick;
  FGrid.Start(ADate);
  bar := MakePanel(Self, alBottom, FontTextHeight(AFont) + 18);
  bar.Color := clAppBg;
  MakeButton(bar, rsDateClear, @ClearClick, alRight);
  MakeButton(bar, rsDateToday, @TodayClick, alLeft);
  sz := FGrid.PreferredSize;
  ClientWidth := sz.X;
  ClientHeight := sz.Y + bar.Height;
  ThemeControlTree(Self);
  Color := clAppBg;
end;

procedure TCalendarPopup.GridPick(Sender: TObject; ADate: TDateTime);
begin
  FPicked := ADate;
  ModalResult := mrOk;
end;

procedure TCalendarPopup.TodayClick(Sender: TObject);
begin
  FPicked := Date;
  ModalResult := mrOk;
end;

procedure TCalendarPopup.ClearClick(Sender: TObject);
begin
  FCleared := True;
  ModalResult := mrOk;
end;

procedure TCalendarPopup.PopupDeactivate(Sender: TObject);
begin
  // Clicking elsewhere closes it, like a drop-down list.
  if ModalResult = mrNone then ModalResult := mrCancel;
end;

procedure TCalendarPopup.PopupKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

{ --- the field ------------------------------------------------------------- }

constructor TDateField.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FButton := MakeButton(Self, '...', @ButtonClick, alRight);
  FButton.Hint := rsDatePick;
  FButton.ShowHint := True;
  FEdit := MakeEdit(Self, alClient);
  FEdit.TextHint := rsDateHint;
end;

function TDateField.IsValid: Boolean;
var
  d: TDateTime;
begin
  Result := (Trim(FEdit.Text) = '') or ParseUserDate(FEdit.Text, d);
end;

function TDateField.GetIso: string;
var
  d: TDateTime;
begin
  if Trim(FEdit.Text) = '' then Result := ''
  else if ParseUserDate(FEdit.Text, d) then Result := IsoOf(d)
  else Result := Trim(FEdit.Text);
end;

procedure TDateField.SetIso(const AValue: string);
begin
  FEdit.Text := DisplayOfIso(AValue);
end;

procedure TDateField.ButtonClick(Sender: TObject);
var
  pop: TCalendarPopup;
  d: TDateTime;
  p: TPoint;
  mon: TMonitor;
begin
  if not ParseUserDate(FEdit.Text, d) then d := 0;
  pop := TCalendarPopup.CreatePopup(Self, FEdit.Font, d);
  try
    // Under the field, kept on the screen.
    p := ClientToScreen(Point(0, Height));
    mon := Screen.MonitorFromPoint(p);
    if p.X + pop.Width > mon.WorkareaRect.Right then p.X := mon.WorkareaRect.Right - pop.Width;
    if p.Y + pop.Height > mon.WorkareaRect.Bottom then p.Y := ClientToScreen(Point(0, 0)).Y - pop.Height;
    pop.Left := p.X;
    pop.Top := p.Y;
    if pop.ShowModal = mrOk then
    begin
      if pop.FCleared then FEdit.Text := ''
      else FEdit.Text := FormatDateTime('dd"/"mm"/"yyyy', pop.FPicked);
    end;
  finally
    pop.Free;
  end;
  FEdit.SetFocus;
end;

end.
