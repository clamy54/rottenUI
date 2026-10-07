// Copyright (C) 2023-2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtSecretEdit;

{$mode objfpc}{$H+}

// Champ de saisie masque, pour les deux familles de controles. Ni PasswordChar ni EchoMode: sous Cocoa
// ils en font un NSSecureTextField et son "secure event input", dont l'etat se desequilibre de dialogue
// en dialogue jusqu'a figer l'application, roue coloree comprise. On masque donc a la main: le widget ne
// montre que des '*', le clair vit dans un tampon a nous. Il passe quand meme UNE fois par le widget.

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Menus, LCLType;

type
  TRtSecretEdit = class(TEdit)
  private
    FValue: string;
    FGuard: Boolean;
    FRevealed: Boolean;
    FSelStart, FSelLen: Integer; // selection d'avant l'edition, en caracteres affiches
    FMaskedMenu: TPopupMenu;
    procedure Capture;
    function Explains(const AShown: string; AHead, ATail: Integer): Boolean;
    procedure Splice(AStart, ACount: Integer; var AInserted: string);
    procedure Display(ACaret: Integer);
    procedure SetRevealed(AValue: Boolean);
    procedure MenuPaste(Sender: TObject);
  protected
    procedure Change; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    // Text ecrit de l'exterieur pose le secret; Text relu ne rend que ce qui est affiche
    procedure RealSetText(const AValue: TCaption); override;
    procedure SetSelText(const Val: string); override;
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
  public
    destructor Destroy; override;
    procedure SelectAll; override;
    procedure PasteFromClipboard; override;
    procedure CopyToClipboard; override;
    procedure CutToClipboard; override;
    procedure Undo; override;
    // copie a effacer par l'appelant; par parametre, un resultat de fonction laisse un temporaire
    procedure GetSecret(out AValue: RawByteString); overload;
    procedure GetSecret(out AValue: string); overload;
    procedure SetSecret(const AValue: string);
    function IsEmpty: Boolean;
    function SameAs(AOther: TRtSecretEdit): Boolean;
    procedure Wipe;
    property Revealed: Boolean read FRevealed write SetRevealed;
  end;

procedure RtWipeSecret(var AValue: RawByteString); overload;
procedure RtWipeSecret(var AValue: string); overload;

resourcestring
  rsRtSecretPaste = 'Paste';

implementation

uses
  Math, LazUTF8, uMenuBar;

procedure RtWipeSecret(var AValue: RawByteString);
begin
  if AValue = '' then Exit;
  UniqueString(AValue);
  FillChar(AValue[1], Length(AValue), 0);
  AValue := '';
end;

procedure RtWipeSecret(var AValue: string);
begin
  if AValue = '' then Exit;
  UniqueString(AValue);
  FillChar(AValue[1], Length(AValue), 0);
  AValue := '';
end;

destructor TRtSecretEdit.Destroy;
begin
  RtWipeSecret(FValue);
  inherited Destroy;
end;

procedure TRtSecretEdit.Capture;
begin
  FSelStart := SelStart;
  FSelLen := SelLength;
end;

procedure TRtSecretEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  Capture;
  // copier/couper au clavier ne passent pas par la LCL: le widget poserait ses etoiles au presse-papiers
  if not FRevealed then
    if ((Key = VK_C) or (Key = VK_INSERT)) and (Shift = [ssModifier]) then
      Key := 0
    else if ((Key = VK_X) and (Shift = [ssModifier])) or ((Key = VK_DELETE) and (Shift = [ssShift])) then
    begin
      Key := 0;
      CutToClipboard;
    end;
  inherited KeyDown(Key, Shift);
end;

procedure TRtSecretEdit.KeyUp(var Key: Word; Shift: TShiftState);
begin
  inherited KeyUp(Key, Shift);
  // le caret a pu bouger sans edition, et la suivante peut arriver sans touche
  Capture;
end;

procedure TRtSecretEdit.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  // Selection lachee avant que le widget ne voie le clic: il ne peut plus la faire glisser. Des
  // etoiles deplacees parmi des etoiles, c'est un secret corrompu sans que rien ne se voie.
  if (Button = mbLeft) and not (ssShift in Shift) and not FRevealed and (SelLength > 0) then
    SelLength := 0;
  inherited MouseDown(Button, Shift, X, Y);
end;

procedure TRtSecretEdit.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  Capture;
end;

procedure TRtSecretEdit.SelectAll;
begin
  inherited SelectAll;
  Capture;
end;

procedure TRtSecretEdit.PasteFromClipboard;
begin
  Capture;
  inherited PasteFromClipboard;
end;

procedure TRtSecretEdit.CopyToClipboard;
begin
  if FRevealed then inherited CopyToClipboard;
end;

procedure TRtSecretEdit.CutToClipboard;
var
  none: string;
begin
  if FRevealed then
  begin
    inherited CutToClipboard;
    Exit;
  end;
  Capture;
  if FSelLen = 0 then Exit;
  none := '';
  Splice(FSelStart, FSelLen, none);
  Display(FSelStart);
  inherited Change;
end;

procedure TRtSecretEdit.Undo;
begin
  // l'historique du widget ne connait que des etoiles: rien a rejouer
end;

function TRtSecretEdit.Explains(const AShown: string; AHead, ATail: Integer): Boolean;
var
  i: Integer;
begin
  if (AHead < 0) or (ATail < 0) or (AHead + ATail > Length(AShown)) then Exit(False);
  for i := 1 to AHead do
    if AShown[i] <> '*' then Exit(False);
  for i := Length(AShown) - ATail + 1 to Length(AShown) do
    if AShown[i] <> '*' then Exit(False);
  Result := True;
end;

// morceaux en variables nommees: un temporaire du compilateur ne s'efface pas
procedure TRtSecretEdit.Splice(AStart, ACount: Integer; var AInserted: string);
var
  head, tail, next: string;
begin
  head := UTF8Copy(FValue, 1, AStart);
  tail := UTF8Copy(FValue, AStart + ACount + 1, MaxInt);
  next := head + AInserted + tail;
  RtWipeSecret(head);
  RtWipeSecret(tail);
  RtWipeSecret(AInserted);
  RtWipeSecret(FValue);
  FValue := next;
end;

procedure TRtSecretEdit.Display(ACaret: Integer);
var
  shown: string;
begin
  if FRevealed then
    SetString(shown, PChar(FValue), Length(FValue))
  else
    shown := StringOfChar('*', UTF8Length(FValue));
  ACaret := EnsureRange(ACaret, 0, UTF8Length(FValue));
  FGuard := True;
  try
    Text := shown;
    SelStart := ACaret;
    SelLength := 0;
  finally
    FGuard := False;
  end;
  FSelStart := ACaret;
  FSelLen := 0;
end;

procedure TRtSecretEdit.Change;
var
  shown, inserted: string;
  oldLen, insLen, caret: Integer;
  known: Boolean;
begin
  if FGuard then Exit;
  shown := Text;
  if FRevealed then
  begin
    RtWipeSecret(FValue);
    FValue := shown;
    shown := '';
    inherited Change;
    Exit;
  end;
  oldLen := UTF8Length(FValue);
  insLen := UTF8Length(shown) - oldLen + FSelLen;
  inserted := '';
  if (insLen >= 0) and (FSelStart >= 0) and (FSelStart + FSelLen <= oldLen) then
  begin
    known := Explains(shown, FSelStart, oldLen - FSelStart - FSelLen);
    if known then
    begin
      inserted := UTF8Copy(shown, FSelStart + 1, insLen);
      Splice(FSelStart, FSelLen, inserted);
    end;
    caret := FSelStart + insLen;
  end
  else
  begin
    // suppression sans selection: arriere ou avant, le caret d'apres en marque le debut
    caret := EnsureRange(SelStart, 0, oldLen);
    known := (insLen < 0) and (caret - insLen <= oldLen) and Explains(shown, Length(shown), 0);
    if known then Splice(caret, -insLen, inserted);
  end;
  RtWipeSecret(shown);
  // Edition venue d'ailleurs que du caret connu (depot, service du systeme): la reconstruire
  // serait inventer un secret. Elle est refusee, le champ revient a ce qu'il contenait.
  if not known then
  begin
    Display(FSelStart);
    Exit;
  end;
  Display(caret);
  inherited Change;
end;

procedure TRtSecretEdit.RealSetText(const AValue: TCaption);
begin
  if FGuard then
    inherited RealSetText(AValue)
  else
    SetSecret(AValue);
end;

// sans ca, la LCL recompose Text autour de la selection: des etoiles prises pour un secret
procedure TRtSecretEdit.SetSelText(const Val: string);
var
  piece: string;
  count: Integer;
begin
  Capture;
  if FSelStart + FSelLen > UTF8Length(FValue) then Exit;
  count := UTF8Length(Val);
  SetString(piece, PChar(Val), Length(Val));
  Splice(FSelStart, FSelLen, piece);
  Display(FSelStart + count);
  inherited Change;
end;

// Masque, le menu natif d'un champ offre "Copier": des etoiles au presse-papiers. Le notre ne sait
// que coller. Revele, ou si l'application a pose son propre menu, on ne s'en mele pas.
procedure TRtSecretEdit.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var
  item: TMenuItem;
  at: TPoint;
begin
  inherited DoContextPopup(MousePos, Handled);
  if Handled or FRevealed or (PopupMenu <> nil) then Exit;
  if FMaskedMenu = nil then
  begin
    FMaskedMenu := TPopupMenu.Create(Self);
    item := TMenuItem.Create(FMaskedMenu);
    item.Caption := rsRtSecretPaste;
    item.OnClick := @MenuPaste;
    FMaskedMenu.Items.Add(item);
    ThemePopupMenu(FMaskedMenu);
  end;
  FMaskedMenu.Items[0].Enabled := not ReadOnly;
  // appele au clavier, il n'y a pas de position: sous le champ
  if MousePos.X < 0 then
    at := ClientToScreen(Point(0, Height))
  else
    at := ClientToScreen(MousePos);
  Handled := True;
  FMaskedMenu.PopupComponent := Self;
  FMaskedMenu.Popup(at.X, at.Y);
end;

procedure TRtSecretEdit.MenuPaste(Sender: TObject);
begin
  PasteFromClipboard;
end;

procedure TRtSecretEdit.SetRevealed(AValue: Boolean);
var
  caret: Integer;
begin
  if AValue = FRevealed then Exit;
  caret := SelStart;
  FRevealed := AValue;
  Display(caret);
end;

procedure TRtSecretEdit.GetSecret(out AValue: RawByteString);
begin
  SetString(AValue, PChar(FValue), Length(FValue));
end;

procedure TRtSecretEdit.GetSecret(out AValue: string);
begin
  SetString(AValue, PChar(FValue), Length(FValue));
end;

procedure TRtSecretEdit.SetSecret(const AValue: string);
var
  next: string;
begin
  SetString(next, PChar(AValue), Length(AValue));
  RtWipeSecret(FValue);
  FValue := next;
  Display(MaxInt);
  if not (csDestroying in ComponentState) then inherited Change;
end;

function TRtSecretEdit.IsEmpty: Boolean;
begin
  Result := FValue = '';
end;

function TRtSecretEdit.SameAs(AOther: TRtSecretEdit): Boolean;
begin
  Result := (AOther <> nil) and (FValue = AOther.FValue);
end;

procedure TRtSecretEdit.Wipe;
var
  had: Boolean;
begin
  had := FValue <> '';
  RtWipeSecret(FValue);
  if csDestroying in ComponentState then Exit;
  Display(0);
  if had then inherited Change;
end;

end.
