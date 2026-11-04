// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtFold;

// Comparaison de recherche: le texte replie en minuscules sans accents
// (e accent aigu -> e, c cedille -> c, oe lie -> oe, eszett -> ss...), les
// accents decomposes (texte venu de macOS) retires, les apostrophes et tirets
// typographiques ramenes aux simples. Taper "gen" trouve "Generique" ecrit
// avec ou sans accent, et l'inverse. Sans LCL: utilisable hors interface
// (requetes SQLite, programmes de test).

{$mode objfpc}{$H+}

interface

// Le texte UTF-8 replie pour la recherche.
function FoldText(const AText: string): string;
// ANeedle (replie ou non) apparait dans AText, accents et casse ignores.
function FoldContains(const ANeedle, AText: string): Boolean;

implementation

const
  // U+00C0..U+00FF, une lettre par caractere; '*' : plusieurs lettres
  // (AE, TH, ss), '#' : garde tel quel (multiplication, division).
  LATIN1: string = 'aaaaaa*ceeeeiiiidnooooo#ouuuuy**aaaaaa*ceeeeiiiidnooooo#ouuuuy*y';
  // U+0100..U+017F; '*' : IJ, OE.
  LATIN_EXT_A: string = 'aaaaaaccccccccddddeeeeeeeeeegggggggghhhhiiiiiiiiii**jjkkkllllllllll' +
    'nnnnnnnnnoooooo**rrrrrrssssssssttttttuuuuuuuuuuuuwwyyyzzzzzzs';

function Latin1Multi(ACode: Cardinal): string;
begin
  case ACode of
    $C6, $E6: Result := 'ae';
    $DE, $FE: Result := 'th';
    $DF: Result := 'ss';
  else
    Result := '';
  end;
end;

function Utf8Of(ACode: Cardinal): string;
begin
  if ACode < $80 then Result := Chr(ACode)
  else if ACode < $800 then Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
end;

function FoldCode(ACode: Cardinal; out AText: string): Boolean;
var
  ch: Char;
begin
  Result := True;
  case ACode of
    Ord('A')..Ord('Z'): AText := Chr(ACode + 32);
    $C0..$FF:
      begin
        ch := LATIN1[ACode - $C0 + 1];
        if ch = '*' then AText := Latin1Multi(ACode)
        else if ch = '#' then Result := False
        else AText := ch;
      end;
    $100..$17F:
      begin
        ch := LATIN_EXT_A[ACode - $100 + 1];
        if ch <> '*' then AText := ch
        else if (ACode = $132) or (ACode = $133) then AText := 'ij'
        else AText := 'oe';
      end;
    // Accents decomposes: retires.
    $300..$36F: AText := '';
    // Apostrophes, guillemets simples, tirets, espaces insecables.
    $2018, $2019, $201B, $2032: AText := '''';
    $2010..$2015, $2212: AText := '-';
    $A0, $2007, $202F: AText := ' ';
    // Grec et cyrillique en minuscules (les accents grecs gardes).
    $386: AText := Utf8Of($3AC);
    $388..$38A: AText := Utf8Of(ACode + $25);
    $38C: AText := Utf8Of($3CC);
    $38E, $38F: AText := Utf8Of(ACode + $3F);
    $391..$3A1, $3A3..$3AB: AText := Utf8Of(ACode + $20);
    $400..$40F: AText := Utf8Of(ACode + $50);
    $410..$42F: AText := Utf8Of(ACode + $20);
    $460..$481, $48A..$4BF, $4D0..$52F:
      if not Odd(ACode) then AText := Utf8Of(ACode + 1) else Result := False;
  else
    Result := False;
  end;
end;

function FoldText(const AText: string): string;
var
  i, n, len: Integer;
  code: Cardinal;
  b: Byte;
  rep: string;
begin
  Result := '';
  i := 1;
  len := Length(AText);
  while i <= len do
  begin
    b := Ord(AText[i]);
    // Une sequence UTF-8: sa longueur et son code.
    if b < $80 then begin n := 1; code := b; end
    else if (b and $E0) = $C0 then begin n := 2; code := b and $1F; end
    else if (b and $F0) = $E0 then begin n := 3; code := b and $0F; end
    else if (b and $F8) = $F0 then begin n := 4; code := b and $07; end
    else begin n := 1; code := $FFFFFFFF; end;
    if i + n - 1 > len then n := 1;
    if (n > 1) and (code <> $FFFFFFFF) then
      for b := 1 to n - 1 do
      begin
        if (Ord(AText[i + b]) and $C0) <> $80 then
        begin
          code := $FFFFFFFF;
          n := 1;
          Break;
        end;
        code := (code shl 6) or (Ord(AText[i + b]) and $3F);
      end;
    if (code <> $FFFFFFFF) and FoldCode(code, rep) then
      Result := Result + rep
    else
      Result := Result + Copy(AText, i, n);
    Inc(i, n);
  end;
end;

function FoldContains(const ANeedle, AText: string): Boolean;
var
  needle: string;
begin
  needle := FoldText(ANeedle);
  Result := (needle = '') or (Pos(needle, FoldText(AText)) > 0);
end;

end.
