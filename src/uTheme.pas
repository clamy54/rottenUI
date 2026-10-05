// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uTheme;

{$mode objfpc}{$H+}

// Jetons de couleur et polices en globales, remplacables a chaud par
// uThemeLoad (reprise de RottenSSHrimp, completee des jetons d'editeur de
// RottenText et des jetons de difference). Chaque controle les relit a son
// dessin: appliquer un theme = ecrire les globales puis repeindre.

interface

uses
  Graphics, Controls;

var
  // '' / 0 = defauts du widgetset (fontes embarquees absentes)
  RSUiFontName: string = '';
  RSUiFontSize: Integer = 10;     // onglets et menus, base 96 DPI
  RSTreeFontSize: Integer = 10;
  RSEditorFontName: string = '';
  RSEditorFontSize: Integer = 12;
  // posees par l'application, jamais par un theme
  RSTerminalFontName: string = '';
  RSTerminalFontSize: Integer = 12;

  clAppBg, clAppFg, clAccent, clBorder: TColor;
  clSideBg, clSideText, clSideTextHi, clSideSel, clSideHover, clSideActive: TColor;
  clStatusBg, clStatusText: TColor;
  clMenuBg, clMenuText, clMenuHover, clMenuPopupBg, clMenuDisabled, clMenuSep: TColor;
  clTabStrip, clTabActive, clTabInactive, clTabHover, clTabActiveText,
    clTabInactiveText, clTabIcon, clTabIconHi, clTabDead: TColor;

  // editeur LDIF et vues texte (RottenText)
  clEditorBg, clEditorFg, clCurrentLine, clSelectionBg, clSelectionFg, clCaret,
    clGutterBg, clGutterFg: TColor;
  clCodeComment, clCodeString, clCodeNumber, clCodeKeyword, clCodeType,
    clCodeInvalid, clCodeFunction, clCodeVariable: TColor;

  // differences: toujours accompagnees d'un symbole et d'un libelle
  clDiffEqual, clDiffAdded, clDiffAbsent, clDiffChanged, clDiffWarning,
    clDiffUnknown: TColor;

  clTermBg, clTermFg: TColor;

  // panneaux de fichiers, transferts
  clPanelBg, clPanelAltRow, clPanelHeader, clPanelHeaderText, clPanelGrid,
    clTextSecondary: TColor;
  clSelActive, clSelInactive, clSelText: TColor;
  clScpOk, clScpWarn, clScpErr: TColor;
  clProgressBar, clProgressTrack: TColor;

  // tailles choisies par l'utilisateur, prioritaires sur celles du theme
  // (uThemeLoad); l'application les charge et les enregistre
  PrefUiFontSize: Integer = 10;        // points, interface et arbres; 0 = systeme
  PrefEditorFontSize: Integer = 0;     // 0 = taille du theme

const
  // tailles de police (points) lisibles et sures pour les mises en page;
  // pour agrandir davantage, l'echelle de Windows agrandit tout d'un bloc
  FONT_SIZE_MIN = 10;
  FONT_SIZE_MAX = 14;

// Taille ramenee dans [FONT_SIZE_MIN, FONT_SIZE_MAX]
function ClampFontSize(ASize: Integer): Integer;

procedure ApplyDefaultFonts;
// recursif sur les enfants; les composants natifs n'y passent pas
procedure ApplyUiFont(AControl: TControl);
// RGB 0xRRGGBB -> TColor (0xBBGGRR): conversion testee, jamais de transtypage
function RgbHexToColor(ARgb: Cardinal): TColor;
function ColorToRgbHex(AColor: TColor): Cardinal;
function BlendColor(A, B: TColor; APct: Integer): TColor;
function IsDarkColor(AColor: TColor): Boolean;
// mesure hors ecran, police de l'interface
function UiTextHeight(const ASample: string): Integer;
function UiTextWidth(const ASample: string): Integer;
// remet les jetons aux valeurs du theme Rotten compile
procedure ResetRottenDefaults;

implementation

uses
  uFontEmbed;

function ClampFontSize(ASize: Integer): Integer;
begin
  if ASize < FONT_SIZE_MIN then Result := FONT_SIZE_MIN
  else if ASize > FONT_SIZE_MAX then Result := FONT_SIZE_MAX
  else Result := ASize;
end;

function RgbHexToColor(ARgb: Cardinal): TColor;
begin
  Result := TColor(((ARgb shr 16) and $FF) or (((ARgb shr 8) and $FF) shl 8) or
    ((ARgb and $FF) shl 16));
end;

function ColorToRgbHex(AColor: TColor): Cardinal;
var
  c: LongInt;
begin
  c := ColorToRGB(AColor);
  Result := (Cardinal(c and $FF) shl 16) or (Cardinal((c shr 8) and $FF) shl 8) or
    Cardinal((c shr 16) and $FF);
end;

function BlendColor(A, B: TColor; APct: Integer): TColor;
var
  ca, cb: LongInt;
  r, g, bl: Integer;
begin
  ca := ColorToRGB(A);
  cb := ColorToRGB(B);
  r := ((ca and $FF) * APct + (cb and $FF) * (100 - APct)) div 100;
  g := (((ca shr 8) and $FF) * APct + ((cb shr 8) and $FF) * (100 - APct)) div 100;
  bl := (((ca shr 16) and $FF) * APct + ((cb shr 16) and $FF) * (100 - APct)) div 100;
  Result := TColor(r or (g shl 8) or (bl shl 16));
end;

function IsDarkColor(AColor: TColor): Boolean;
var
  c: LongInt;
begin
  c := ColorToRGB(AColor);
  Result := ((c and $FF) * 299 + ((c shr 8) and $FF) * 587 + ((c shr 16) and $FF) * 114)
    div 1000 < 128;
end;

procedure ApplyDefaultFonts;
begin
  if MonaspaceAvailable then
  begin
    RSUiFontName := MonaspaceDefaultFamily;
    RSEditorFontName := MonaspaceTerminalDefaultFamily;
  end
  else
  begin
    RSUiFontName := '';
    RSEditorFontName := '';
  end;
  RSTerminalFontName := RSEditorFontName;
end;

var
  GMeasureBmp: TBitmap = nil;

function MeasureCanvas: TCanvas;
begin
  if GMeasureBmp = nil then
  begin
    GMeasureBmp := TBitmap.Create;
    GMeasureBmp.SetSize(1, 1);
  end;
  if RSUiFontName <> '' then
    GMeasureBmp.Canvas.Font.Name := RSUiFontName;
  if RSUiFontSize > 0 then
    GMeasureBmp.Canvas.Font.Size := RSUiFontSize;
  Result := GMeasureBmp.Canvas;
end;

function UiTextHeight(const ASample: string): Integer;
begin
  Result := MeasureCanvas.TextHeight(ASample);
  if Result < 1 then
    Result := 1;
end;

function UiTextWidth(const ASample: string): Integer;
begin
  Result := MeasureCanvas.TextWidth(ASample);
  if Result < 0 then
    Result := 0;
end;

procedure ApplyUiFont(AControl: TControl);
var
  i: Integer;
  wc: TWinControl;
begin
  if AControl = nil then Exit;
  if RSUiFontName <> '' then
    AControl.Font.Name := RSUiFontName;
  if AControl is TWinControl then
  begin
    wc := TWinControl(AControl);
    for i := 0 to wc.ControlCount - 1 do
      ApplyUiFont(wc.Controls[i]);
  end;
end;

procedure ResetRottenDefaults;
begin
  // palette de reference "Rotten" (cahier des charges 4.2)
  clAppBg := RgbHexToColor($1E1E1E);
  clAppFg := RgbHexToColor($D4D4D4);
  clAccent := RgbHexToColor($FB9E6B);
  clBorder := RgbHexToColor($161616);
  clSideBg := RgbHexToColor($252526);
  clSideText := RgbHexToColor($CCCCCC);
  clSideTextHi := RgbHexToColor($FFFFFF);
  clSideSel := RgbHexToColor($37414F);
  clSideHover := RgbHexToColor($2D2D30);
  clSideActive := RgbHexToColor($8FB84E);
  clStatusBg := RgbHexToColor($252526);
  clStatusText := RgbHexToColor($9D9D9D);
  clMenuBg := RgbHexToColor($252526);
  clMenuText := RgbHexToColor($CCCCCC);
  clMenuHover := RgbHexToColor($37414F);
  clMenuPopupBg := RgbHexToColor($2D2D30);
  clMenuDisabled := RgbHexToColor($808080);
  clMenuSep := RgbHexToColor($454549);
  clTabStrip := RgbHexToColor($3A3A3D);
  clTabActive := RgbHexToColor($646469);
  clTabInactive := RgbHexToColor($4C4C50);
  clTabHover := RgbHexToColor($59595E);
  clTabActiveText := RgbHexToColor($FFFFFF);
  clTabInactiveText := RgbHexToColor($D2D2D2);
  clTabIcon := RgbHexToColor($6A9955);
  clTabIconHi := RgbHexToColor($7AB069);
  clTabDead := RgbHexToColor($F14C4C);
  clEditorBg := RgbHexToColor($1E1E1E);
  clEditorFg := RgbHexToColor($D4D4D4);
  clCurrentLine := RgbHexToColor($282828);
  clSelectionBg := RgbHexToColor($FB9E6B);
  clSelectionFg := RgbHexToColor($1E1E1E);
  clCaret := RgbHexToColor($AEAFAD);
  clGutterBg := RgbHexToColor($1E1E1E);
  clGutterFg := RgbHexToColor($858585);
  clCodeComment := RgbHexToColor($6A9955);
  clCodeString := RgbHexToColor($CE9178);
  clCodeNumber := RgbHexToColor($B5CEA8);
  clCodeKeyword := RgbHexToColor($569CD6);
  clCodeType := RgbHexToColor($4EC9B0);
  clCodeInvalid := RgbHexToColor($F44747);
  clCodeFunction := RgbHexToColor($DCDCAA);
  clCodeVariable := RgbHexToColor($9CDCFE);
  clDiffEqual := RgbHexToColor($8FB84E);
  clDiffAdded := RgbHexToColor($4EC9B0);
  clDiffAbsent := RgbHexToColor($F14C4C);
  clDiffChanged := RgbHexToColor($FB9E6B);
  clDiffWarning := RgbHexToColor($DCDCAA);
  clDiffUnknown := RgbHexToColor($9D9D9D);
  clTermBg := RgbHexToColor($1E1E1E);
  clTermFg := RgbHexToColor($D4D4D4);
  clPanelBg := RgbHexToColor($1E1E1E);
  clPanelAltRow := RgbHexToColor($232323);
  clPanelHeader := RgbHexToColor($2D2D30);
  clPanelHeaderText := RgbHexToColor($C8C8C8);
  clPanelGrid := RgbHexToColor($333336);
  clTextSecondary := RgbHexToColor($9D9D9D);
  clSelActive := RgbHexToColor($37414F);
  clSelInactive := RgbHexToColor($2E3238);
  clSelText := RgbHexToColor($FFFFFF);
  clScpOk := RgbHexToColor($8FB84E);
  clScpWarn := RgbHexToColor($D7A03A);
  clScpErr := RgbHexToColor($F14C4C);
  clProgressBar := RgbHexToColor($FB9E6B);
  clProgressTrack := RgbHexToColor($3A3A3D);
end;

initialization
  ResetRottenDefaults;

finalization
  GMeasureBmp.Free;

end.
