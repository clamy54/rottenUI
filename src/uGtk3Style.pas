// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uGtk3Style;

{$mode objfpc}{$H+}

// GTK3: ce que le theme systeme dessine sous les controles de l'application.
// Menus: cadre et separateurs natifs. Champs: transition de fond, qui faisait
// passer un champ recolore par le fond clair du systeme. Sans effet ailleurs.

interface

procedure ApplyGtk3Style;

implementation

{$IFDEF LCLGtk3}
uses
  SysUtils, Graphics, LazGtk3, LazGdk3, LazGObject2, uTheme;

var
  GCss: PGtkCssProvider = nil;
  GCssText: string = '';

function CssHex(AColor: TColor): string;
var
  c: LongInt;
begin
  c := ColorToRGB(AColor);
  Result := Format('#%.2x%.2x%.2x', [c and $FF, (c shr 8) and $FF, (c shr 16) and $FF]);
end;

procedure ApplyGtk3Style;
var
  screen: PGdkScreen;
  css: string;
begin
  css := Format('menu { background-color: %s; padding: 0; border-radius: 0; } ' +
    'menu separator { background-color: %s; background-image: none; ' +
    'min-height: 1px; margin: 4px 8px; } ' +
    'entry { transition: none; }', [CssHex(clMenuPopupBg), CssHex(clMenuSep)]);
  if css = GCssText then Exit;
  screen := gdk_screen_get_default;
  if screen = nil then Exit;
  if GCss <> nil then
  begin
    gtk_style_context_remove_provider_for_screen(screen, PGtkStyleProvider(GCss));
    g_object_unref(GCss);
  end;
  GCss := gtk_css_provider_new;
  gtk_css_provider_load_from_data(GCss, PChar(css), -1, nil);
  gtk_style_context_add_provider_for_screen(screen, PGtkStyleProvider(GCss),
    GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  GCssText := css;
end;
{$ELSE}
procedure ApplyGtk3Style;
begin
end;
{$ENDIF}

end.
