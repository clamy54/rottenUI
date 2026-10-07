// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtPassword;

{$mode objfpc}{$H+}

// Dialogue de mot de passe sur TRtDialog et TRtSecretEdit: un champ, ou nouveau + confirmation,
// case pour montrer la saisie, ligne d'etat. Ce que vaut un mot de passe reste l'affaire de
// l'appelant: il refuse par OnValidate, et le dialogue reste ouvert, saisie intacte.

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Forms, uUiKit, uRtCheck, uRtSecretEdit;

type
  // ARefusal rempli: refus. ASecret est une copie, effacee au retour du gestionnaire
  TRtPasswordValidate = procedure(Sender: TObject; const ASecret: RawByteString;
    var ARefusal: string) of object;

  TRtPasswordDialog = class(TRtDialog)
  private
    FField, FConfirm: TRtSecretEdit;
    FReveal: TRtCheckBox;
    FStatus: TLabel;
    FMismatchText: string;
    FOnValidate: TRtPasswordValidate;
    procedure RevealClick(Sender: TObject);
    function Accepts: Boolean;
    function Run: Boolean;
  public
    function CloseQuery: Boolean; override;
    function AddText(const AText: string): TLabel;
    function AddField(const ACaption: string): TRtSecretEdit;
    function AddConfirm(const ACaption: string): TRtSecretEdit;
    function AddReveal(const ACaption: string = ''): TRtCheckBox;
    function AddStatus(const AHint: string = ''): TLabel;
    // sans ligne d'etat, le refus part en boite de message
    procedure Refuse(const AMessage: string);
    // le secret sort en copie a effacer par l'appelant, champs vides au retour; sans bouton: OK et Cancel
    function Execute(out ASecret: RawByteString): Boolean; overload;
    function Execute(out ASecret: string): Boolean; overload;
    procedure Wipe;
    property Field: TRtSecretEdit read FField;
    property ConfirmField: TRtSecretEdit read FConfirm;
    property RevealCheck: TRtCheckBox read FReveal;
    property StatusLabel: TLabel read FStatus;
    property MismatchText: string read FMismatchText write FMismatchText;
    property OnValidate: TRtPasswordValidate read FOnValidate write FOnValidate;
  end;

resourcestring
  rsRtPasswordField = 'Password';
  rsRtPasswordShow = 'Show';
  rsRtPasswordOk = 'OK';
  rsRtPasswordCancel = 'Cancel';
  rsRtPasswordMismatch = 'The two passwords differ.';

implementation

uses
  Dialogs, uRtMessage;

const
  LABEL_WIDTH = 110;

function TRtPasswordDialog.AddText(const AText: string): TLabel;
begin
  Result := MakeDataLabel(Body, AText);
end;

function TRtPasswordDialog.AddField(const ACaption: string): TRtSecretEdit;
begin
  FField := MakeSecretRow(Body, ACaption, LABEL_WIDTH);
  FField.AutoSelect := False;
  Result := FField;
end;

function TRtPasswordDialog.AddConfirm(const ACaption: string): TRtSecretEdit;
begin
  FConfirm := MakeSecretRow(Body, ACaption, LABEL_WIDTH);
  FConfirm.AutoSelect := False;
  Result := FConfirm;
end;

function TRtPasswordDialog.AddReveal(const ACaption: string): TRtCheckBox;
begin
  if ACaption <> '' then
    FReveal := MakeCheck(Body, ACaption)
  else
    FReveal := MakeCheck(Body, rsRtPasswordShow);
  FReveal.OnClick := @RevealClick;
  Result := FReveal;
end;

function TRtPasswordDialog.AddStatus(const AHint: string): TLabel;
begin
  FStatus := MakeDataLabel(Body, AHint);
  FStatus.Font.Color := DialogStateColor(usMuted);
  Result := FStatus;
end;

procedure TRtPasswordDialog.RevealClick(Sender: TObject);
begin
  if FField <> nil then FField.Revealed := FReveal.Checked;
  if FConfirm <> nil then FConfirm.Revealed := FReveal.Checked;
end;

procedure TRtPasswordDialog.Refuse(const AMessage: string);
begin
  if FStatus = nil then
    RtMessageDlg(Caption, AMessage, mtWarning, [mbOK], 0)
  else
  begin
    FStatus.Caption := AMessage;
    FStatus.Font.Color := DialogStateColor(usError);
  end;
  // la frappe suivante remplace la saisie au lieu de s'ajouter a un texte que personne ne voit
  if ActiveControl is TRtSecretEdit then TRtSecretEdit(ActiveControl).SelectAll;
end;

function TRtPasswordDialog.Accepts: Boolean;
var
  secret: RawByteString;
  refusal: string;
begin
  if (FConfirm <> nil) and not FField.SameAs(FConfirm) then
  begin
    if FMismatchText <> '' then Refuse(FMismatchText) else Refuse(rsRtPasswordMismatch);
    Exit(False);
  end;
  refusal := '';
  if Assigned(FOnValidate) then
  begin
    FField.GetSecret(secret);
    try
      FOnValidate(Self, secret, refusal);
    finally
      RtWipeSecret(secret);
    end;
  end;
  Result := refusal = '';
  if not Result then Refuse(refusal);
end;

function TRtPasswordDialog.CloseQuery: Boolean;
begin
  if (ModalResult = mrOk) and not Accepts then Exit(False);
  Result := inherited CloseQuery;
end;

function TRtPasswordDialog.Run: Boolean;
begin
  if FField = nil then AddField(rsRtPasswordField);
  if ButtonBar.ControlCount = 0 then
  begin
    AddButton(rsRtPasswordOk, mrOk, True);
    AddButton(rsRtPasswordCancel, mrCancel, False, True);
  end;
  ApplyTheme;
  ActiveControl := FField;
  Result := ShowModal = mrOk;
end;

function TRtPasswordDialog.Execute(out ASecret: RawByteString): Boolean;
begin
  ASecret := '';
  Result := Run;
  if Result then FField.GetSecret(ASecret);
  Wipe;
end;

function TRtPasswordDialog.Execute(out ASecret: string): Boolean;
begin
  ASecret := '';
  Result := Run;
  if Result then FField.GetSecret(ASecret);
  Wipe;
end;

procedure TRtPasswordDialog.Wipe;
begin
  if FField <> nil then FField.Wipe;
  if FConfirm <> nil then FConfirm.Wipe;
end;

end.
