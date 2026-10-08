// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtReport;

{$mode objfpc}{$H+}

// Vue de rapport de la famille Rt: barre de commandes, bilan et avertissement, liste triable.
// A poser dans une page d'onglet, dont le fond natif ignore le theme: un libelle pose dessus
// y reste gris clair sur blanc, lisible surtout par ceux qui n'en ont pas besoin. Ici tout
// vit dans des panneaux. L'application fournit les commandes, les textes et les cellules.

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, Graphics, uRtList, uRtCombo;

type
  TRtReportView = class(TCustomPanel)
  private
    FBar, FInfo: TPanel;
    FBarHint, FSummary, FWarning: TLabel;
    FList: TRtListGrid;
    function GetBarHint: string;
    procedure SetBarHint(const AValue: string);
  public
    constructor Create(AOwner: TComponent); override;
    function AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
    // Liste de choix a droite de la barre, son libelle devant. La premiere posee est la plus
    // a droite.
    function AddChoice(const ACaption: string; const AItems: array of string;
      AOnChange: TNotifyEvent; AWidth: Integer = 220): TRtComboBox;
    // Un texte vide retire sa ligne; les deux vides, le bloc disparait.
    procedure SetTexts(const ASummary, AWarning: string);
    procedure ApplyTheme;
    // Pour les controles de l'ecran, a aligner a droite.
    property Bar: TPanel read FBar;
    property List: TRtListGrid read FList;
    property BarHint: string read GetBarHint write SetBarHint;
  end;

implementation

uses
  uTheme, uUiKit;

constructor TRtReportView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FBar := MakePanel(Self, alTop, 36);
  FBarHint := MakeLabel(FBar, '', alClient);
  FBarHint.Layout := tlCenter;
  FBarHint.WordWrap := False;
  FInfo := MakePanel(Self, alTop);
  FInfo.AutoSize := True;
  FInfo.Visible := False;
  FSummary := MakeDataLabel(FInfo, '');
  FSummary.Visible := False;
  FWarning := MakeDataLabel(FInfo, '');
  FWarning.Visible := False;
  FList := TRtListGrid.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.Sortable := True;
  FList.FillWidth := True;
end;

function TRtReportView.AddButton(const ACaption: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := MakeButton(FBar, ACaption, AOnClick);
end;

function TRtReportView.AddChoice(const ACaption: string; const AItems: array of string;
  AOnChange: TNotifyEvent; AWidth: Integer): TRtComboBox;
begin
  Result := MakeCombo(FBar, AItems, alRight);
  Result.Width := AWidth;
  Result.OnChange := AOnChange;
  MakeLabel(FBar, ACaption, alRight).Layout := tlCenter;
end;

function TRtReportView.GetBarHint: string;
begin
  Result := FBarHint.Caption;
end;

procedure TRtReportView.SetBarHint(const AValue: string);
begin
  FBarHint.Caption := AValue;
end;

procedure TRtReportView.SetTexts(const ASummary, AWarning: string);
begin
  FSummary.Caption := ASummary;
  FWarning.Caption := AWarning;
  if (FSummary.Visible = (ASummary <> '')) and (FWarning.Visible = (AWarning <> '')) then Exit;
  FSummary.Visible := ASummary <> '';
  FWarning.Visible := AWarning <> '';
  FInfo.Visible := FSummary.Visible or FWarning.Visible;
  StackByCreation(Self);
end;

procedure TRtReportView.ApplyTheme;
begin
  ThemeControlTree(Self);
  ArrangeByCreation(Self);
  Color := clAppBg;
  FList.Color := clAppBg;
  FList.Font.Color := clAppFg;
  FList.RefreshMetrics;
  // Le theme repeint tous les libelles couleur texte: l'avertissement reprend la sienne.
  FWarning.Font.Color := clDiffWarning;
end;

end.
