// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtProgress;

{$mode objfpc}{$H+}

// Suivi d'un travail long: sujet, etat, jauge, detail, element en cours, Stop puis Close.
// Fermer en plein travail vaut Stop, et la fenetre reste jusqu'au bilan: on assume ce qui est fait.

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, Graphics, uUiKit, uRtGauge;

type
  TRtProgressDialog = class(TRtDialog)
  private
    FStatus, FDetail, FCurrent: TLabel;
    FGauge: TRtGauge;
    FStop, FClose: TButton;
    FRunning: Boolean;
    FStoppingText: string;
    FOnStop: TNotifyEvent;
    procedure StopClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    function GetText(AIndex: Integer): string;
    procedure SetText(AIndex: Integer; const AValue: string);
    function GetStopEnabled: Boolean;
    procedure SetStopEnabled(AValue: Boolean);
  public
    // ASubject: ce sur quoi porte le travail, affiche tel quel au-dessus de l'etat
    constructor CreateProgress(AOwner: TComponent; const ACaption, ASubject: string;
      AWidth: Integer = 640; AHeight: Integer = 250);
    function CloseQuery: Boolean; override;
    procedure SetProgress(APosition, AMax: Integer);
    procedure SetIndeterminate;
    // usOk remplit la jauge; tout autre etat la laisse ou elle s'est arretee
    procedure Finish(const AStatus, ASummary: string; AState: TUiState);
    procedure PressStop;
    property StatusText: string index 0 read GetText write SetText;
    property DetailText: string index 1 read GetText write SetText;
    property CurrentText: string index 2 read GetText write SetText;
    property StoppingText: string read FStoppingText write FStoppingText;
    property StopEnabled: Boolean read GetStopEnabled write SetStopEnabled;
    property Running: Boolean read FRunning;
    property Gauge: TRtGauge read FGauge;
    property StopButton: TButton read FStop;
    property CloseButton: TButton read FClose;
    property OnStop: TNotifyEvent read FOnStop write FOnStop;
  end;

resourcestring
  rsRtProgressStop = 'Stop';
  rsRtProgressClose = 'Close';
  rsRtProgressStopping = 'Stopping...';

implementation

constructor TRtProgressDialog.CreateProgress(AOwner: TComponent; const ACaption, ASubject: string;
  AWidth, AHeight: Integer);
begin
  inherited CreateDialog(AOwner, ACaption, AWidth, AHeight);
  FStoppingText := rsRtProgressStopping;
  // Tous des libelles de donnees: un DN ou un nom de fichier s'y invite tot ou tard, "&" compris.
  if ASubject <> '' then MakeDataLabel(Body, ASubject);
  FStatus := MakeDataLabel(Body, '');
  FGauge := TRtGauge.Create(Body);
  FGauge.Parent := Body;
  StackTop(FGauge);
  FGauge.Align := alTop;
  FGauge.Height := 10;
  FGauge.BorderSpacing.Around := 6;
  FGauge.BorderSpacing.Top := 4;
  FGauge.BorderSpacing.Bottom := 4;
  FGauge.Max := 1;
  FDetail := MakeDataLabel(Body, '');
  FCurrent := MakeDataLabel(Body, '');
  FStop := AddButton(rsRtProgressStop, mrNone);
  FStop.OnClick := @StopClick;
  FClose := AddButton(rsRtProgressClose, mrNone);
  FClose.OnClick := @CloseClick;
  FClose.Enabled := False;
  FRunning := True;
  ApplyTheme;
end;

function TRtProgressDialog.GetText(AIndex: Integer): string;
begin
  case AIndex of
    0: Result := FStatus.Caption;
    1: Result := FDetail.Caption;
  else
    Result := FCurrent.Caption;
  end;
end;

procedure TRtProgressDialog.SetText(AIndex: Integer; const AValue: string);
begin
  case AIndex of
    0: FStatus.Caption := AValue;
    1: FDetail.Caption := AValue;
  else
    FCurrent.Caption := AValue;
  end;
end;

function TRtProgressDialog.GetStopEnabled: Boolean;
begin
  Result := FStop.Enabled;
end;

procedure TRtProgressDialog.SetStopEnabled(AValue: Boolean);
begin
  FStop.Enabled := FRunning and AValue;
end;

procedure TRtProgressDialog.SetProgress(APosition, AMax: Integer);
begin
  FGauge.Indeterminate := False;
  FGauge.Max := AMax;
  FGauge.Position := APosition;
end;

procedure TRtProgressDialog.SetIndeterminate;
begin
  FGauge.Indeterminate := True;
end;

procedure TRtProgressDialog.Finish(const AStatus, ASummary: string; AState: TUiState);
begin
  FRunning := False;
  FGauge.Indeterminate := False;
  if AState = usOk then FGauge.Position := FGauge.Max;
  FStatus.Caption := AStatus;
  FDetail.Caption := ASummary;
  FDetail.Font.Color := DialogStateColor(AState);
  FCurrent.Caption := '';
  FStop.Enabled := False;
  FClose.Enabled := True;
  if Showing and FClose.CanFocus then FClose.SetFocus;
end;

procedure TRtProgressDialog.StopClick(Sender: TObject);
begin
  PressStop;
end;

procedure TRtProgressDialog.PressStop;
begin
  if not FRunning or not FStop.Enabled then Exit;
  FStop.Enabled := False;
  FStatus.Caption := FStoppingText;
  if Assigned(FOnStop) then FOnStop(Self);
end;

procedure TRtProgressDialog.CloseClick(Sender: TObject);
begin
  Close;
end;

function TRtProgressDialog.CloseQuery: Boolean;
begin
  if FRunning then
  begin
    PressStop;
    Exit(False);
  end;
  Result := inherited CloseQuery;
end;

end.
