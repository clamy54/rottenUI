// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtWizard;

{$mode objfpc}{$H+}

// Echafaudage d'assistant pose dans un TRtDialog, par composition: l'hote garde sa lignee et ses
// controles. Avec une seule page, ni etapes ni Back: un assistant qui sait se faire oublier.

interface

uses
  Classes, SysUtils, Controls, Forms, StdCtrls, ExtCtrls, Graphics, uUiKit, uRtButton, uIcons;

type
  TRtWizardButtons = record
    BackEnabled: Boolean;
    NextEnabled: Boolean;
    NextVisible: Boolean;
    NextCaption: string;
  end;

  // Validation, recul compris (ATo < AFrom). AAllow a False: on reste sur AFrom.
  TRtWizardLeaveEvent = procedure(Sender: TObject; AFrom, ATo: Integer; var AAllow: Boolean) of object;
  // AButtons arrive avec l'etat par defaut de la page: l'hote y retranche ce que son metier interdit.
  TRtWizardButtonsEvent = procedure(Sender: TObject; var AButtons: TRtWizardButtons) of object;

  TRtWizard = class(TComponent)
  private
    FDialog: TRtDialog;
    FBanner: TPanel;
    FBannerIcon: TRtIcon;
    FBannerLabels: array[0..2] of TLabel;
    FStepper: TRtStepper;
    FTitle: TLabel;
    FPages: array of TPanel;
    FSteps, FTitles, FNextCaptions: array of string;
    FIndex: Integer;
    FBack, FNext, FClose: TButton;
    FNextText, FFinishText: string;
    FOnLeavePage: TRtWizardLeaveEvent;
    FOnPageShown, FOnFinish: TNotifyEvent;
    FOnUpdateButtons: TRtWizardButtonsEvent;
    procedure NextClick(Sender: TObject);
    procedure BackClick(Sender: TObject);
    function GetPage(AIndex: Integer): TPanel;
    function GetPageCount: Integer;
  public
    constructor Create(ADialog: TRtDialog); reintroduce;
    // Icone et trois lignes (intitule, titre gras, detail), rangees dans le corps a l'endroit de l'appel.
    procedure SetBanner(const AIconId: string; AIconSize: Integer; const ACaption, ATitle, ADetail: string);
    // Le premier appel pose les etapes sous ce que le corps contient deja. ANextCaption: Next sur cette page.
    function AddPage(const AStep: string; const ATitle: string = '';
      const ANextCaption: string = ''): TPanel;
    // AFinish: libelle de Next sur la derniere page
    procedure AddButtons(const AClose: string; ACloseResult: TModalResult; const AFinish: string = '';
      const ANext: string = ''; const ABack: string = '');
    procedure ShowPage(AIndex: Integer);
    // Vrai si la page a change. Sur la derniere, Next declenche OnFinish.
    function GoNext: Boolean;
    function GoBack: Boolean;
    procedure UpdateButtons;
    procedure RefreshTheme;
    property PageIndex: Integer read FIndex;
    property PageCount: Integer read GetPageCount;
    property Pages[AIndex: Integer]: TPanel read GetPage;
    property Stepper: TRtStepper read FStepper;
    property BackButton: TButton read FBack;
    property NextButton: TButton read FNext;
    property CloseButton: TButton read FClose;
    property OnLeavePage: TRtWizardLeaveEvent read FOnLeavePage write FOnLeavePage;
    property OnPageShown: TNotifyEvent read FOnPageShown write FOnPageShown;
    property OnFinish: TNotifyEvent read FOnFinish write FOnFinish;
    property OnUpdateButtons: TRtWizardButtonsEvent read FOnUpdateButtons write FOnUpdateButtons;
  end;

resourcestring
  rsRtWizardBack = '< Back';
  rsRtWizardNext = 'Next >';
  rsRtWizardFinish = 'Finish';

implementation

uses
  uTheme;

constructor TRtWizard.Create(ADialog: TRtDialog);
begin
  inherited Create(ADialog);
  FDialog := ADialog;
  FNextText := rsRtWizardNext;
  FFinishText := rsRtWizardFinish;
end;

procedure TRtWizard.SetBanner(const AIconId: string; AIconSize: Integer; const ACaption, ATitle,
  ADetail: string);
var
  txt: TPanel;
  i, h: Integer;
begin
  if FBanner = nil then
  begin
    FBanner := MakePanel(FDialog.Body, alTop, 60);
    FBannerIcon := TRtIcon.Create(FBanner);
    FBannerIcon.Parent := FBanner;
    FBannerIcon.Align := alLeft;
    txt := MakePanel(FBanner, alClient);
    for i := 0 to 2 do
      FBannerLabels[i] := MakeDataLabel(txt, '');
    FBannerLabels[0].Font.Color := DialogStateColor(usMuted);
    FBannerLabels[1].Font.Style := [fsBold];
    FBannerLabels[2].Font.Color := DialogStateColor(usMuted);
  end;
  FBannerIcon.SetIcon(AIconId, AIconSize, clAccent);
  FBannerLabels[0].Caption := ACaption;
  FBannerLabels[1].Caption := ATitle;
  FBannerLabels[2].Caption := ADetail;
  for i := 0 to 2 do
    FBannerLabels[i].Visible := FBannerLabels[i].Caption <> '';
  h := StackedLabelsHeight(FBannerLabels[0].Parent) + 6;
  if h < FBannerIcon.Width then h := FBannerIcon.Width;
  FBanner.Height := h;
end;

function TRtWizard.AddPage(const AStep, ATitle, ANextCaption: string): TPanel;
var
  n: Integer;
begin
  if FStepper = nil then
  begin
    FStepper := TRtStepper.Create(FDialog.Body);
    FStepper.Parent := FDialog.Body;
    StackTop(FStepper);
    FStepper.Align := alTop;
    FStepper.BorderSpacing.Top := 6;
    FStepper.Height := FStepper.PreferredHeight;
    FTitle := MakeLabel(FDialog.Body, '');
    FTitle.Font.Style := [fsBold];
    FTitle.BorderSpacing.Top := 6;
    FTitle.Visible := False;
  end;
  n := Length(FPages);
  SetLength(FPages, n + 1);
  SetLength(FSteps, n + 1);
  SetLength(FTitles, n + 1);
  SetLength(FNextCaptions, n + 1);
  Result := MakePanel(FDialog.Body, alClient);
  FPages[n] := Result;
  FSteps[n] := AStep;
  FTitles[n] := ATitle;
  FNextCaptions[n] := ANextCaption;
  FStepper.SetSteps(FSteps);
  FStepper.Visible := n > 0;
  // decide une fois pour toutes: un libelle alTop qui clignote d'une page a l'autre perd sa place
  if ATitle <> '' then FTitle.Visible := True;
end;

procedure TRtWizard.AddButtons(const AClose: string; ACloseResult: TModalResult; const AFinish,
  ANext, ABack: string);
begin
  if FNext <> nil then Exit;
  if AFinish <> '' then FFinishText := AFinish;
  if ANext <> '' then FNextText := ANext;
  FClose := FDialog.AddButton(AClose, ACloseResult, False, True);
  FNext := FDialog.AddButton(FNextText, mrNone, True);
  FNext.OnClick := @NextClick;
  if ABack <> '' then FBack := FDialog.AddButton(ABack, mrNone)
  else FBack := FDialog.AddButton(rsRtWizardBack, mrNone);
  FBack.OnClick := @BackClick;
end;

function TRtWizard.GetPage(AIndex: Integer): TPanel;
begin
  if (AIndex >= 0) and (AIndex < Length(FPages)) then Result := FPages[AIndex] else Result := nil;
end;

function TRtWizard.GetPageCount: Integer;
begin
  Result := Length(FPages);
end;

procedure TRtWizard.ShowPage(AIndex: Integer);
var
  i: Integer;
begin
  if (AIndex < 0) or (AIndex >= Length(FPages)) then Exit;
  FIndex := AIndex;
  for i := 0 to High(FPages) do
    FPages[i].Visible := i = AIndex;
  FTitle.Caption := FTitles[AIndex];
  FStepper.Current := AIndex;
  UpdateButtons;
  if Assigned(FOnPageShown) then FOnPageShown(Self);
end;

procedure TRtWizard.UpdateButtons;
var
  b: TRtWizardButtons;
begin
  if (FNext = nil) or (Length(FPages) = 0) then Exit;
  b.BackEnabled := FIndex > 0;
  b.NextEnabled := True;
  b.NextVisible := True;
  if FNextCaptions[FIndex] <> '' then b.NextCaption := FNextCaptions[FIndex]
  else if FIndex = High(FPages) then b.NextCaption := FFinishText
  else b.NextCaption := FNextText;
  if Assigned(FOnUpdateButtons) then FOnUpdateButtons(Self, b);
  // une seule ecriture par propriete: un bouton qu'on eteint puis rallume perd le focus en route
  FBack.Visible := Length(FPages) > 1;
  FBack.Enabled := b.BackEnabled;
  FNext.Visible := b.NextVisible;
  FNext.Enabled := b.NextEnabled;
  FNext.Caption := b.NextCaption;
end;

function TRtWizard.GoNext: Boolean;
var
  before: Integer;
  allow: Boolean;
begin
  before := FIndex;
  UpdateButtons;
  if (FNext = nil) or not (FNext.Enabled and FNext.Visible) then Exit(False);
  if FIndex >= High(FPages) then
  begin
    if Assigned(FOnFinish) then FOnFinish(Self);
  end
  else
  begin
    allow := True;
    if Assigned(FOnLeavePage) then FOnLeavePage(Self, FIndex, FIndex + 1, allow);
    // le gestionnaire a pu changer de page lui-meme
    if allow and (FIndex = before) then ShowPage(FIndex + 1);
  end;
  Result := FIndex <> before;
end;

function TRtWizard.GoBack: Boolean;
var
  before: Integer;
  allow: Boolean;
begin
  before := FIndex;
  if FIndex = 0 then Exit(False);
  allow := True;
  if Assigned(FOnLeavePage) then FOnLeavePage(Self, FIndex, FIndex - 1, allow);
  if allow and (FIndex = before) then ShowPage(FIndex - 1);
  Result := FIndex <> before;
end;

procedure TRtWizard.NextClick(Sender: TObject);
begin
  GoNext;
end;

procedure TRtWizard.BackClick(Sender: TObject);
begin
  GoBack;
end;

procedure TRtWizard.RefreshTheme;
begin
  if FBannerIcon <> nil then FBannerIcon.IconColor := clAccent;
  if FStepper <> nil then FStepper.Height := FStepper.PreferredHeight;
end;

end.
