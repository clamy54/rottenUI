// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uThemeData;

{$mode objfpc}{$H+}

// Definitions de themes, sans LCL. Un theme est une entree hostile jusqu'a preuve du
// contraire: taille et profondeur bornees, couleurs #RRGGBB strictes, fontes en liste
// blanche, ni script, ni URL, ni chemin. Un theme invalide n'est jamais applique, meme
// a moitie.

interface

uses
  SysUtils;

const
  THEME_MAX_BYTES = 256 * 1024;
  THEME_MAX_DEPTH = 8;

type
  TThemeToken = (
    ttAppBg, ttAppFg, ttAccent, ttBorder,
    ttSideBg, ttSideText, ttSideTextHi, ttSideSel, ttSideHover, ttSideActive,
    ttStatusBg, ttStatusText,
    ttMenuBg, ttMenuText, ttMenuHover, ttMenuPopupBg, ttMenuDisabled, ttMenuSep,
    ttTabStrip, ttTabActive, ttTabInactive, ttTabHover, ttTabActiveText,
    ttTabInactiveText, ttTabIcon, ttTabIconHi, ttTabDead,
    ttEditorBg, ttEditorFg, ttCurrentLine, ttSelectionBg, ttSelectionFg, ttCaret,
    ttGutterBg, ttGutterFg,
    ttCodeComment, ttCodeString, ttCodeNumber, ttCodeKeyword, ttCodeType,
    ttCodeInvalid, ttCodeFunction, ttCodeVariable,
    ttDiffEqual, ttDiffAdded, ttDiffAbsent, ttDiffChanged, ttDiffWarning, ttDiffUnknown,
    ttTermBg, ttTermFg,
    ttPanelBg, ttPanelAltRow, ttPanelHeader, ttPanelHeaderText, ttPanelGrid,
    ttTextSecondary, ttSelActive, ttSelInactive, ttSelText,
    ttScpOk, ttScpWarn, ttScpErr, ttProgressBar, ttProgressTrack,
    // editeur de texte: absents d'un theme, deduits de ses autres couleurs
    ttSelectionInactive, ttGutterFgCur, ttGutterCurBg, ttRightEdge, ttTabActiveDim,
    ttTabActiveTextDim, ttModifiedDot, ttTabGlyph, ttMacroRec, ttTabLock, ttTabLockMod,
    ttMinimapViewport, ttFindOutline, ttFindBtn, ttFindBtnText, ttFindToggleOn,
    ttFindToggleOnText, ttFindToggleOff, ttFindToggleOffText, ttSideHeader,
    ttCodeConstant, ttCodeOperator);

  TThemeColors = array[TThemeToken] of LongInt;

  TThemeKind = (tkBuiltin, tkRottenText, tkUser);

  TThemeDef = record
    Name: string;
    Kind: TThemeKind;
    SourceFile: string;
    Colors: TThemeColors;
    UiFamily: string;
    EditorFamily: string;
    EditorSize: Integer;
    Warnings: array of string;
  end;

const
  TOKEN_KEYS: array[TThemeToken] of string = (
    'appBg', 'appFg', 'accent', 'border',
    'sideBg', 'sideText', 'sideTextHi', 'sideSel', 'sideHover', 'sideActive',
    'statusBg', 'statusText',
    'menuBg', 'menuText', 'menuHover', 'menuPopupBg', 'menuDisabled', 'menuSep',
    'tabStrip', 'tabActive', 'tabInactive', 'tabHover', 'tabActiveText',
    'tabInactiveText', 'tabIcon', 'tabIconHi', 'tabDead',
    'editorBg', 'editorFg', 'currentLine', 'selectionBg', 'selectionFg', 'caret',
    'gutterBg', 'gutterFg',
    'codeComment', 'codeString', 'codeNumber', 'codeKeyword', 'codeType',
    'codeInvalid', 'codeFunction', 'codeVariable',
    'diffEqual', 'diffAdded', 'diffAbsent', 'diffChanged', 'diffWarning', 'diffUnknown',
    'termBg', 'termFg',
    'panelBg', 'panelAltRow', 'panelHeader', 'panelHeaderText', 'panelGrid',
    'textSecondary', 'selActive', 'selInactive', 'selText',
    'scpOk', 'scpWarn', 'scpErr', 'progressBar', 'progressTrack',
    'selectionInactive', 'gutterFgCur', 'gutterCurBg', 'rightEdge', 'tabActiveDim',
    'tabActiveTextDim', 'modifiedDot', 'tabGlyph', 'macroRec', 'tabLock', 'tabLockMod',
    'minimapViewport', 'findOutline', 'findBtn', 'findBtnText', 'findToggleOn',
    'findToggleOnText', 'findToggleOff', 'findToggleOffText', 'sideHeader',
    'codeConstant', 'codeOperator');

  FONT_FAMILY_KEYS: array[0..5] of string =
    ('Neon', 'Argon', 'Xenon', 'Radon', 'Krypton', 'JetBrainsMono');

function RgbToBgr(ARgb: LongWord): LongInt;
function BgrToRgb(ABgr: LongInt): LongWord;
function ParseHexColor(const S: string; out ARgb: LongWord): Boolean;
function EmptyColors: TThemeColors;
function RottenBase: TThemeColors;
function LightBase: TThemeColors;
function NordBase: TThemeColors;
function ResolveColors(const AColors: TThemeColors): TThemeColors;
function IsDarkRgb(ARgb: LongWord): Boolean;
function ParseThemeJson(const AText, AFallbackName: string; AKind: TThemeKind;
  out ADef: TThemeDef; out AError: string): Boolean;

implementation

uses
  fpjson, jsonparser, uJsonGuard;

function RgbToBgr(ARgb: LongWord): LongInt;
begin
  Result := LongInt(((ARgb shr 16) and $FF) or (((ARgb shr 8) and $FF) shl 8) or
    ((ARgb and $FF) shl 16));
end;

function BgrToRgb(ABgr: LongInt): LongWord;
begin
  Result := (LongWord(ABgr and $FF) shl 16) or (LongWord((ABgr shr 8) and $FF) shl 8) or
    LongWord((ABgr shr 16) and $FF);
end;

function ParseHexColor(const S: string; out ARgb: LongWord): Boolean;
var
  i: Integer;
  v: LongWord;
  c: Char;
begin
  Result := False;
  ARgb := 0;
  if (Length(S) <> 7) or (S[1] <> '#') then Exit;
  v := 0;
  for i := 2 to 7 do
  begin
    c := S[i];
    case c of
      '0'..'9': v := (v shl 4) or LongWord(Ord(c) - Ord('0'));
      'a'..'f': v := (v shl 4) or LongWord(Ord(c) - Ord('a') + 10);
      'A'..'F': v := (v shl 4) or LongWord(Ord(c) - Ord('A') + 10);
    else
      Exit;
    end;
  end;
  ARgb := v;
  Result := True;
end;

function EmptyColors: TThemeColors;
var
  t: TThemeToken;
begin
  for t := Low(t) to High(t) do
    Result[t] := -1;
end;

function IsDarkRgb(ARgb: LongWord): Boolean;
begin
  Result := (((ARgb shr 16) and $FF) * 299 + ((ARgb shr 8) and $FF) * 587 +
    (ARgb and $FF) * 114) div 1000 < 128;
end;

procedure SetC(var C: TThemeColors; T: TThemeToken; ARgb: LongWord);
begin
  C[T] := LongInt(ARgb);
end;

function RottenBase: TThemeColors;
begin
  Result := EmptyColors;
  SetC(Result, ttAppBg, $1E1E1E); SetC(Result, ttAppFg, $D4D4D4);
  SetC(Result, ttAccent, $FB9E6B); SetC(Result, ttBorder, $161616);
  SetC(Result, ttSideBg, $252526); SetC(Result, ttSideText, $CCCCCC);
  SetC(Result, ttSideTextHi, $FFFFFF); SetC(Result, ttSideSel, $37414F);
  SetC(Result, ttSideHover, $2D2D30); SetC(Result, ttSideActive, $8FB84E);
  SetC(Result, ttStatusBg, $252526); SetC(Result, ttStatusText, $9D9D9D);
  SetC(Result, ttMenuBg, $252526); SetC(Result, ttMenuText, $CCCCCC);
  SetC(Result, ttMenuHover, $37414F); SetC(Result, ttMenuPopupBg, $2D2D30);
  SetC(Result, ttMenuDisabled, $808080); SetC(Result, ttMenuSep, $454549);
  SetC(Result, ttTabStrip, $3A3A3D); SetC(Result, ttTabActive, $646469);
  SetC(Result, ttTabInactive, $4C4C50); SetC(Result, ttTabHover, $59595E);
  SetC(Result, ttTabActiveText, $FFFFFF); SetC(Result, ttTabInactiveText, $D2D2D2);
  SetC(Result, ttTabIcon, $6A9955); SetC(Result, ttTabIconHi, $7AB069);
  SetC(Result, ttTabDead, $F14C4C);
  SetC(Result, ttEditorBg, $1E1E1E); SetC(Result, ttEditorFg, $D4D4D4);
  SetC(Result, ttCurrentLine, $282828); SetC(Result, ttSelectionBg, $FB9E6B);
  SetC(Result, ttSelectionFg, $1E1E1E); SetC(Result, ttCaret, $AEAFAD);
  SetC(Result, ttGutterBg, $1E1E1E); SetC(Result, ttGutterFg, $858585);
  SetC(Result, ttCodeComment, $6A9955); SetC(Result, ttCodeString, $CE9178);
  SetC(Result, ttCodeNumber, $B5CEA8); SetC(Result, ttCodeKeyword, $569CD6);
  SetC(Result, ttCodeType, $4EC9B0); SetC(Result, ttCodeInvalid, $F44747);
  SetC(Result, ttCodeFunction, $DCDCAA); SetC(Result, ttCodeVariable, $9CDCFE);
  SetC(Result, ttDiffEqual, $8FB84E); SetC(Result, ttDiffAdded, $4EC9B0);
  SetC(Result, ttDiffAbsent, $F14C4C); SetC(Result, ttDiffChanged, $FB9E6B);
  SetC(Result, ttDiffWarning, $DCDCAA); SetC(Result, ttDiffUnknown, $9D9D9D);
  SetC(Result, ttTermBg, $1E1E1E); SetC(Result, ttTermFg, $D4D4D4);
  SetC(Result, ttPanelBg, $1E1E1E); SetC(Result, ttPanelAltRow, $232323);
  SetC(Result, ttPanelHeader, $2D2D30); SetC(Result, ttPanelHeaderText, $C8C8C8);
  SetC(Result, ttPanelGrid, $333336); SetC(Result, ttTextSecondary, $9D9D9D);
  SetC(Result, ttSelActive, $37414F); SetC(Result, ttSelInactive, $2E3238);
  SetC(Result, ttSelText, $FFFFFF);
  SetC(Result, ttScpOk, $8FB84E); SetC(Result, ttScpWarn, $D7A03A);
  SetC(Result, ttScpErr, $F14C4C);
  SetC(Result, ttProgressBar, $FB9E6B); SetC(Result, ttProgressTrack, $3A3A3D);
  SetC(Result, ttSelectionInactive, $2C3B4C); SetC(Result, ttGutterFgCur, $C6C6C6);
  SetC(Result, ttGutterCurBg, $282828); SetC(Result, ttRightEdge, $2A2A2A);
  SetC(Result, ttModifiedDot, $6A9955); SetC(Result, ttTabGlyph, $D4D4D4);
  SetC(Result, ttMacroRec, $F44747); SetC(Result, ttTabLock, $F44747);
  SetC(Result, ttTabLockMod, $CCA700); SetC(Result, ttMinimapViewport, $3A3A3A);
  SetC(Result, ttFindOutline, $FAC761); SetC(Result, ttFindBtn, $37373D);
  SetC(Result, ttFindBtnText, $D4D4D4); SetC(Result, ttFindToggleOn, $FB9E6B);
  SetC(Result, ttFindToggleOnText, $1E1E1E); SetC(Result, ttFindToggleOff, $37373D);
  SetC(Result, ttFindToggleOffText, $9D9D9D); SetC(Result, ttSideHeader, $7A7A7A);
  SetC(Result, ttCodeConstant, $4FC1FF); SetC(Result, ttCodeOperator, $D4D4D4);
end;

function LightBase: TThemeColors;
begin
  Result := EmptyColors;
  SetC(Result, ttAppBg, $F3F3F3); SetC(Result, ttAppFg, $1E1E1E);
  SetC(Result, ttAccent, $C05A1E); SetC(Result, ttBorder, $C8C8C8);
  SetC(Result, ttSideBg, $ECECEC); SetC(Result, ttSideText, $2B2B2B);
  SetC(Result, ttSideTextHi, $000000); SetC(Result, ttSideSel, $CFE3FA);
  SetC(Result, ttSideHover, $E0E0E0); SetC(Result, ttSideActive, $1F7A1F);
  SetC(Result, ttStatusBg, $E0E0E0); SetC(Result, ttStatusText, $404040);
  SetC(Result, ttMenuBg, $F3F3F3); SetC(Result, ttMenuText, $1E1E1E);
  SetC(Result, ttMenuHover, $CFE3FA); SetC(Result, ttMenuPopupBg, $FFFFFF);
  SetC(Result, ttMenuDisabled, $9A9A9A); SetC(Result, ttMenuSep, $D7D7D7);
  SetC(Result, ttTabStrip, $E4E4E4); SetC(Result, ttTabActive, $FFFFFF);
  SetC(Result, ttTabInactive, $DADADA); SetC(Result, ttTabHover, $EDEDED);
  SetC(Result, ttTabActiveText, $1E1E1E); SetC(Result, ttTabInactiveText, $6A6A6A);
  SetC(Result, ttTabIcon, $4E8A3A); SetC(Result, ttTabIconHi, $3D7A2D);
  SetC(Result, ttTabDead, $C62828);
  SetC(Result, ttEditorBg, $FFFFFF); SetC(Result, ttEditorFg, $1E1E1E);
  SetC(Result, ttCurrentLine, $F2F2F2); SetC(Result, ttSelectionBg, $ADD6FF);
  SetC(Result, ttSelectionFg, $000000); SetC(Result, ttCaret, $000000);
  SetC(Result, ttGutterBg, $F7F7F7); SetC(Result, ttGutterFg, $6E7681);
  SetC(Result, ttCodeComment, $008000); SetC(Result, ttCodeString, $A31515);
  SetC(Result, ttCodeNumber, $098658); SetC(Result, ttCodeKeyword, $0000FF);
  SetC(Result, ttCodeType, $267F99); SetC(Result, ttCodeInvalid, $CD3131);
  SetC(Result, ttCodeFunction, $795E26); SetC(Result, ttCodeVariable, $001080);
  SetC(Result, ttDiffEqual, $1F7A1F); SetC(Result, ttDiffAdded, $0B6E7A);
  SetC(Result, ttDiffAbsent, $C62828); SetC(Result, ttDiffChanged, $B35300);
  SetC(Result, ttDiffWarning, $8A6D00); SetC(Result, ttDiffUnknown, $6A6A6A);
  SetC(Result, ttTermBg, $FBFBFB); SetC(Result, ttTermFg, $2B2B2B);
  SetC(Result, ttPanelBg, $FFFFFF); SetC(Result, ttPanelAltRow, $F5F5F5);
  SetC(Result, ttPanelHeader, $E8E8E8); SetC(Result, ttPanelHeaderText, $2B2B2B);
  SetC(Result, ttPanelGrid, $D8D8D8); SetC(Result, ttTextSecondary, $6A6A6A);
  SetC(Result, ttSelActive, $CFE3FA); SetC(Result, ttSelInactive, $E2E6EB);
  SetC(Result, ttSelText, $101010);
  SetC(Result, ttScpOk, $1F7A1F); SetC(Result, ttScpWarn, $9A6A00);
  SetC(Result, ttScpErr, $C42B1C);
  SetC(Result, ttProgressBar, $C05A1E); SetC(Result, ttProgressTrack, $D8D8D8);
end;

function NordBase: TThemeColors;
begin
  Result := RottenBase;
  SetC(Result, ttAppBg, $2E3440); SetC(Result, ttAppFg, $D8DEE9);
  SetC(Result, ttAccent, $88C0D0); SetC(Result, ttBorder, $232831);
  SetC(Result, ttSideBg, $2B303B); SetC(Result, ttSideText, $D8DEE9);
  SetC(Result, ttSideTextHi, $ECEFF4); SetC(Result, ttSideSel, $434C5E);
  SetC(Result, ttSideHover, $3B4252); SetC(Result, ttSideActive, $A3BE8C);
  SetC(Result, ttStatusBg, $2B303B); SetC(Result, ttStatusText, $A6B0C0);
  SetC(Result, ttMenuBg, $2B303B); SetC(Result, ttMenuText, $D8DEE9);
  SetC(Result, ttMenuHover, $434C5E); SetC(Result, ttMenuPopupBg, $353B49);
  SetC(Result, ttMenuDisabled, $7B8497); SetC(Result, ttMenuSep, $434C5E);
  SetC(Result, ttTabStrip, $2B303B); SetC(Result, ttTabActive, $3B4252);
  SetC(Result, ttTabInactive, $2E3440); SetC(Result, ttTabHover, $353B49);
  SetC(Result, ttTabActiveText, $ECEFF4); SetC(Result, ttTabInactiveText, $8893A5);
  SetC(Result, ttTabIcon, $A3BE8C); SetC(Result, ttTabIconHi, $B7CE9F);
  SetC(Result, ttTabDead, $BF616A);
  SetC(Result, ttEditorBg, $2E3440); SetC(Result, ttEditorFg, $D8DEE9);
  SetC(Result, ttCurrentLine, $3B4252); SetC(Result, ttSelectionBg, $434C5E);
  SetC(Result, ttSelectionFg, $ECEFF4); SetC(Result, ttCaret, $D8DEE9);
  SetC(Result, ttGutterBg, $2E3440); SetC(Result, ttGutterFg, $4C566A);
  SetC(Result, ttCodeComment, $616E88); SetC(Result, ttCodeString, $A3BE8C);
  SetC(Result, ttCodeNumber, $B48EAD); SetC(Result, ttCodeKeyword, $81A1C1);
  SetC(Result, ttCodeType, $8FBCBB); SetC(Result, ttCodeInvalid, $BF616A);
  SetC(Result, ttCodeFunction, $88C0D0); SetC(Result, ttCodeVariable, $D8DEE9);
  SetC(Result, ttDiffEqual, $A3BE8C); SetC(Result, ttDiffAdded, $8FBCBB);
  SetC(Result, ttDiffAbsent, $BF616A); SetC(Result, ttDiffChanged, $D08770);
  SetC(Result, ttDiffWarning, $EBCB8B); SetC(Result, ttDiffUnknown, $81879B);
  SetC(Result, ttTermBg, $2E3440); SetC(Result, ttTermFg, $D8DEE9);
  SetC(Result, ttPanelBg, $2E3440); SetC(Result, ttPanelAltRow, $333B49);
  SetC(Result, ttPanelHeader, $3B4252); SetC(Result, ttPanelHeaderText, $E5E9F0);
  SetC(Result, ttPanelGrid, $434C5E); SetC(Result, ttTextSecondary, $A6B0C0);
  SetC(Result, ttSelActive, $434C5E); SetC(Result, ttSelInactive, $3A4051);
  SetC(Result, ttSelText, $ECEFF4);
  SetC(Result, ttScpOk, $A3BE8C); SetC(Result, ttScpWarn, $EBCB8B);
  SetC(Result, ttScpErr, $BF616A);
  SetC(Result, ttProgressBar, $88C0D0); SetC(Result, ttProgressTrack, $3B4252);
  SetC(Result, ttSelectionInactive, $3B4252); SetC(Result, ttGutterFgCur, $D8DEE9);
  SetC(Result, ttGutterCurBg, $3B4252); SetC(Result, ttRightEdge, $434C5E);
  SetC(Result, ttModifiedDot, $A3BE8C); SetC(Result, ttTabGlyph, $D8DEE9);
  SetC(Result, ttMacroRec, $BF616A); SetC(Result, ttTabLock, $BF616A);
  SetC(Result, ttTabLockMod, $EBCB8B); SetC(Result, ttMinimapViewport, $434C5E);
  SetC(Result, ttFindOutline, $88C0D0); SetC(Result, ttFindBtn, $3B4252);
  SetC(Result, ttFindBtnText, $D8DEE9); SetC(Result, ttFindToggleOn, $434C5E);
  SetC(Result, ttFindToggleOnText, $88C0D0); SetC(Result, ttFindToggleOff, $3B4252);
  SetC(Result, ttFindToggleOffText, $616E88); SetC(Result, ttSideHeader, $616B85);
  SetC(Result, ttCodeConstant, $B48EAD); SetC(Result, ttCodeOperator, $81A1C1);
end;

// APct % de A, le reste de B
function MixRgb(A, B: LongInt; APct: Integer): LongInt;
begin
  Result :=
    ((((A shr 16) and $FF) * APct + ((B shr 16) and $FF) * (100 - APct)) div 100) shl 16 or
    ((((A shr 8) and $FF) * APct + ((B shr 8) and $FF) * (100 - APct)) div 100) shl 8 or
    (((A and $FF) * APct + (B and $FF) * (100 - APct)) div 100);
end;

// Absents du theme: tires de SES couleurs, pas de la base. Une constante bleue dans un theme
// vert phosphore, ca se remarque.
procedure DeriveEditorTokens(var C: TThemeColors);

  procedure D(T: TThemeToken; AValue: LongInt);
  begin
    if C[T] < 0 then C[T] := AValue;
  end;

begin
  D(ttSelectionInactive, MixRgb(C[ttSelectionBg], C[ttEditorBg], 35));
  D(ttGutterFgCur, MixRgb(C[ttEditorFg], C[ttGutterBg], 85));
  D(ttGutterCurBg, C[ttCurrentLine]);
  D(ttRightEdge, MixRgb(C[ttEditorFg], C[ttEditorBg], 6));
  D(ttTabActiveDim, MixRgb(C[ttTabActive], C[ttTabInactive], 50));
  D(ttTabActiveTextDim, MixRgb(C[ttTabActiveText], C[ttTabInactiveText], 70));
  D(ttModifiedDot, C[ttTabIcon]);
  D(ttTabGlyph, C[ttTabInactiveText]);
  D(ttMacroRec, C[ttCodeInvalid]);
  D(ttTabLock, C[ttCodeInvalid]);
  D(ttTabLockMod, C[ttScpWarn]);
  D(ttMinimapViewport, MixRgb(C[ttEditorFg], C[ttEditorBg], 14));
  D(ttFindOutline, C[ttAccent]);
  D(ttFindBtn, C[ttSideSel]);
  D(ttFindBtnText, C[ttEditorFg]);
  D(ttFindToggleOn, C[ttSelectionBg]);
  D(ttFindToggleOnText, C[ttSelectionFg]);
  D(ttFindToggleOff, C[ttFindBtn]);
  D(ttFindToggleOffText, C[ttStatusText]);
  D(ttSideHeader, MixRgb(C[ttSideText], C[ttSideBg], 50));
  D(ttCodeConstant, C[ttCodeNumber]);
  D(ttCodeOperator, C[ttEditorFg]);
end;

function ResolveColors(const AColors: TThemeColors): TThemeColors;
var
  base: TThemeColors;
  t: TThemeToken;
  bg: LongInt;
begin
  bg := AColors[ttAppBg];
  if bg < 0 then bg := AColors[ttEditorBg];
  if (bg >= 0) and not IsDarkRgb(LongWord(bg)) then
    base := LightBase
  else
    base := RottenBase;
  for t := Low(t) to High(t) do
    if AColors[t] >= 0 then
      Result[t] := AColors[t]
    else if t >= ttSelectionInactive then
      Result[t] := -1
    else
      Result[t] := base[t];
  // terminal: l'editeur du theme, pas celui de la base
  if AColors[ttTermBg] < 0 then Result[ttTermBg] := Result[ttEditorBg];
  if AColors[ttTermFg] < 0 then Result[ttTermFg] := Result[ttEditorFg];
  DeriveEditorTokens(Result);
end;

procedure AddWarning(var ADef: TThemeDef; const S: string);
begin
  if Length(ADef.Warnings) >= 64 then Exit;
  SetLength(ADef.Warnings, Length(ADef.Warnings) + 1);
  ADef.Warnings[High(ADef.Warnings)] := S;
end;

function ParseThemeJson(const AText, AFallbackName: string; AKind: TThemeKind;
  out ADef: TThemeDef; out AError: string): Boolean;
var
  data: TJSONData;
  obj: TJSONObject;
  i: Integer;
  key, s: string;
  t: TThemeToken;
  found: Boolean;
  rgb: LongWord;
  aliasKey: string;

  function FamilyOk(const AValue: string): Boolean;
  var
    k: Integer;
  begin
    for k := 0 to High(FONT_FAMILY_KEYS) do
      if SameText(AValue, FONT_FAMILY_KEYS[k]) then Exit(True);
    Result := False;
  end;

begin
  Result := False;
  AError := '';
  ADef := Default(TThemeDef);
  ADef.Name := AFallbackName;
  ADef.Kind := AKind;
  ADef.Colors := EmptyColors;
  if Length(AText) > THEME_MAX_BYTES then
  begin
    AError := 'theme file too large';
    Exit;
  end;
  if JsonNestingTooDeep(AText, THEME_MAX_DEPTH) then
  begin
    AError := 'theme nested too deeply';
    Exit;
  end;
  try
    // GetJSON s'etrangle sur un BOM
    if Copy(AText, 1, 3) = #$EF#$BB#$BF then
      data := GetJSON(Copy(AText, 4, MaxInt))
    else
      data := GetJSON(AText);
  except
    AError := 'invalid JSON';
    Exit;
  end;
  try
    if not (data is TJSONObject) then
    begin
      AError := 'a theme must be a JSON object';
      Exit;
    end;
    obj := TJSONObject(data);
    for i := 0 to obj.Count - 1 do
    begin
      key := obj.Names[i];
      if key = 'name' then
      begin
        if obj.Items[i].JSONType <> jtString then
        begin
          AError := '"name" must be a string';
          Exit;
        end;
        s := Trim(obj.Items[i].AsString);
        if (s = '') or (Length(s) > 64) then
        begin
          AError := 'invalid theme name';
          Exit;
        end;
        ADef.Name := s;
        Continue;
      end;
      if (key = 'editorFont') or (key = 'tabFont') or (key = 'sideFont') or (key = 'uiFont') then
      begin
        if (obj.Items[i].JSONType <> jtString) or not FamilyOk(obj.Items[i].AsString) then
        begin
          // Chemin, URL ou famille inconnue: jamais suivi. Un theme choisit une couleur, pas un
          // fichier a charger.
          AError := Format('"%s" must name an embedded font family', [key]);
          Exit;
        end;
        if key = 'editorFont' then
          ADef.EditorFamily := obj.Items[i].AsString
        else
          ADef.UiFamily := obj.Items[i].AsString;
        Continue;
      end;
      if key = 'editorFontSize' then
      begin
        if (obj.Items[i].JSONType <> jtNumber) or (obj.Items[i].AsInteger < 6) or
           (obj.Items[i].AsInteger > 72) then
        begin
          AError := '"editorFontSize" must be between 6 and 72';
          Exit;
        end;
        ADef.EditorSize := obj.Items[i].AsInteger;
        Continue;
      end;
      found := False;
      for t := Low(t) to High(t) do
        if TOKEN_KEYS[t] = key then
        begin
          found := True;
          if (obj.Items[i].JSONType <> jtString) or not ParseHexColor(obj.Items[i].AsString, rgb) then
          begin
            AError := Format('"%s" must be a #RRGGBB color', [key]);
            Exit;
          end;
          if (AKind = tkRottenText) and (t in [ttMenuBg, ttMenuText, ttMenuHover,
             ttMenuPopupBg, ttMenuDisabled, ttMenuSep]) then
            Break;
          ADef.Colors[t] := LongInt(rgb);
          Break;
        end;
      if not found then
      begin
        aliasKey := key;
        AddWarning(ADef, 'unknown key ignored: ' + aliasKey);
      end;
    end;
    if AKind = tkRottenText then
    begin
      if ADef.Colors[ttAppBg] < 0 then ADef.Colors[ttAppBg] := ADef.Colors[ttEditorBg];
      if ADef.Colors[ttAppFg] < 0 then ADef.Colors[ttAppFg] := ADef.Colors[ttEditorFg];
      if ADef.Colors[ttAccent] < 0 then ADef.Colors[ttAccent] := ADef.Colors[ttSelectionBg];
      ADef.Colors[ttMenuBg] := ADef.Colors[ttSideBg];
      ADef.Colors[ttMenuText] := ADef.Colors[ttSideText];
      ADef.Colors[ttMenuHover] := ADef.Colors[ttSideSel];
      ADef.Colors[ttMenuPopupBg] := ADef.Colors[ttSideHover];
      ADef.Colors[ttDiffEqual] := ADef.Colors[ttCodeComment];
      ADef.Colors[ttDiffAbsent] := ADef.Colors[ttCodeInvalid];
      ADef.Colors[ttDiffAdded] := ADef.Colors[ttCodeType];
      ADef.Colors[ttDiffChanged] := ADef.Colors[ttCodeString];
      ADef.Colors[ttDiffWarning] := ADef.Colors[ttCodeFunction];
      ADef.Colors[ttDiffUnknown] := ADef.Colors[ttStatusText];
    end;
    Result := True;
  finally
    data.Free;
  end;
end;

end.
