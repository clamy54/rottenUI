// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtAbout;

{$mode objfpc}{$H+}

// A propos et visionneuse de licences. Le kit ne sait rien de l'application: nom, version,
// lignes, liens, logo et textes arrivent tous de l'appelant. Les licences se lisent dans les
// ressources du binaire: pas besoin de reseau pour savoir ce qu'on doit a qui.

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Forms, Graphics, uUiKit;

type
  TRtAboutDialog = class(TRtDialog)
  private
    FTitle: TLabel;
    FLogo: TImage;
    FDetails: TMemo;
    FLinks: TFPList;
    FCentered: Boolean;
    procedure LinkClick(Sender: TObject);
    procedure SetCentered(AValue: Boolean);
  protected
    procedure ApplyShellColors; override;
  public
    constructor CreateAbout(AOwner: TComponent; const AAppName, AVersion: string;
      AWidth: Integer = 700; AHeight: Integer = 520);
    destructor Destroy; override;
    // au-dessus du titre; l'appelant garde la propriete de l'image
    procedure SetLogo(AGraphic: TGraphic; ASize: Integer = 96);
    function AddLine(const AText: string): TLabel;
    function AddLink(const AUrl: string; const ACaption: string = ''): TLabel;
    // memo en lecture seule qui prend la place restante, rendu pour y ajouter des lignes
    function AddDetails(const ACaption: string): TStrings;
    // sans memo de details, la hauteur se cale sur le contenu
    function Execute: TModalResult;
    property Centered: Boolean read FCentered write SetCentered;
  end;

  TRtLicenseViewer = class(TRtDialog)
  private
    FList: TListBox;
    FViewer: TMemo;
    FTexts: TStringList;
    procedure ListClick(Sender: TObject);
  public
    constructor CreateViewer(AOwner: TComponent; const ACaption: string;
      AWidth: Integer = 980; AHeight: Integer = 680);
    destructor Destroy; override;
    procedure AddText(const ACaption, AText: string);
    // ressource RCDATA du binaire, lue quand on la demande; absente, elle s'affiche vide
    procedure AddResource(const ACaption, AResName: string);
    procedure Select(AIndex: Integer);
    function Execute: TModalResult;
    function Count: Integer;
    function ItemIndex: Integer;
    function ShownText: string;
  end;

procedure RtShowLicenses(AOwner: TComponent; const ACaption: string;
  const ACaptions, AResNames: array of string);

resourcestring
  rsRtAboutTitle = 'About %s';
  rsRtAboutClose = 'Close';
  rsRtLicensesTitle = 'Licenses';

implementation

uses
  LCLType, LCLIntf, uTheme;

const
  TITLE_EXTRA = 4;
  LIST_WIDTH = 300;

function ResourceText(const AName: string): string;
var
  rs: TResourceStream;
begin
  Result := '';
  try
    rs := TResourceStream.Create(HInstance, AName, RT_RCDATA);
    try
      SetLength(Result, rs.Size);
      if rs.Size > 0 then rs.ReadBuffer(Result[1], rs.Size);
    finally
      rs.Free;
    end;
  except
    Result := '';
  end;
end;

constructor TRtAboutDialog.CreateAbout(AOwner: TComponent; const AAppName, AVersion: string;
  AWidth, AHeight: Integer);
begin
  inherited CreateDialog(AOwner, Format(rsRtAboutTitle, [AAppName]), AWidth, AHeight);
  FLinks := TFPList.Create;
  SetIcon('info-circle');
  FTitle := MakeDataLabel(Body, Trim(AAppName + ' ' + AVersion));
  // hors du passage du theme, qui ramenerait le titre a la taille commune
  FTitle.Tag := TAG_KEEP_FONT;
  AddButton(rsRtAboutClose, mrOk, True, True);
end;

destructor TRtAboutDialog.Destroy;
begin
  FLinks.Free;
  inherited Destroy;
end;

procedure TRtAboutDialog.SetLogo(AGraphic: TGraphic; ASize: Integer);
begin
  if AGraphic = nil then Exit;
  if FLogo = nil then
  begin
    FLogo := TImage.Create(Body);
    FLogo.Parent := Body;
    FLogo.Align := alTop;
    FLogo.Stretch := True;
    FLogo.Proportional := True;
    FLogo.BorderSpacing.Around := 4;
    Body.SetControlIndex(FLogo, 0);
  end;
  FLogo.Height := ASize;
  FLogo.Center := FCentered;
  FLogo.Picture.Assign(AGraphic);
end;

function TRtAboutDialog.AddLine(const AText: string): TLabel;
begin
  Result := MakeDataLabel(Body, AText);
  if FCentered then Result.Alignment := taCenter;
end;

function TRtAboutDialog.AddLink(const AUrl: string; const ACaption: string): TLabel;
begin
  if ACaption <> '' then Result := AddLine(ACaption) else Result := AddLine(AUrl);
  Result.Hint := AUrl;
  Result.Font.Style := Result.Font.Style + [fsUnderline];
  Result.Font.Color := clAccent;
  Result.Cursor := crHandPoint;
  Result.OnClick := @LinkClick;
  FLinks.Add(Result);
end;

function TRtAboutDialog.AddDetails(const ACaption: string): TStrings;
begin
  if FDetails = nil then
  begin
    if ACaption <> '' then AddLine(ACaption);
    FDetails := MakeMemo(Body);
    FDetails.ReadOnly := True;
  end;
  Result := FDetails.Lines;
end;

procedure TRtAboutDialog.SetCentered(AValue: Boolean);
var
  i: Integer;
begin
  FCentered := AValue;
  for i := 0 to Body.ControlCount - 1 do
    if Body.Controls[i] is TLabel then
      if AValue then TLabel(Body.Controls[i]).Alignment := taCenter
      else TLabel(Body.Controls[i]).Alignment := taLeftJustify;
  if FLogo <> nil then FLogo.Center := AValue;
end;

procedure TRtAboutDialog.LinkClick(Sender: TObject);
begin
  OpenURL(TLabel(Sender).Hint);
end;

procedure TRtAboutDialog.ApplyShellColors;
var
  i: Integer;
begin
  inherited ApplyShellColors;
  if FTitle <> nil then
  begin
    if RSUiFontName <> '' then FTitle.Font.Name := RSUiFontName;
    FTitle.Font.Size := RSUiFontSize + TITLE_EXTRA;
  end;
  // le theme remet tout libelle a la couleur du texte: les liens reprennent la leur
  if FLinks <> nil then
    for i := 0 to FLinks.Count - 1 do
      TLabel(FLinks[i]).Font.Color := clAccent;
end;

function TRtAboutDialog.Execute: TModalResult;
begin
  FitOnShow := FDetails = nil;
  ApplyTheme;
  Result := ShowModal;
end;

constructor TRtLicenseViewer.CreateViewer(AOwner: TComponent; const ACaption: string;
  AWidth, AHeight: Integer);
var
  side: TPanel;
begin
  if ACaption <> '' then
    inherited CreateDialog(AOwner, ACaption, AWidth, AHeight)
  else
    inherited CreateDialog(AOwner, rsRtLicensesTitle, AWidth, AHeight);
  FTexts := TStringList.Create;
  SetIcon('file-text');
  side := MakePanel(Body, alLeft, LIST_WIDTH);
  FList := TListBox.Create(side);
  FList.Parent := side;
  FList.Align := alClient;
  FList.OnClick := @ListClick;
  FViewer := MakeMemo(Body);
  FViewer.ReadOnly := True;
  AddButton(rsRtAboutClose, mrOk, True, True);
end;

destructor TRtLicenseViewer.Destroy;
begin
  FTexts.Free;
  inherited Destroy;
end;

procedure TRtLicenseViewer.AddText(const ACaption, AText: string);
begin
  FList.Items.Add(ACaption);
  FTexts.Add(AText);
end;

procedure TRtLicenseViewer.AddResource(const ACaption, AResName: string);
begin
  // Objects non nil: FTexts porte un nom de ressource, pas le texte
  FList.Items.Add(ACaption);
  FTexts.AddObject(AResName, Self);
end;

procedure TRtLicenseViewer.Select(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FTexts.Count) then Exit;
  FList.ItemIndex := AIndex;
  ListClick(nil);
end;

procedure TRtLicenseViewer.ListClick(Sender: TObject);
var
  i: Integer;
begin
  i := FList.ItemIndex;
  if (i < 0) or (i >= FTexts.Count) then Exit;
  if FTexts.Objects[i] <> nil then
    FViewer.Text := ResourceText(FTexts[i])
  else
    FViewer.Text := FTexts[i];
end;

function TRtLicenseViewer.Count: Integer;
begin
  Result := FTexts.Count;
end;

function TRtLicenseViewer.ItemIndex: Integer;
begin
  Result := FList.ItemIndex;
end;

function TRtLicenseViewer.ShownText: string;
begin
  Result := FViewer.Text;
end;

function TRtLicenseViewer.Execute: TModalResult;
begin
  if FList.ItemIndex < 0 then Select(0);
  ApplyTheme;
  Result := ShowModal;
end;

procedure RtShowLicenses(AOwner: TComponent; const ACaption: string;
  const ACaptions, AResNames: array of string);
var
  d: TRtLicenseViewer;
  i: Integer;
begin
  d := TRtLicenseViewer.CreateViewer(AOwner, ACaption);
  try
    for i := 0 to High(AResNames) do
      if i <= High(ACaptions) then d.AddResource(ACaptions[i], AResNames[i])
      else d.AddResource(AResNames[i], AResNames[i]);
    d.Execute;
  finally
    d.Free;
  end;
end;

end.
