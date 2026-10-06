// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uThemeLoad;

{$mode objfpc}{$H+}

// Registre des themes: Rotten, Light et Nord (RottenSSHrimp), les 16 themes de
// RottenText embarques en ressources (sans leurs Rotten et Nord, doublons des
// themes de la coque), puis les JSON du dossier utilisateur.
// Les collisions de nom deviennent des variantes nommees: aucun fichier n'en
// ecrase un autre. Appliquer = resoudre toutes les couleurs, puis ecrire les
// globales de uTheme d'un bloc; un theme invalide n'entre jamais au registre.

interface

uses
  SysUtils, Classes, uThemeData;

procedure InitThemes(const APreferredName: string);
function ThemeCount: Integer;
function ThemeName(AIndex: Integer): string;
function ThemeKind(AIndex: Integer): TThemeKind;
function CurrentThemeIndex: Integer;
function CurrentThemeName: string;
function ApplyThemeIndex(AIndex: Integer): Boolean;
function ApplyThemeByName(const AName: string): Boolean;
// Couleurs resolues d'un theme (ordre TColor) et ses familles de fontes, sans
// l'appliquer: apercu des preferences
function ThemePreview(AIndex: Integer; out AColors: TThemeColors; out AUiFont,
  AEditorFont: string): Boolean;
// Avertissements de chargement propres a un theme (cles inconnues...)
function ThemeWarnings(AIndex: Integer): TStringArray;
// themes utilisateur refuses ou avertissements, pour les preferences
function ThemeDiagnostics: TStrings;
// Dossier des themes JSON de l'utilisateur: ThemesUserDir si l'application
// l'a pose avant InitThemes, sinon <dossier de configuration>/themes
function UserThemesDir: string;

var
  ThemesUserDir: string = '';
  // False avant InitThemes: sans les themes RottenText
  ThemesEmbedded: Boolean = True;

implementation

uses
  LCLType, uTheme, uFontEmbed, uSafeSave;

// themes embarques (THEME_*), produits par tools/gen_res.py
{$R rottenui_themes.res}

const
  EMBEDDED_THEMES: array[0..15] of string = ('AQUA', 'CLASSIC_LIGHT', 'CODE_DARK', 'ELEGANT',
    'GAS_PLASMA', 'GREEN_PHOSPHOR', 'GRUVBOX_DARK', 'HIGH_CONTRAST_DARK', 'HIGH_CONTRAST_LIGHT',
    'MONOKAI', 'NEON_NIGHT', 'NOTSOROTTEN', 'ONE_DARK', 'PAPER', 'SOLARIZED_LIGHT', 'TANGO');

var
  GThemes: array of TThemeDef;
  GCurrent: Integer = 0;
  GDiagnostics: TStringList = nil;

function UserThemesDir: string;
begin
  if ThemesUserDir <> '' then
    Result := ExcludeTrailingPathDelimiter(ThemesUserDir)
  else
    Result := GetAppConfigDir(False) + 'themes';
end;

function ThemeDiagnostics: TStrings;
begin
  if GDiagnostics = nil then
    GDiagnostics := TStringList.Create;
  Result := GDiagnostics;
end;

function NameTaken(const AName: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(GThemes) do
    if SameText(GThemes[i].Name, AName) then Exit(True);
  Result := False;
end;

procedure AddTheme(ADef: TThemeDef; const ASuffix: string);
var
  n: Integer;
  base: string;
begin
  if NameTaken(ADef.Name) then
  begin
    base := ADef.Name + ' (' + ASuffix + ')';
    ADef.Name := base;
    n := 2;
    while NameTaken(ADef.Name) do
    begin
      ADef.Name := base + ' ' + IntToStr(n);
      Inc(n);
    end;
  end;
  SetLength(GThemes, Length(GThemes) + 1);
  GThemes[High(GThemes)] := ADef;
end;

procedure AddBuiltin(const AName: string; const AColors: TThemeColors);
var
  d: TThemeDef;
begin
  d := Default(TThemeDef);
  d.Name := AName;
  d.Kind := tkBuiltin;
  d.Colors := AColors;
  AddTheme(d, 'builtin');
end;

function ReadResourceText(const AName: string; out AText: string): Boolean;
var
  rs: TResourceStream;
begin
  Result := False;
  AText := '';
  try
    rs := TResourceStream.Create(HInstance, AName, RT_RCDATA);
    try
      if rs.Size > THEME_MAX_BYTES then Exit;
      SetLength(AText, rs.Size);
      if rs.Size > 0 then
        rs.ReadBuffer(AText[1], rs.Size);
      Result := True;
    finally
      rs.Free;
    end;
  except
    Result := False;
  end;
end;

procedure LoadEmbedded;
var
  i: Integer;
  txt, err: string;
  d: TThemeDef;
begin
  for i := 0 to High(EMBEDDED_THEMES) do
  begin
    if not ReadResourceText('THEME_' + EMBEDDED_THEMES[i], txt) then Continue;
    if ParseThemeJson(txt, EMBEDDED_THEMES[i], tkRottenText, d, err) then
      AddTheme(d, 'RottenText')
    else
      ThemeDiagnostics.Add(Format('embedded theme %s rejected: %s', [EMBEDDED_THEMES[i], err]));
  end;
end;

procedure LoadUserThemes;
var
  sr: TSearchRec;
  dir, txt, err: string;
  d: TThemeDef;
  fs: THandleStream;
  notReg: Boolean;
  raw: RawByteString;
begin
  dir := UserThemesDir;
  if not DirectoryExists(dir) then Exit;
  if FindFirst(dir + PathDelim + '*.json', faAnyFile, sr) <> 0 then Exit;
  try
    repeat
      if (sr.Attr and faDirectory) <> 0 then Continue;
      if Length(GThemes) >= 128 then Break;
      if sr.Size > THEME_MAX_BYTES then
      begin
        ThemeDiagnostics.Add(sr.Name + ': file too large');
        Continue;
      end;
      try
        // fichier ordinaire seulement; taille lue une fois, lecture bornee a
        // cette capacite (G01)
        fs := OpenRegularFileRead(dir + PathDelim + sr.Name, notReg);
        if fs = nil then
        begin
          ThemeDiagnostics.Add(sr.Name + ': not a regular file');
          Continue;
        end;
        try
          if not ReadWholeStream(fs, THEME_MAX_BYTES, raw) then
          begin
            ThemeDiagnostics.Add(sr.Name + ': file too large or changed while it was read');
            Continue;
          end;
          txt := string(raw);
        finally
          fs.Free;
        end;
      except
        ThemeDiagnostics.Add(sr.Name + ': unreadable');
        Continue;
      end;
      if ParseThemeJson(txt, ChangeFileExt(sr.Name, ''), tkUser, d, err) then
      begin
        d.SourceFile := sr.Name;
        if Length(d.Warnings) > 0 then
          ThemeDiagnostics.Add(Format('%s: %d warnings (%s)', [sr.Name, Length(d.Warnings), d.Warnings[0]]));
        AddTheme(d, 'user');
      end
      else
        ThemeDiagnostics.Add(sr.Name + ': ' + err);
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

procedure InitThemes(const APreferredName: string);
begin
  GThemes := nil;
  ThemeDiagnostics.Clear;
  AddBuiltin('Rotten', RottenBase);
  AddBuiltin('Light', LightBase);
  AddBuiltin('Nord', NordBase);
  if ThemesEmbedded then LoadEmbedded;
  LoadUserThemes;
  if (APreferredName = '') or not ApplyThemeByName(APreferredName) then
    ApplyThemeIndex(0);
end;

function ThemeCount: Integer;
begin
  Result := Length(GThemes);
end;

function ThemeName(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(GThemes)) then
    Result := GThemes[AIndex].Name
  else
    Result := '';
end;

function ThemeKind(AIndex: Integer): TThemeKind;
begin
  Result := GThemes[AIndex].Kind;
end;

function CurrentThemeIndex: Integer;
begin
  Result := GCurrent;
end;

function CurrentThemeName: string;
begin
  Result := ThemeName(GCurrent);
end;

function C(const AColors: TThemeColors; T: TThemeToken): LongInt; inline;
begin
  Result := RgbToBgr(LongWord(AColors[T]));
end;

function ApplyThemeIndex(AIndex: Integer): Boolean;
var
  cs: TThemeColors;
  d: TThemeDef;
  fam: string;
begin
  Result := False;
  if (AIndex < 0) or (AIndex > High(GThemes)) then Exit;
  d := GThemes[AIndex];
  // resolution complete d'abord: aucune globale n'est ecrite si un jeton manque
  cs := ResolveColors(d.Colors);
  clAppBg := C(cs, ttAppBg);
  clAppFg := C(cs, ttAppFg);
  clAccent := C(cs, ttAccent);
  clBorder := C(cs, ttBorder);
  clSideBg := C(cs, ttSideBg);
  clSideText := C(cs, ttSideText);
  clSideTextHi := C(cs, ttSideTextHi);
  clSideSel := C(cs, ttSideSel);
  clSideHover := C(cs, ttSideHover);
  clSideActive := C(cs, ttSideActive);
  clStatusBg := C(cs, ttStatusBg);
  clStatusText := C(cs, ttStatusText);
  clMenuBg := C(cs, ttMenuBg);
  clMenuText := C(cs, ttMenuText);
  clMenuHover := C(cs, ttMenuHover);
  clMenuPopupBg := C(cs, ttMenuPopupBg);
  clMenuDisabled := C(cs, ttMenuDisabled);
  clMenuSep := C(cs, ttMenuSep);
  clTabStrip := C(cs, ttTabStrip);
  clTabActive := C(cs, ttTabActive);
  clTabInactive := C(cs, ttTabInactive);
  clTabHover := C(cs, ttTabHover);
  clTabActiveText := C(cs, ttTabActiveText);
  clTabInactiveText := C(cs, ttTabInactiveText);
  clTabIcon := C(cs, ttTabIcon);
  clTabIconHi := C(cs, ttTabIconHi);
  clTabDead := C(cs, ttTabDead);
  clEditorBg := C(cs, ttEditorBg);
  clEditorFg := C(cs, ttEditorFg);
  clCurrentLine := C(cs, ttCurrentLine);
  clSelectionBg := C(cs, ttSelectionBg);
  clSelectionFg := C(cs, ttSelectionFg);
  clCaret := C(cs, ttCaret);
  clGutterBg := C(cs, ttGutterBg);
  clGutterFg := C(cs, ttGutterFg);
  clCodeComment := C(cs, ttCodeComment);
  clCodeString := C(cs, ttCodeString);
  clCodeNumber := C(cs, ttCodeNumber);
  clCodeKeyword := C(cs, ttCodeKeyword);
  clCodeType := C(cs, ttCodeType);
  clCodeInvalid := C(cs, ttCodeInvalid);
  clCodeFunction := C(cs, ttCodeFunction);
  clCodeVariable := C(cs, ttCodeVariable);
  clDiffEqual := C(cs, ttDiffEqual);
  clDiffAdded := C(cs, ttDiffAdded);
  clDiffAbsent := C(cs, ttDiffAbsent);
  clDiffChanged := C(cs, ttDiffChanged);
  clDiffWarning := C(cs, ttDiffWarning);
  clDiffUnknown := C(cs, ttDiffUnknown);
  clTermBg := C(cs, ttTermBg);
  clTermFg := C(cs, ttTermFg);
  clPanelBg := C(cs, ttPanelBg);
  clPanelAltRow := C(cs, ttPanelAltRow);
  clPanelHeader := C(cs, ttPanelHeader);
  clPanelHeaderText := C(cs, ttPanelHeaderText);
  clPanelGrid := C(cs, ttPanelGrid);
  clTextSecondary := C(cs, ttTextSecondary);
  clSelActive := C(cs, ttSelActive);
  clSelInactive := C(cs, ttSelInactive);
  clSelText := C(cs, ttSelText);
  clScpOk := C(cs, ttScpOk);
  clScpWarn := C(cs, ttScpWarn);
  clScpErr := C(cs, ttScpErr);
  clProgressBar := C(cs, ttProgressBar);
  clProgressTrack := C(cs, ttProgressTrack);
  clSelectionInactive := C(cs, ttSelectionInactive);
  clGutterFgCur := C(cs, ttGutterFgCur);
  clGutterCurBg := C(cs, ttGutterCurBg);
  clRightEdge := C(cs, ttRightEdge);
  clTabActiveDim := C(cs, ttTabActiveDim);
  clTabActiveTextDim := C(cs, ttTabActiveTextDim);
  clModifiedDot := C(cs, ttModifiedDot);
  clTabGlyph := C(cs, ttTabGlyph);
  clMacroRec := C(cs, ttMacroRec);
  clTabLock := C(cs, ttTabLock);
  clTabLockMod := C(cs, ttTabLockMod);
  clMinimapViewport := C(cs, ttMinimapViewport);
  clFindOutline := C(cs, ttFindOutline);
  clFindBtn := C(cs, ttFindBtn);
  clFindBtnText := C(cs, ttFindBtnText);
  clFindToggleOn := C(cs, ttFindToggleOn);
  clFindToggleOnText := C(cs, ttFindToggleOnText);
  clFindToggleOff := C(cs, ttFindToggleOff);
  clFindToggleOffText := C(cs, ttFindToggleOffText);
  clSideHeader := C(cs, ttSideHeader);
  clCodeConstant := C(cs, ttCodeConstant);
  clCodeOperator := C(cs, ttCodeOperator);
  if MonaspaceAvailable then
  begin
    fam := '';
    if d.UiFamily <> '' then fam := ResolveMonaspace(d.UiFamily);
    if fam = '' then fam := MonaspaceDefaultFamily;
    RSUiFontName := fam;
    fam := '';
    if d.EditorFamily <> '' then fam := ResolveMonaspace(d.EditorFamily);
    if fam = '' then fam := MonaspaceTerminalDefaultFamily;
    RSEditorFontName := fam;
    // la famille choisie par l'utilisateur prime sur celle du theme
    if PrefEditorFontKey <> '' then
    begin
      fam := ResolveMonaspace(PrefEditorFontKey);
      if fam <> '' then RSEditorFontName := fam;
    end;
  end;
  // taille du theme bornee comme celle de l'utilisateur (un theme utilisateur
  // peut en declarer une de 6 a 72)
  if d.EditorSize > 0 then
    RSEditorFontSize := ClampEditorFontSize(d.EditorSize)
  else
    RSEditorFontSize := 12;
  // les tailles choisies par l'utilisateur priment sur celles du theme
  if PrefEditorFontSize > 0 then
    RSEditorFontSize := ClampEditorFontSize(PrefEditorFontSize);
  if PrefUiFontSize = 0 then
    RSUiFontSize := 0
  else
    RSUiFontSize := ClampFontSize(PrefUiFontSize);
  RSTreeFontSize := RSUiFontSize;
  SyncNativeAppearance;
  GCurrent := AIndex;
  Result := True;
end;

function ThemePreview(AIndex: Integer; out AColors: TThemeColors; out AUiFont,
  AEditorFont: string): Boolean;
var
  cs: TThemeColors;
  t: TThemeToken;
  d: TThemeDef;
begin
  Result := (AIndex >= 0) and (AIndex <= High(GThemes));
  AUiFont := RSUiFontName;
  AEditorFont := RSEditorFontName;
  if not Result then
  begin
    AColors := EmptyColors;
    Exit;
  end;
  d := GThemes[AIndex];
  cs := ResolveColors(d.Colors);
  for t := Low(TThemeToken) to High(TThemeToken) do
    AColors[t] := C(cs, t);
  if MonaspaceAvailable then
  begin
    if d.UiFamily <> '' then AUiFont := ResolveMonaspace(d.UiFamily)
    else AUiFont := MonaspaceDefaultFamily;
    if AUiFont = '' then AUiFont := MonaspaceDefaultFamily;
    if d.EditorFamily <> '' then AEditorFont := ResolveMonaspace(d.EditorFamily)
    else AEditorFont := MonaspaceTerminalDefaultFamily;
    if AEditorFont = '' then AEditorFont := MonaspaceTerminalDefaultFamily;
  end;
end;

function ThemeWarnings(AIndex: Integer): TStringArray;
var
  i: Integer;
begin
  Result := nil;
  if (AIndex < 0) or (AIndex > High(GThemes)) then Exit;
  SetLength(Result, Length(GThemes[AIndex].Warnings));
  for i := 0 to High(GThemes[AIndex].Warnings) do
    Result[i] := GThemes[AIndex].Warnings[i];
end;

function ApplyThemeByName(const AName: string): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(GThemes) do
    if SameText(GThemes[i].Name, AName) then
      Exit(ApplyThemeIndex(i));
  Result := False;
end;

finalization
  GDiagnostics.Free;

end.
