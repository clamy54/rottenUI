// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtLogList;

{$mode objfpc}{$H+}

// Journal borne: la premiere colonne porte l'heure, les suivantes ce que l'appelant fournit,
// le plus recent en haut. Passe la capacite, le plus ancien tombe sans ceremonie.

interface

uses
  Classes, SysUtils, uRtList;

type
  TRtLogList = class(TRtListGrid)
  private
    FEntries: array of TStringArray;
    FNext: Integer;
    FUsed: Integer;
    FTimeFormat: string;
    function GetCapacity: Integer;
    procedure SetCapacity(AValue: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    procedure Append(const AFields: array of string);
    procedure Clear; override;
    function CellText(AIndex, ACol: Integer): string; override;
    procedure RefreshTheme;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property TimeFormat: string read FTimeFormat write FTimeFormat;
  end;

implementation

uses
  uTheme;

constructor TRtLogList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTimeFormat := 'hh:nn:ss';
  SetLength(FEntries, 1000);
end;

function TRtLogList.GetCapacity: Integer;
begin
  Result := Length(FEntries);
end;

procedure TRtLogList.SetCapacity(AValue: Integer);
var
  kept: array of TStringArray;
  i, n: Integer;
begin
  if AValue < 1 then AValue := 1;
  if AValue = Length(FEntries) then Exit;
  n := FUsed;
  if n > AValue then n := AValue;
  kept := nil;
  SetLength(kept, AValue);
  for i := 0 to n - 1 do
    kept[i] := FEntries[(FNext - n + i + Length(FEntries)) mod Length(FEntries)];
  FEntries := kept;
  FUsed := n;
  FNext := n mod AValue;
  Count := FUsed;
end;

procedure TRtLogList.Append(const AFields: array of string);
var
  entry: TStringArray;
  i: Integer;
begin
  entry := nil;
  SetLength(entry, Length(AFields) + 1);
  entry[0] := FormatDateTime(FTimeFormat, Now);
  // Une ligne, un message: personne ne forge de fausse entree de journal a coups de retours a la ligne.
  for i := 0 to High(AFields) do
    entry[i + 1] := StringReplace(StringReplace(AFields[i], #13, ' ', [rfReplaceAll]), #10, ' ',
      [rfReplaceAll]);
  FEntries[FNext] := entry;
  FNext := (FNext + 1) mod Length(FEntries);
  if FUsed < Length(FEntries) then Inc(FUsed);
  Count := FUsed;
end;

procedure TRtLogList.Clear;
var
  i: Integer;
begin
  for i := 0 to High(FEntries) do
    FEntries[i] := nil;
  FNext := 0;
  FUsed := 0;
  inherited Clear;
end;

function TRtLogList.CellText(AIndex, ACol: Integer): string;
var
  entry: TStringArray;
begin
  Result := '';
  if (AIndex < 0) or (AIndex >= FUsed) or (ACol < 0) then Exit;
  entry := FEntries[(FNext - 1 - AIndex + Length(FEntries)) mod Length(FEntries)];
  if ACol < Length(entry) then
    Result := entry[ACol];
end;

procedure TRtLogList.RefreshTheme;
begin
  Color := clSideBg;
  Font.Color := clSideText;
  RowColor := clSideBg;
  RowTextColor := clSideText;
  if RSUiFontName <> '' then Font.Name := RSUiFontName;
  Font.Size := RSUiFontSize;
  RefreshMetrics;
end;

end.
