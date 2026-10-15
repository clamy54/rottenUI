// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uGtk3Style;

{$mode objfpc}{$H+}

// GTK3: ce que le theme systeme dessine sous les controles de l'application.
// Menus: cadre et separateurs natifs. Champs: transition de fond, qui faisait
// passer un champ recolore par le fond clair du systeme. Sans effet ailleurs.

interface

uses
  Controls;

procedure ApplyGtk3Style;
// GTK3 ne livre la molette qu'au premier widget sous la souris, et un TCustomControl
// l'avale sans rien en faire: la zone la capte avant tout le monde. Un enfant qui
// defile vraiment (memo, liste) la garde.
procedure Gtk3CaptureWheel(AControl: TWinControl);

implementation

{$IFDEF LCLGtk3}
uses
  SysUtils, Math, Graphics, LMessages, LazGLib2, LazGtk3, LazGdk3, LazGObject2, gtk3widgets, uTheme;

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

function ScrollableBetween(ATarget, ATop: PGtkWidget): PGtkScrolledWindow;
var
  w: PGtkWidget;
  hp, vp: TGtkPolicyType;
  adj: PGtkAdjustment;
begin
  Result := nil;
  w := ATarget;
  while (w <> nil) and (w <> ATop) do
  begin
    if g_type_check_instance_is_a(PGTypeInstance(w), gtk_scrolled_window_get_type) then
    begin
      gtk_scrolled_window_get_policy(PGtkScrolledWindow(w), @hp, @vp);
      adj := gtk_scrolled_window_get_vadjustment(PGtkScrolledWindow(w));
      if (vp <> GTK_POLICY_EXTERNAL) and (adj <> nil) and
         (gtk_adjustment_get_upper(adj) - gtk_adjustment_get_page_size(adj) > 0.5) then
        Exit(PGtkScrolledWindow(w));
    end;
    w := gtk_widget_get_parent(w);
  end;
end;

procedure WheelCaptured({%H-}AController: PGtkEventController; {%H-}dx, dy: gdouble;
  AData: gpointer); cdecl;
var
  ctl: TWinControl;
  ev: PGdkEvent;
  target: PGtkWidget;
  sw: PGtkScrolledWindow;
  adj: PGtkAdjustment;
  msg: TLMMouseEvent;
begin
  if dy = 0 then Exit;
  ctl := TWinControl(AData);
  if not ctl.HandleAllocated then Exit;
  target := nil;
  ev := gtk_get_current_event;
  if ev <> nil then
  begin
    target := gtk_get_event_widget(ev);
    gdk_event_free(ev);
  end;
  if target <> nil then
  begin
    sw := ScrollableBetween(target, TGtk3Widget(ctl.Handle).Widget);
    if sw <> nil then
    begin
      // Le pas de GTK lui-meme.
      adj := gtk_scrolled_window_get_vadjustment(sw);
      gtk_adjustment_set_value(adj, gtk_adjustment_get_value(adj) +
        dy * Power(gtk_adjustment_get_page_size(adj), 2 / 3));
      Exit;
    end;
  end;
  FillChar(msg, SizeOf(msg), 0);
  msg.Msg := LM_MOUSEWHEEL;
  if dy > 0 then msg.WheelDelta := -120 else msg.WheelDelta := 120;
  ctl.Dispatch(msg);
end;

procedure Gtk3CaptureWheel(AControl: TWinControl);
var
  c: PGtkEventControllerScroll;
begin
  if not AControl.HandleAllocated then Exit;
  c := gtk_event_controller_scroll_new(TGtk3Widget(AControl.Handle).Widget,
    [GTK_EVENT_CONTROLLER_SCROLL_VERTICAL]);
  gtk_event_controller_set_propagation_phase(PGtkEventController(c), GTK_PHASE_CAPTURE);
  g_signal_connect_data(PGObject(c), 'scroll', TGCallback(@WheelCaptured), AControl, nil,
    G_CONNECT_DEFAULT);
end;
{$ELSE}
procedure ApplyGtk3Style;
begin
end;

procedure Gtk3CaptureWheel(AControl: TWinControl);
begin
end;
{$ENDIF}

end.
