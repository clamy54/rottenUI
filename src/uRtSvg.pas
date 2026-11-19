unit uRtSvg;
{ rottenUI — a small SVG reader and rasterizer of its own, without the LCL.

  Read: paths (every command, arcs included), rect / circle / ellipse /
  line / polyline / polygon, groups, nested svg, transforms, internal
  <use> (and symbols), presentation attributes and style="", fills
  (nonzero, evenodd), strokes (width, caps, joins, miter limit, dashes),
  opacities, gradients reduced to the average of their stops, texts
  (text / tspan) handed to the caller, who writes them in its own fonts.

  Colours are kept as grey levels (0 black .. 1 white) and coverage: the
  caller tints them, typically from the theme's foreground (black) to its
  background (white), so that a plan follows the theme.

  The input is hostile: a reader of its own, no DTD with declarations
  (no entity can be defined, so none can expand), no external reference
  (images, links to other files) ever followed, bounded size, nodes,
  nesting, shapes, points and <use> depth. Errors raise ERtSvg.

  Rasterization: the signed-area accumulation of font-rs (exact
  antialiasing, one pass per shape), strokes built as polygons whose union
  is taken by clamping the coverage.
  SPDX-License-Identifier: GPL-3.0-or-later }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math;

const
  RTSVG_MAX_BYTES = 32 * 1024 * 1024;
  RTSVG_MAX_NODES = 400000;
  RTSVG_MAX_DEPTH = 128;
  RTSVG_MAX_SHAPES = 400000;
  RTSVG_MAX_POINTS = 8000000;     // coordinates kept (x and y count once)
  RTSVG_MAX_USE_DEPTH = 8;
  RTSVG_MAX_VISITS = 2000000;     // elements walked, <use> expansions counted
  RTSVG_MAX_FLAT = 2000000;       // points of one shape once flattened
  RTSVG_MAX_SIDE = 1000000;       // the image's own size, in pixels

type
  ERtSvg = class(Exception);

  { x' = A x + C y + E ; y' = B x + D y + F (the SVG matrix(a b c d e f)). }
  TRtSvgMatrix = record
    A, B, C, D, E, F: Double;
  end;

  TRtSvgCap = (rcButt, rcRound, rcSquare);
  TRtSvgJoin = (rjMiter, rjRound, rjBevel);

  TRtSvgShape = record
    First, Count: Integer;          // commands, in the image's list
    PtFirst: Integer;               // their points
    M: TRtSvgMatrix;                // user space -> image pixels
    FillLum, FillAlpha: Single;     // FillAlpha 0: no fill
    StrokeLum, StrokeAlpha: Single; // StrokeAlpha 0: no stroke
    StrokeWidth, MiterLimit, DashOffset: Double;
    Cap: TRtSvgCap;
    Join: TRtSvgJoin;
    EvenOdd: Boolean;
    Dash: array of Double;
  end;

  TRtSvgText = record
    X, Y: Double;                   // the anchor point, user space
    M: TRtSvgMatrix;                // user space -> image pixels
    Size: Double;                   // font size, user space
    Bold, Italic, Mono: Boolean;    // Mono: the SVG asked for a monospace font
    Anchor: Integer;                // 0 start, 1 middle, 2 end
    Baseline: Integer;              // 0 alphabetic, 1 central / middle, 2 hanging / top
    Lum, Alpha: Single;
    Text: string;                   // UTF-8, white space collapsed
    Order: Integer;                 // the shapes drawn before it
  end;

  { Grey levels and coverage of a rendered area, row by row from the top.
    Lum is premultiplied by Alpha. }
  TRtSvgRaster = record
    Width, Height: Integer;
    Lum, Alpha: array of Single;
  end;

  TRtSvgImage = class
  private
    FWidth, FHeight: Double;
    FCmds: array of Byte;
    FCmdCount: Integer;
    FPts: array of Double;
    FPtCount: Integer;
    FShapes: array of TRtSvgShape;
    FShapeCount: Integer;
    FTexts: array of TRtSvgText;
    FTextCount: Integer;
    FTextHidden: array of Boolean;
    function GetText(AIndex: Integer): TRtSvgText;
    function GetTextHidden(AIndex: Integer): Boolean;
    procedure SetTextHidden(AIndex: Integer; AValue: Boolean);
  public
    { Reads an SVG document (UTF-8, or UTF-16 with its byte order mark).
      Raises ERtSvg when it is not one, or breaks a limit. }
    procedure LoadFromString(const AData: RawByteString);
    procedure Clear;
    { Renders into ARaster, whose Width and Height the caller sets: AM maps
      the image's pixels (0..Width, 0..Height) onto the raster's. The
      shapes from AFirst to ALast only, when given (texts lie between). }
    procedure Render(const AM: TRtSvgMatrix; var ARaster: TRtSvgRaster;
      AFirst: Integer = 0; ALast: Integer = MaxInt);
    { The image's own size, in pixels (its width / height, else its viewBox). }
    property Width: Double read FWidth;
    property Height: Double read FHeight;
    property ShapeCount: Integer read FShapeCount;
    property TextCount: Integer read FTextCount;
    property Texts[AIndex: Integer]: TRtSvgText read GetText;
    { A text left out when painted (an application writes another in its
      place); none is after loading. }
    property TextHidden[AIndex: Integer]: Boolean read GetTextHidden write SetTextHidden;
    procedure ShowAllTexts;
  end;

{ True when the data looks like an SVG document (an <svg> element near the
  start, after an optional XML declaration, comments or doctype). }
function RtSvgSniff(const AData: RawByteString): Boolean;

type
  TRtSvgIndexes = array of Integer;

const
  RTSVG_CROP_MAX_BYTES = 24 * 1024 * 1024;

{ The image AM maps (its pixels to a new image's) cropped to 0..AW x 0..AH,
  written as an SVG of that size: its shapes flattened (curves as short
  segments) and clipped to it (fills as polygons, strokes segment by
  segment, a dashed one keeping its phase), with their greys, opacities,
  widths, caps, joins and dashes; its texts kept whole when their anchor
  lies inside, each in its place among the shapes. AKept[i]: the new
  index of text i, -1 when it is left out. Raises ERtSvg beyond
  RTSVG_CROP_MAX_BYTES. }
function RtSvgCrop(AImage: TRtSvgImage; const AM: TRtSvgMatrix; AW, AH: Double;
  out AKept: TRtSvgIndexes): RawByteString;

function RtSvgIdentity: TRtSvgMatrix;
function RtSvgMatrix(A, B, C, D, E, F: Double): TRtSvgMatrix;
{ AOuter after AInner: a point goes through AInner first. }
function RtSvgMul(const AOuter, AInner: TRtSvgMatrix): TRtSvgMatrix;
function RtSvgScale(SX, SY: Double): TRtSvgMatrix;
function RtSvgTranslate(TX, TY: Double): TRtSvgMatrix;
procedure RtSvgApply(const AM: TRtSvgMatrix; X, Y: Double; out AX, AY: Double);

implementation

uses
  StrUtils;

const
  CMD_MOVE = 0;
  CMD_LINE = 1;
  CMD_CUBIC = 2;
  CMD_CLOSE = 3;
  KAPPA = 0.5522847498307936;
  FLAT_TOLERANCE = 0.05;

resourcestring
  rsSvgNotSvg = 'This is not an SVG image.';
  rsSvgBroken = 'The SVG image is damaged (%s).';
  rsSvgTooBig = 'The SVG image is too large or too complex (%s).';
  rsSvgDtd = 'The SVG image declares entities in a DTD: refused.';

{ ---------------------------------------------------------------------------
  Matrices
  --------------------------------------------------------------------------- }

function RtSvgIdentity: TRtSvgMatrix;
begin
  Result := RtSvgMatrix(1, 0, 0, 1, 0, 0);
end;

function RtSvgMatrix(A, B, C, D, E, F: Double): TRtSvgMatrix;
begin
  Result.A := A; Result.B := B; Result.C := C;
  Result.D := D; Result.E := E; Result.F := F;
end;

function RtSvgMul(const AOuter, AInner: TRtSvgMatrix): TRtSvgMatrix;
begin
  Result.A := AOuter.A * AInner.A + AOuter.C * AInner.B;
  Result.B := AOuter.B * AInner.A + AOuter.D * AInner.B;
  Result.C := AOuter.A * AInner.C + AOuter.C * AInner.D;
  Result.D := AOuter.B * AInner.C + AOuter.D * AInner.D;
  Result.E := AOuter.A * AInner.E + AOuter.C * AInner.F + AOuter.E;
  Result.F := AOuter.B * AInner.E + AOuter.D * AInner.F + AOuter.F;
end;

function RtSvgScale(SX, SY: Double): TRtSvgMatrix;
begin
  Result := RtSvgMatrix(SX, 0, 0, SY, 0, 0);
end;

function RtSvgTranslate(TX, TY: Double): TRtSvgMatrix;
begin
  Result := RtSvgMatrix(1, 0, 0, 1, TX, TY);
end;

procedure RtSvgApply(const AM: TRtSvgMatrix; X, Y: Double; out AX, AY: Double);
begin
  AX := AM.A * X + AM.C * Y + AM.E;
  AY := AM.B * X + AM.D * Y + AM.F;
end;

{ ---------------------------------------------------------------------------
  XML: a reader of its own, into a flat tree
  --------------------------------------------------------------------------- }

type
  TXNode = record
    Name: string;                 // local name, lower case kept as written; '' = text
    Attrs: array of string;       // name, value, name, value...
    Text: string;
    Parent, FirstChild, LastChild, Next: Integer;
  end;

  TXDoc = record
    Nodes: array of TXNode;
    Count: Integer;
  end;

procedure Broken(const AWhat: string);
begin
  raise ERtSvg.CreateFmt(rsSvgBroken, [AWhat]);
end;

procedure TooBig(const AWhat: string);
begin
  raise ERtSvg.CreateFmt(rsSvgTooBig, [AWhat]);
end;

function CodePointUtf8(ACode: Cardinal): string;
begin
  if (ACode = 0) or (ACode > $10FFFF) or ((ACode >= $D800) and (ACode <= $DFFF)) then
    Exit('?');
  if ACode < $80 then
    Result := Chr(ACode)
  else if ACode < $800 then
    Result := Chr($C0 or (ACode shr 6)) + Chr($80 or (ACode and $3F))
  else if ACode < $10000 then
    Result := Chr($E0 or (ACode shr 12)) + Chr($80 or ((ACode shr 6) and $3F)) +
      Chr($80 or (ACode and $3F))
  else
    Result := Chr($F0 or (ACode shr 18)) + Chr($80 or ((ACode shr 12) and $3F)) +
      Chr($80 or ((ACode shr 6) and $3F)) + Chr($80 or (ACode and $3F));
end;

{ The five predefined entities and character references; anything else is
  kept as written (no entity can be declared). }
function DecodeEntities(const S: string): string;
var
  i, j, n: Integer;
  ent: string;
  code: Cardinal;
  ok: Boolean;
begin
  if Pos('&', S) = 0 then Exit(S);
  Result := '';
  i := 1;
  n := Length(S);
  while i <= n do
  begin
    if S[i] <> '&' then
    begin
      j := i;
      while (j <= n) and (S[j] <> '&') do Inc(j);
      Result := Result + Copy(S, i, j - i);
      i := j;
      Continue;
    end;
    j := i + 1;
    while (j <= n) and (j - i < 12) and (S[j] <> ';') do Inc(j);
    if (j > n) or (S[j] <> ';') then
    begin
      Result := Result + '&';
      Inc(i);
      Continue;
    end;
    ent := Copy(S, i + 1, j - i - 1);
    ok := True;
    if ent = 'lt' then Result := Result + '<'
    else if ent = 'gt' then Result := Result + '>'
    else if ent = 'amp' then Result := Result + '&'
    else if ent = 'quot' then Result := Result + '"'
    else if ent = 'apos' then Result := Result + ''''
    else if (Length(ent) > 1) and (ent[1] = '#') then
    begin
      if (ent[2] = 'x') or (ent[2] = 'X') then
        ok := TryStrToDWord('$' + Copy(ent, 3, MaxInt), code) and (Length(ent) > 2)
      else
        ok := TryStrToDWord(Copy(ent, 2, MaxInt), code);
      if ok then Result := Result + CodePointUtf8(code);
    end
    else
      ok := False;
    if not ok then Result := Result + '&' + ent + ';';
    i := j + 1;
  end;
end;

function LocalName(const AName: string): string;
var
  p: Integer;
begin
  p := Pos(':', AName);
  if p = 0 then Exit(AName);
  // Only the SVG namespace's prefix stands for SVG (and xlink's, for its
  // href); other prefixes (an editor's own) are kept, and so ignored.
  if (Copy(AName, 1, p - 1) = 'svg') or (Copy(AName, 1, p - 1) = 'xlink') then Result := Copy(AName, p + 1, MaxInt)
  else Result := AName;
end;

function IsNameChar(C: Char): Boolean; inline;
begin
  Result := C in ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.', ':', #$80..#$FF];
end;

function IsSpace(C: Char): Boolean; inline;
begin
  Result := C in [' ', #9, #10, #13];
end;

procedure ParseXml(const S: string; var ADoc: TXDoc);
var
  p, n, cur, depth: Integer;

  function NewNode(const AName: string): Integer;
  begin
    if ADoc.Count >= RTSVG_MAX_NODES then TooBig('nodes');
    if ADoc.Count >= Length(ADoc.Nodes) then
      SetLength(ADoc.Nodes, Max(256, Length(ADoc.Nodes) * 2));
    Result := ADoc.Count;
    Inc(ADoc.Count);
    ADoc.Nodes[Result].Name := AName;
    ADoc.Nodes[Result].Attrs := nil;
    ADoc.Nodes[Result].Text := '';
    ADoc.Nodes[Result].Parent := cur;
    ADoc.Nodes[Result].FirstChild := -1;
    ADoc.Nodes[Result].LastChild := -1;
    ADoc.Nodes[Result].Next := -1;
    if cur >= 0 then
    begin
      if ADoc.Nodes[cur].LastChild >= 0 then
        ADoc.Nodes[ADoc.Nodes[cur].LastChild].Next := Result
      else
        ADoc.Nodes[cur].FirstChild := Result;
      ADoc.Nodes[cur].LastChild := Result;
    end;
  end;

  procedure AddText(const AText: string);
  var
    t: Integer;
  begin
    if cur < 0 then Exit;     // text outside the root
    t := NewNode('');
    ADoc.Nodes[t].Text := AText;
  end;

  function Find(const AWhat: string): Integer;
  begin
    // (Codex review 90) From p, never copying the rest of the document.
    Result := PosEx(AWhat, S, p);
    if Result = 0 then Broken('unterminated ' + AWhat);
  end;

  procedure SkipDoctype;
  begin
    // A doctype naming its DTD is harmless (never read); one declaring
    // anything (an internal subset) is refused: no entity can exist.
    while (p <= n) and (S[p] <> '>') do
    begin
      if S[p] = '[' then raise ERtSvg.Create(rsSvgDtd);
      if S[p] in ['"', ''''] then
      begin
        Inc(p);
        while (p <= n) and not (S[p] in ['"', '''']) do Inc(p);
      end;
      Inc(p);
    end;
    if p > n then Broken('doctype');
    Inc(p);
  end;

  procedure ReadTag;
  var
    q, node: Integer;
    name, aname, value: string;
    quote: Char;
    closing: Boolean;
  begin
    // At '<' + a name character.
    Inc(p);
    q := p;
    while (p <= n) and IsNameChar(S[p]) do Inc(p);
    name := LocalName(Copy(S, q, p - q));
    if name = '' then Broken('element name');
    if depth >= RTSVG_MAX_DEPTH then TooBig('nesting');
    node := NewNode(name);
    closing := False;
    while True do
    begin
      while (p <= n) and IsSpace(S[p]) do Inc(p);
      if p > n then Broken('tag');
      if S[p] = '>' then begin Inc(p); Break; end;
      if (S[p] = '/') and (p < n) and (S[p + 1] = '>') then
      begin
        Inc(p, 2);
        closing := True;
        Break;
      end;
      q := p;
      while (p <= n) and IsNameChar(S[p]) do Inc(p);
      aname := Copy(S, q, p - q);
      if aname = '' then Broken('attribute');
      while (p <= n) and IsSpace(S[p]) do Inc(p);
      if (p > n) or (S[p] <> '=') then Broken('attribute ' + aname);
      Inc(p);
      while (p <= n) and IsSpace(S[p]) do Inc(p);
      if (p > n) or not (S[p] in ['"', '''']) then Broken('attribute ' + aname);
      quote := S[p];
      Inc(p);
      q := p;
      while (p <= n) and (S[p] <> quote) do Inc(p);
      if p > n then Broken('attribute ' + aname);
      value := DecodeEntities(Copy(S, q, p - q));
      Inc(p);
      if Length(ADoc.Nodes[node].Attrs) >= 400 then TooBig('attributes');
      SetLength(ADoc.Nodes[node].Attrs, Length(ADoc.Nodes[node].Attrs) + 2);
      ADoc.Nodes[node].Attrs[High(ADoc.Nodes[node].Attrs) - 1] := LocalName(aname);
      ADoc.Nodes[node].Attrs[High(ADoc.Nodes[node].Attrs)] := value;
    end;
    if not closing then
    begin
      cur := node;
      Inc(depth);
    end;
  end;

  procedure ReadClose;
  var
    q: Integer;
    name: string;
  begin
    Inc(p, 2);
    q := p;
    while (p <= n) and IsNameChar(S[p]) do Inc(p);
    name := LocalName(Copy(S, q, p - q));
    while (p <= n) and IsSpace(S[p]) do Inc(p);
    if (p > n) or (S[p] <> '>') then Broken('closing tag');
    Inc(p);
    if (cur < 0) or (ADoc.Nodes[cur].Name <> name) then Broken('</' + name + '>');
    cur := ADoc.Nodes[cur].Parent;
    Dec(depth);
  end;

var
  q, e: Integer;
begin
  ADoc.Count := 0;
  ADoc.Nodes := nil;
  n := Length(S);
  p := 1;
  cur := -1;
  depth := 0;
  while p <= n do
  begin
    if S[p] <> '<' then
    begin
      q := p;
      while (p <= n) and (S[p] <> '<') do Inc(p);
      if cur >= 0 then AddText(DecodeEntities(Copy(S, q, p - q)));
      Continue;
    end;
    if p = n then Broken('<');
    case S[p + 1] of
      '?':
        begin
          e := Find('?>');
          p := e + 2;
        end;
      '!':
        if Copy(S, p, 4) = '<!--' then
        begin
          Inc(p, 4);
          e := Find('-->');
          p := e + 3;
        end
        else if Copy(S, p, 9) = '<![CDATA[' then
        begin
          Inc(p, 9);
          e := Find(']]>');
          if cur >= 0 then AddText(Copy(S, p, e - p));
          p := e + 3;
        end
        else if UpperCase(Copy(S, p, 9)) = '<!DOCTYPE' then
        begin
          Inc(p, 9);
          SkipDoctype;
        end
        else
          raise ERtSvg.Create(rsSvgDtd);
      '/':
        ReadClose;
    else
      if IsNameChar(S[p + 1]) then
      begin
        if (cur < 0) and (ADoc.Count > 0) then Broken('second root');
        ReadTag;
      end
      else
        Broken('<');
    end;
  end;
  if cur >= 0 then Broken('unclosed <' + ADoc.Nodes[cur].Name + '>');
  if ADoc.Count = 0 then raise ERtSvg.Create(rsSvgNotSvg);
end;

function Attr(const ANode: TXNode; const AName: string; out AValue: string): Boolean;
var
  i: Integer;
begin
  i := 0;
  while i < High(ANode.Attrs) do
  begin
    if ANode.Attrs[i] = AName then
    begin
      AValue := ANode.Attrs[i + 1];
      Exit(True);
    end;
    Inc(i, 2);
  end;
  AValue := '';
  Result := False;
end;

function AttrOr(const ANode: TXNode; const AName, ADefault: string): string;
begin
  if not Attr(ANode, AName, Result) then Result := ADefault;
end;

{ UTF-16 with its byte order mark becomes UTF-8; a UTF-8 mark is dropped. }
function ToUtf8(const AData: RawByteString): string;
var
  u: UnicodeString;
  i, n: Integer;
  be: Boolean;
begin
  if (Length(AData) >= 2) and (((AData[1] = #$FF) and (AData[2] = #$FE)) or
    ((AData[1] = #$FE) and (AData[2] = #$FF))) then
  begin
    be := AData[1] = #$FE;
    n := (Length(AData) - 2) div 2;
    SetLength(u, n);
    for i := 1 to n do
      if be then
        u[i] := WideChar((Ord(AData[1 + 2 * i]) shl 8) or Ord(AData[2 + 2 * i]))
      else
        u[i] := WideChar(Ord(AData[1 + 2 * i]) or (Ord(AData[2 + 2 * i]) shl 8));
    Result := UTF8Encode(u);
  end
  else if (Length(AData) >= 3) and (AData[1] = #$EF) and (AData[2] = #$BB) and (AData[3] = #$BF) then
    Result := Copy(AData, 4, MaxInt)
  else
    Result := AData;
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

function RtSvgSniff(const AData: RawByteString): Boolean;
var
  head: string;
begin
  head := LowerCase(ToUtf8(Copy(AData, 1, 4096)));
  // Binary images never start with these.
  Result := (Pos('<svg', head) > 0) and (Pos('<', TrimLeft(head)) = 1);
end;

{ ---------------------------------------------------------------------------
  Values: numbers, lengths, colours, transforms
  --------------------------------------------------------------------------- }

var
  Dot: TFormatSettings;

{ Reads a number at S[P], moving P past it. }
function ReadNumber(const S: string; var P: Integer; out AValue: Double): Boolean;
var
  q, n: Integer;
  digits: Boolean;
begin
  n := Length(S);
  q := P;
  if (P <= n) and (S[P] in ['+', '-']) then Inc(P);
  digits := False;
  while (P <= n) and (S[P] in ['0'..'9']) do begin Inc(P); digits := True; end;
  if (P <= n) and (S[P] = '.') then
  begin
    Inc(P);
    while (P <= n) and (S[P] in ['0'..'9']) do begin Inc(P); digits := True; end;
  end;
  if not digits then
  begin
    P := q;
    AValue := 0;
    Exit(False);
  end;
  if (P < n) and (S[P] in ['e', 'E']) and ((S[P + 1] in ['0'..'9']) or
    ((P + 1 < n) and (S[P + 1] in ['+', '-']) and (S[P + 2] in ['0'..'9']))) then
  begin
    Inc(P, 2);
    while (P <= n) and (S[P] in ['0'..'9']) do Inc(P);
  end;
  Result := TryStrToFloat(Copy(S, q, P - q), AValue, Dot) and not IsNan(AValue) and
    not IsInfinite(AValue) and (Abs(AValue) < 1e15);
  if not Result then AValue := 0;
end;

procedure SkipSep(const S: string; var P: Integer);
begin
  while (P <= Length(S)) and (IsSpace(S[P]) or (S[P] = ',')) do Inc(P);
end;

{ A length in pixels: px, pt, pc, mm, cm, in, em (of AFont), % (of ARef). }
function Length_(const S: string; ADefault, AFont, ARef: Double): Double;
var
  p: Integer;
  v: Double;
  u: string;
begin
  p := 1;
  SkipSep(S, p);
  if not ReadNumber(S, p, v) then Exit(ADefault);
  u := LowerCase(Trim(Copy(S, p, 3)));
  if u = '' then Result := v
  else if u = 'px' then Result := v
  else if u = 'pt' then Result := v * 4 / 3
  else if u = 'pc' then Result := v * 16
  else if u = 'mm' then Result := v * 96 / 25.4
  else if u = 'cm' then Result := v * 96 / 2.54
  else if u = 'in' then Result := v * 96
  else if u = 'em' then Result := v * AFont
  else if u = 'ex' then Result := v * AFont / 2
  else if u[1] = '%' then Result := v * ARef / 100
  else Result := v;
end;

function Number_(const S: string; ADefault: Double): Double;
begin
  Result := Length_(S, ADefault, 16, 0);
end;

type
  TNamedColor = record
    Name: string;
    RGB: Cardinal;
  end;

const
  NAMED_COLORS: array[0..41] of TNamedColor = (
    (Name: 'black'; RGB: $000000), (Name: 'white'; RGB: $FFFFFF),
    (Name: 'red'; RGB: $FF0000), (Name: 'green'; RGB: $008000),
    (Name: 'blue'; RGB: $0000FF), (Name: 'yellow'; RGB: $FFFF00),
    (Name: 'cyan'; RGB: $00FFFF), (Name: 'aqua'; RGB: $00FFFF),
    (Name: 'magenta'; RGB: $FF00FF), (Name: 'fuchsia'; RGB: $FF00FF),
    (Name: 'gray'; RGB: $808080), (Name: 'grey'; RGB: $808080),
    (Name: 'silver'; RGB: $C0C0C0), (Name: 'maroon'; RGB: $800000),
    (Name: 'olive'; RGB: $808000), (Name: 'lime'; RGB: $00FF00),
    (Name: 'teal'; RGB: $008080), (Name: 'navy'; RGB: $000080),
    (Name: 'purple'; RGB: $800080), (Name: 'orange'; RGB: $FFA500),
    (Name: 'brown'; RGB: $A52A2A), (Name: 'pink'; RGB: $FFC0CB),
    (Name: 'gold'; RGB: $FFD700), (Name: 'beige'; RGB: $F5F5DC),
    (Name: 'darkgray'; RGB: $A9A9A9), (Name: 'darkgrey'; RGB: $A9A9A9),
    (Name: 'lightgray'; RGB: $D3D3D3), (Name: 'lightgrey'; RGB: $D3D3D3),
    (Name: 'dimgray'; RGB: $696969), (Name: 'dimgrey'; RGB: $696969),
    (Name: 'gainsboro'; RGB: $DCDCDC), (Name: 'whitesmoke'; RGB: $F5F5F5),
    (Name: 'darkred'; RGB: $8B0000), (Name: 'darkgreen'; RGB: $006400),
    (Name: 'darkblue'; RGB: $00008B), (Name: 'lightblue'; RGB: $ADD8E6),
    (Name: 'lightgreen'; RGB: $90EE90), (Name: 'lightyellow'; RGB: $FFFFE0),
    (Name: 'ivory'; RGB: $FFFFF0), (Name: 'linen'; RGB: $FAF0E6),
    (Name: 'tan'; RGB: $D2B48C), (Name: 'khaki'; RGB: $F0E68C));

function LumOf(R, G, B: Double): Single;
begin
  Result := EnsureRange((0.2126 * R + 0.7152 * G + 0.0722 * B) / 255, 0, 1);
end;

function HexVal(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

{ A colour as a grey level and an opacity; False when not a colour. }
function ParseColor(const AValue: string; out ALum, AAlpha: Single): Boolean;
var
  s: string;
  i, p: Integer;
  v: array[0..3] of Double;
  h: array of Integer;
  pct: Boolean;
begin
  s := LowerCase(Trim(AValue));
  ALum := 0;
  AAlpha := 1;
  Result := False;
  if s = '' then Exit;
  if s[1] = '#' then
  begin
    SetLength(h, Length(s) - 1);
    for i := 2 to Length(s) do
    begin
      h[i - 2] := HexVal(s[i]);
      if h[i - 2] < 0 then Exit;
    end;
    case Length(h) of
      3, 4:
        begin
          ALum := LumOf(h[0] * 17, h[1] * 17, h[2] * 17);
          if Length(h) = 4 then AAlpha := h[3] * 17 / 255;
        end;
      6, 8:
        begin
          ALum := LumOf(h[0] * 16 + h[1], h[2] * 16 + h[3], h[4] * 16 + h[5]);
          if Length(h) = 8 then AAlpha := (h[6] * 16 + h[7]) / 255;
        end;
    else
      Exit;
    end;
    Exit(True);
  end;
  if (Copy(s, 1, 4) = 'rgb(') or (Copy(s, 1, 5) = 'rgba(') then
  begin
    p := Pos('(', s) + 1;
    for i := 0 to 3 do
    begin
      SkipSep(s, p);
      if (p <= Length(s)) and (s[p] = '/') then begin Inc(p); SkipSep(s, p); end;
      if not ReadNumber(s, p, v[i]) then
      begin
        if i < 3 then Exit;
        v[3] := 1;
        Break;
      end;
      pct := (p <= Length(s)) and (s[p] = '%');
      if pct then
      begin
        Inc(p);
        if i < 3 then v[i] := v[i] * 2.55 else v[i] := v[i] / 100;
      end;
    end;
    ALum := LumOf(EnsureRange(v[0], 0, 255), EnsureRange(v[1], 0, 255), EnsureRange(v[2], 0, 255));
    AAlpha := EnsureRange(v[3], 0, 1);
    Exit(True);
  end;
  if s = 'transparent' then
  begin
    AAlpha := 0;
    Exit(True);
  end;
  for i := Low(NAMED_COLORS) to High(NAMED_COLORS) do
    if NAMED_COLORS[i].Name = s then
    begin
      ALum := LumOf((NAMED_COLORS[i].RGB shr 16) and $FF, (NAMED_COLORS[i].RGB shr 8) and $FF,
        NAMED_COLORS[i].RGB and $FF);
      Exit(True);
    end;
end;

function ParseTransform(const S: string; out AM: TRtSvgMatrix): Boolean;
var
  p, q, k: Integer;
  name: string;
  a: array[0..5] of Double;
  t: TRtSvgMatrix;
  ang, c, sn: Double;
begin
  AM := RtSvgIdentity;
  Result := True;
  p := 1;
  while True do
  begin
    SkipSep(S, p);
    if p > Length(S) then Break;
    q := p;
    while (p <= Length(S)) and (S[p] in ['a'..'z', 'A'..'Z']) do Inc(p);
    name := LowerCase(Copy(S, q, p - q));
    SkipSep(S, p);
    if (name = '') or (p > Length(S)) or (S[p] <> '(') then Exit(False);
    Inc(p);
    k := 0;
    while True do
    begin
      SkipSep(S, p);
      if (p <= Length(S)) and (S[p] = ')') then begin Inc(p); Break; end;
      if (k > 5) or not ReadNumber(S, p, a[k]) then Exit(False);
      Inc(k);
    end;
    if (name = 'matrix') and (k = 6) then
      t := RtSvgMatrix(a[0], a[1], a[2], a[3], a[4], a[5])
    else if (name = 'translate') and (k in [1, 2]) then
    begin
      if k = 1 then a[1] := 0;
      t := RtSvgTranslate(a[0], a[1]);
    end
    else if (name = 'scale') and (k in [1, 2]) then
    begin
      if k = 1 then a[1] := a[0];
      t := RtSvgScale(a[0], a[1]);
    end
    else if (name = 'rotate') and (k in [1, 3]) then
    begin
      ang := DegToRad(a[0]);
      c := Cos(ang);
      sn := Sin(ang);
      t := RtSvgMatrix(c, sn, -sn, c, 0, 0);
      if k = 3 then
        t := RtSvgMul(RtSvgTranslate(a[1], a[2]), RtSvgMul(t, RtSvgTranslate(-a[1], -a[2])));
    end
    else if (name = 'skewx') and (k = 1) then
      t := RtSvgMatrix(1, 0, Tan(DegToRad(a[0])), 1, 0, 0)
    else if (name = 'skewy') and (k = 1) then
      t := RtSvgMatrix(1, Tan(DegToRad(a[0])), 0, 1, 0, 0)
    else
      Exit(False);
    AM := RtSvgMul(AM, t);
  end;
end;

{ ---------------------------------------------------------------------------
  Building the shapes from the tree
  --------------------------------------------------------------------------- }

type
  TPaintKind = (pkNone, pkColor, pkCurrent);

  TPaint = record
    Kind: TPaintKind;
    Lum, Alpha: Single;
  end;

  TStyle = record
    Fill, Stroke: TPaint;
    ColorLum, ColorAlpha: Single;    // currentColor
    FillOpacity, StrokeOpacity, Opacity: Single;
    StrokeWidth, MiterLimit, DashOffset: Double;
    Dash: array of Double;
    Cap: TRtSvgCap;
    Join: TRtSvgJoin;
    EvenOdd: Boolean;
    FontSize: Double;
    Bold, Italic, Mono: Boolean;
    Anchor, Baseline: Integer;
    Hidden: Boolean;                 // visibility: hidden
  end;

  TBuilder = class
    Img: TRtSvgImage;
    Doc: TXDoc;
    Ids: array of string;            // sorted id -> node, for <use> and gradients
    IdNodes: array of Integer;
    UseDepth: Integer;
    Visits: Integer;
    ViewW, ViewH: Double;
    procedure IndexIds;
    function FindId(const AId: string): Integer;
    procedure ApplyProperty(var AStyle: TStyle; const AName, AValue: string);
    procedure ApplyStyle(var AStyle: TStyle; const ANode: TXNode);
    function GradientPaint(const AId: string; out APaint: TPaint): Boolean;
    function ParsePaint(const AValue: string; const AStyle: TStyle; var APaint: TPaint): Boolean;
    procedure AddCmd(ACmd: Byte; const APts: array of Double);
    procedure Walk(ANode: Integer; AStyle: TStyle; const AM: TRtSvgMatrix);
    procedure Element(ANode: Integer; const AStyle: TStyle; const AM: TRtSvgMatrix);
    procedure FinishShape(AFirstCmd, AFirstPt: Integer; const AStyle: TStyle; const AM: TRtSvgMatrix);
    procedure ArcTo(X0, Y0, RX, RY, APhi: Double; ALarge, ASweep: Boolean; X, Y: Double);
    procedure Ellipse(CX, CY, RX, RY: Double);
    procedure RoundRect(X, Y, W, H, RX, RY: Double);
    procedure Points(const S: string; AClose: Boolean);
    procedure TextElement(ANode: Integer; const AStyle: TStyle; const AM: TRtSvgMatrix);
  end;

function DefaultStyle: TStyle;
begin
  Result := Default(TStyle);
  Result.Fill.Kind := pkColor;
  Result.Fill.Lum := 0;
  Result.Fill.Alpha := 1;
  Result.Stroke.Kind := pkNone;
  Result.ColorLum := 0;
  Result.ColorAlpha := 1;
  Result.FillOpacity := 1;
  Result.StrokeOpacity := 1;
  Result.Opacity := 1;
  Result.StrokeWidth := 1;
  Result.MiterLimit := 4;
  Result.FontSize := 16;
end;

procedure TBuilder.IndexIds;
var
  found: array of string;
  nodes, tmp: array of Integer;
  i, n, w, lo, mid, hi, a, b, k, c: Integer;
  id: string;
begin
  // (Codex review 90) Gathered, then merge-sorted once by id and by place
  // in the document (the first of duplicated ids wins): never quadratic.
  n := 0;
  SetLength(found, 0);
  SetLength(nodes, 0);
  for i := 0 to Doc.Count - 1 do
    if (Doc.Nodes[i].Name <> '') and Attr(Doc.Nodes[i], 'id', id) and (id <> '') then
    begin
      if n >= Length(nodes) then
      begin
        SetLength(nodes, Max(64, 2 * n));
        SetLength(found, Length(nodes));
      end;
      found[n] := id;
      nodes[n] := i;
      Inc(n);
    end;
  // nodes[] holds node indexes; found[k] is the id of the k-th gathered one:
  // sort positions 0..n-1 through an index of positions.
  SetLength(tmp, n);
  SetLength(IdNodes, n);
  for i := 0 to n - 1 do IdNodes[i] := i;
  w := 1;
  while w < n do
  begin
    lo := 0;
    while lo < n do
    begin
      mid := Min(lo + w, n);
      hi := Min(lo + 2 * w, n);
      a := lo; b := mid; k := lo;
      while (a < mid) and (b < hi) do
      begin
        c := CompareStr(found[IdNodes[a]], found[IdNodes[b]]);
        if (c < 0) or ((c = 0) and (IdNodes[a] <= IdNodes[b])) then
        begin
          tmp[k] := IdNodes[a];
          Inc(a);
        end
        else
        begin
          tmp[k] := IdNodes[b];
          Inc(b);
        end;
        Inc(k);
      end;
      while a < mid do begin tmp[k] := IdNodes[a]; Inc(a); Inc(k); end;
      while b < hi do begin tmp[k] := IdNodes[b]; Inc(b); Inc(k); end;
      lo := hi;
    end;
    for i := 0 to n - 1 do IdNodes[i] := tmp[i];
    w := w * 2;
  end;
  // Kept: the first of each id, as node indexes.
  SetLength(Ids, n);
  k := 0;
  for i := 0 to n - 1 do
    if (k = 0) or (Ids[k - 1] <> found[IdNodes[i]]) then
    begin
      Ids[k] := found[IdNodes[i]];
      tmp[k] := nodes[IdNodes[i]];
      Inc(k);
    end;
  SetLength(Ids, k);
  SetLength(IdNodes, k);
  for i := 0 to k - 1 do IdNodes[i] := tmp[i];
end;

function TBuilder.FindId(const AId: string): Integer;
var
  lo, hi, mid, c: Integer;
begin
  lo := 0;
  hi := High(Ids);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    c := CompareStr(Ids[mid], AId);
    if c = 0 then Exit(IdNodes[mid]);
    if c < 0 then lo := mid + 1 else hi := mid - 1;
  end;
  Result := -1;
end;

{ A gradient or pattern: the average of its stops (or of the gradient it
  inherits them from). }
function TBuilder.GradientPaint(const AId: string; out APaint: TPaint): Boolean;
var
  node, ch, hops, cnt: Integer;
  href, v: string;
  lum, alpha, sumL, sumA, op: Single;
  st: TStyle;
begin
  Result := False;
  APaint.Kind := pkColor;
  APaint.Lum := 0.5;
  APaint.Alpha := 1;
  node := FindId(AId);
  hops := 0;
  while node >= 0 do
  begin
    sumL := 0;
    sumA := 0;
    cnt := 0;
    ch := Doc.Nodes[node].FirstChild;
    while ch >= 0 do
    begin
      if Doc.Nodes[ch].Name = 'stop' then
      begin
        st := DefaultStyle;
        st.Fill.Lum := 0;    // stop-color defaults to black
        lum := 0;
        alpha := 1;
        v := AttrOr(Doc.Nodes[ch], 'stop-color', '');
        op := 1;
        if Attr(Doc.Nodes[ch], 'style', href) then
        begin
          // style="stop-color:...;stop-opacity:..."
          if Pos('stop-color', href) > 0 then
            v := Trim(Copy(href, Pos('stop-color', href) + 11, MaxInt));
          if Pos(';', v) > 0 then v := Copy(v, 1, Pos(';', v) - 1);
          if Pos('stop-opacity', href) > 0 then
            op := Number_(Copy(href, Pos('stop-opacity', href) + 13, 20), 1);
        end;
        if v <> '' then ParseColor(v, lum, alpha);
        op := op * Number_(AttrOr(Doc.Nodes[ch], 'stop-opacity', '1'), 1);
        sumL := sumL + lum;
        sumA := sumA + alpha * EnsureRange(op, 0, 1);
        Inc(cnt);
      end;
      ch := Doc.Nodes[ch].Next;
    end;
    if cnt > 0 then
    begin
      APaint.Lum := sumL / cnt;
      APaint.Alpha := sumA / cnt;
      Exit(True);
    end;
    // No stop of its own: those of the gradient it names.
    Inc(hops);
    if (hops > 8) or not (Attr(Doc.Nodes[node], 'href', href)) or (Copy(href, 1, 1) <> '#') then Break;
    node := FindId(Copy(href, 2, MaxInt));
  end;
end;

function TBuilder.ParsePaint(const AValue: string; const AStyle: TStyle; var APaint: TPaint): Boolean;
var
  v, id: string;
  p: Integer;
  lum, alpha: Single;
begin
  Result := True;
  v := Trim(AValue);
  if (v = '') or (LowerCase(v) = 'inherit') then Exit(False);
  if LowerCase(v) = 'none' then APaint.Kind := pkNone
  else if LowerCase(v) = 'currentcolor' then APaint.Kind := pkCurrent
  else if LowerCase(Copy(v, 1, 4)) = 'url(' then
  begin
    p := Pos(')', v);
    id := Trim(Copy(v, 5, p - 5));
    if (id <> '') and (id[1] in ['"', '''']) then id := Copy(id, 2, Length(id) - 2);
    if (Copy(id, 1, 1) = '#') and GradientPaint(Copy(id, 2, MaxInt), APaint) then Exit;
    // Not found: the fallback colour written after it, else a mid grey.
    if (p > 0) and ParseColor(Copy(v, p + 1, MaxInt), lum, alpha) then
    begin
      APaint.Kind := pkColor;
      APaint.Lum := lum;
      APaint.Alpha := alpha;
    end
    else if (p > 0) and (LowerCase(Trim(Copy(v, p + 1, MaxInt))) = 'none') then
      APaint.Kind := pkNone
    else
    begin
      APaint.Kind := pkColor;
      APaint.Lum := 0.5;
      APaint.Alpha := 1;
    end;
  end
  else if ParseColor(v, lum, alpha) then
  begin
    APaint.Kind := pkColor;
    APaint.Lum := lum;
    APaint.Alpha := alpha;
  end
  else
    Result := False;
end;

procedure TBuilder.ApplyProperty(var AStyle: TStyle; const AName, AValue: string);
var
  v, fam: string;
  p, k: Integer;
  d: Double;
  lum, alpha: Single;
begin
  v := Trim(AValue);
  if (v = '') or (LowerCase(v) = 'inherit') then Exit;
  if AName = 'fill' then ParsePaint(v, AStyle, AStyle.Fill)
  else if AName = 'stroke' then ParsePaint(v, AStyle, AStyle.Stroke)
  else if AName = 'color' then
  begin
    if ParseColor(v, lum, alpha) then
    begin
      AStyle.ColorLum := lum;
      AStyle.ColorAlpha := alpha;
    end;
  end
  else if AName = 'fill-opacity' then AStyle.FillOpacity := EnsureRange(Number_(v, 1), 0, 1)
  else if AName = 'stroke-opacity' then AStyle.StrokeOpacity := EnsureRange(Number_(v, 1), 0, 1)
  else if AName = 'opacity' then AStyle.Opacity := AStyle.Opacity * EnsureRange(Number_(v, 1), 0, 1)
  else if AName = 'stroke-width' then AStyle.StrokeWidth := Max(0, Length_(v, 1, AStyle.FontSize, 0))
  else if AName = 'stroke-miterlimit' then AStyle.MiterLimit := Max(1, Number_(v, 4))
  else if AName = 'stroke-dashoffset' then AStyle.DashOffset := Length_(v, 0, AStyle.FontSize, 0)
  else if AName = 'stroke-dasharray' then
  begin
    AStyle.Dash := nil;
    if LowerCase(v) <> 'none' then
    begin
      p := 1;
      while True do
      begin
        SkipSep(v, p);
        if not ReadNumber(v, p, d) then Break;
        while (p <= Length(v)) and (v[p] in ['a'..'z', '%']) do Inc(p);
        if (d < 0) or (Length(AStyle.Dash) >= 64) then
        begin
          AStyle.Dash := nil;
          Break;
        end;
        SetLength(AStyle.Dash, Length(AStyle.Dash) + 1);
        AStyle.Dash[High(AStyle.Dash)] := d;
      end;
      // An odd list is repeated; an all-zero list means solid.
      if Odd(Length(AStyle.Dash)) then
      begin
        k := Length(AStyle.Dash);
        SetLength(AStyle.Dash, 2 * k);
        for p := 0 to k - 1 do AStyle.Dash[k + p] := AStyle.Dash[p];
      end;
      d := 0;
      for p := 0 to High(AStyle.Dash) do d := d + AStyle.Dash[p];
      if d <= 0 then AStyle.Dash := nil;
    end;
  end
  else if AName = 'stroke-linecap' then
  begin
    if v = 'round' then AStyle.Cap := rcRound
    else if v = 'square' then AStyle.Cap := rcSquare
    else AStyle.Cap := rcButt;
  end
  else if AName = 'stroke-linejoin' then
  begin
    if v = 'round' then AStyle.Join := rjRound
    else if v = 'bevel' then AStyle.Join := rjBevel
    else AStyle.Join := rjMiter;
  end
  else if AName = 'fill-rule' then AStyle.EvenOdd := v = 'evenodd'
  else if AName = 'font-size' then
  begin
    d := Length_(v, AStyle.FontSize, AStyle.FontSize, AStyle.FontSize);
    if (d > 0) and (d < 1e6) then AStyle.FontSize := d;
  end
  else if AName = 'font-weight' then
    AStyle.Bold := (v = 'bold') or (v = 'bolder') or (Number_(v, 400) >= 600)
  else if AName = 'font-style' then AStyle.Italic := (v = 'italic') or (v = 'oblique')
  else if AName = 'font-family' then
  begin
    fam := LowerCase(v);
    AStyle.Mono := (Pos('mono', fam) > 0) or (Pos('courier', fam) > 0) or (Pos('consol', fam) > 0);
  end
  else if AName = 'font' then
  begin
    // The shorthand: its size (a number with a unit) and boldness.
    AStyle.Bold := Pos('bold', LowerCase(v)) > 0;
    p := 1;
    while p <= Length(v) do
    begin
      if v[p] in ['0'..'9'] then
      begin
        d := Length_(Copy(v, p, 12), 0, AStyle.FontSize, AStyle.FontSize);
        if d > 0 then AStyle.FontSize := d;
        Break;
      end;
      Inc(p);
    end;
  end
  else if AName = 'text-anchor' then
  begin
    if v = 'middle' then AStyle.Anchor := 1
    else if v = 'end' then AStyle.Anchor := 2
    else AStyle.Anchor := 0;
  end
  else if (AName = 'dominant-baseline') or (AName = 'alignment-baseline') then
  begin
    if (v = 'central') or (v = 'middle') then AStyle.Baseline := 1
    else if (v = 'hanging') or (v = 'text-before-edge') or (v = 'text-top') then AStyle.Baseline := 2
    else AStyle.Baseline := 0;
  end
  else if AName = 'visibility' then AStyle.Hidden := (v = 'hidden') or (v = 'collapse');
end;

const
  STYLE_PROPS: array[0..22] of string = ('fill', 'stroke', 'color', 'fill-opacity', 'stroke-opacity',
    'opacity', 'stroke-width', 'stroke-miterlimit', 'stroke-dashoffset', 'stroke-dasharray',
    'stroke-linecap', 'stroke-linejoin', 'fill-rule', 'font-size', 'font-weight', 'font-style',
    'font-family', 'font', 'text-anchor', 'dominant-baseline', 'alignment-baseline', 'visibility',
    'display');

procedure TBuilder.ApplyStyle(var AStyle: TStyle; const ANode: TXNode);
var
  i, p, q: Integer;
  v, decl, name: string;
begin
  // Presentation attributes first ('color' before the paints that may name
  // currentColor), then style="", which wins.
  if Attr(ANode, 'color', v) then ApplyProperty(AStyle, 'color', v);
  for i := Low(STYLE_PROPS) to High(STYLE_PROPS) do
    if (STYLE_PROPS[i] <> 'color') and (STYLE_PROPS[i] <> 'display') and Attr(ANode, STYLE_PROPS[i], v) then
      ApplyProperty(AStyle, STYLE_PROPS[i], v);
  if Attr(ANode, 'style', v) then
  begin
    p := 1;
    while p <= Length(v) do
    begin
      q := p;
      while (q <= Length(v)) and (v[q] <> ';') do Inc(q);
      decl := Copy(v, p, q - p);
      p := q + 1;
      q := Pos(':', decl);
      if q = 0 then Continue;
      name := LowerCase(Trim(Copy(decl, 1, q - 1)));
      decl := Trim(Copy(decl, q + 1, MaxInt));
      if Pos('!important', decl) > 0 then decl := Trim(Copy(decl, 1, Pos('!important', decl) - 1));
      ApplyProperty(AStyle, name, decl);
    end;
  end;
end;

function IsHidden(const ANode: TXNode): Boolean;
var
  v: string;
  p: Integer;
begin
  Result := Attr(ANode, 'display', v) and (Trim(v) = 'none');
  if not Result and Attr(ANode, 'style', v) then
  begin
    v := StringReplace(LowerCase(v), ' ', '', [rfReplaceAll]);
    p := Pos('display:none', v);
    Result := (p > 0) and ((p = 1) or (v[p - 1] = ';'));
  end;
end;

procedure TBuilder.AddCmd(ACmd: Byte; const APts: array of Double);
var
  i: Integer;
begin
  if Img.FPtCount + Length(APts) > RTSVG_MAX_POINTS then TooBig('points');
  if Img.FCmdCount >= Length(Img.FCmds) then
    SetLength(Img.FCmds, Max(1024, Length(Img.FCmds) * 2));
  Img.FCmds[Img.FCmdCount] := ACmd;
  Inc(Img.FCmdCount);
  if Img.FPtCount + Length(APts) > Length(Img.FPts) then
    SetLength(Img.FPts, Max(Img.FPtCount + Length(APts), Max(2048, Length(Img.FPts) * 2)));
  for i := 0 to High(APts) do
    Img.FPts[Img.FPtCount + i] := APts[i];
  Inc(Img.FPtCount, Length(APts));
end;

procedure TBuilder.Ellipse(CX, CY, RX, RY: Double);
var
  kx, ky: Double;
begin
  kx := RX * KAPPA;
  ky := RY * KAPPA;
  AddCmd(CMD_MOVE, [CX + RX, CY]);
  AddCmd(CMD_CUBIC, [CX + RX, CY + ky, CX + kx, CY + RY, CX, CY + RY]);
  AddCmd(CMD_CUBIC, [CX - kx, CY + RY, CX - RX, CY + ky, CX - RX, CY]);
  AddCmd(CMD_CUBIC, [CX - RX, CY - ky, CX - kx, CY - RY, CX, CY - RY]);
  AddCmd(CMD_CUBIC, [CX + kx, CY - RY, CX + RX, CY - ky, CX + RX, CY]);
  AddCmd(CMD_CLOSE, []);
end;

procedure TBuilder.RoundRect(X, Y, W, H, RX, RY: Double);
var
  kx, ky: Double;
begin
  if (RX <= 0) or (RY <= 0) then
  begin
    AddCmd(CMD_MOVE, [X, Y]);
    AddCmd(CMD_LINE, [X + W, Y]);
    AddCmd(CMD_LINE, [X + W, Y + H]);
    AddCmd(CMD_LINE, [X, Y + H]);
    AddCmd(CMD_CLOSE, []);
    Exit;
  end;
  kx := RX * (1 - KAPPA);
  ky := RY * (1 - KAPPA);
  AddCmd(CMD_MOVE, [X + RX, Y]);
  AddCmd(CMD_LINE, [X + W - RX, Y]);
  AddCmd(CMD_CUBIC, [X + W - kx, Y, X + W, Y + ky, X + W, Y + RY]);
  AddCmd(CMD_LINE, [X + W, Y + H - RY]);
  AddCmd(CMD_CUBIC, [X + W, Y + H - ky, X + W - kx, Y + H, X + W - RX, Y + H]);
  AddCmd(CMD_LINE, [X + RX, Y + H]);
  AddCmd(CMD_CUBIC, [X + kx, Y + H, X, Y + H - ky, X, Y + H - RY]);
  AddCmd(CMD_LINE, [X, Y + RY]);
  AddCmd(CMD_CUBIC, [X, Y + ky, X + kx, Y, X + RX, Y]);
  AddCmd(CMD_CLOSE, []);
end;

function VecAngle(UX, UY, VX, VY: Double): Double;
begin
  Result := ArcTan2(UX * VY - UY * VX, UX * VX + UY * VY);
end;

{ The arc from (X0, Y0) to (X, Y) as cubics (SVG implementation notes F.6). }
procedure TBuilder.ArcTo(X0, Y0, RX, RY, APhi: Double; ALarge, ASweep: Boolean; X, Y: Double);
var
  cp, sp, x1, y1, lam, num, den, coef, cxp, cyp, cx, cy, th1, dth, dlt, t: Double;
  a1, a2, ux1, uy1, ux2, uy2, c1x, c1y, c2x, c2y: Double;
  i, n: Integer;

  procedure Map(UX, UY: Double; out AX, AY: Double);
  begin
    AX := cx + RX * cp * UX - RY * sp * UY;
    AY := cy + RX * sp * UX + RY * cp * UY;
  end;

var
  p1x, p1y, p2x, p2y, p3x, p3y: Double;
begin
  if (X0 = X) and (Y0 = Y) then Exit;
  RX := Abs(RX);
  RY := Abs(RY);
  if (RX < 1e-12) or (RY < 1e-12) then
  begin
    AddCmd(CMD_LINE, [X, Y]);
    Exit;
  end;
  cp := Cos(DegToRad(APhi));
  sp := Sin(DegToRad(APhi));
  x1 := cp * (X0 - X) / 2 + sp * (Y0 - Y) / 2;
  y1 := -sp * (X0 - X) / 2 + cp * (Y0 - Y) / 2;
  lam := Sqr(x1) / Sqr(RX) + Sqr(y1) / Sqr(RY);
  if lam > 1 then
  begin
    RX := RX * Sqrt(lam);
    RY := RY * Sqrt(lam);
  end;
  num := Sqr(RX) * Sqr(RY) - Sqr(RX) * Sqr(y1) - Sqr(RY) * Sqr(x1);
  den := Sqr(RX) * Sqr(y1) + Sqr(RY) * Sqr(x1);
  if den <= 0 then coef := 0 else coef := Sqrt(Max(0, num / den));
  if ALarge = ASweep then coef := -coef;
  cxp := coef * RX * y1 / RY;
  cyp := -coef * RY * x1 / RX;
  cx := cp * cxp - sp * cyp + (X0 + X) / 2;
  cy := sp * cxp + cp * cyp + (Y0 + Y) / 2;
  th1 := VecAngle(1, 0, (x1 - cxp) / RX, (y1 - cyp) / RY);
  dth := VecAngle((x1 - cxp) / RX, (y1 - cyp) / RY, (-x1 - cxp) / RX, (-y1 - cyp) / RY);
  if not ASweep and (dth > 0) then dth := dth - 2 * Pi
  else if ASweep and (dth < 0) then dth := dth + 2 * Pi;
  n := Max(1, Ceil(Abs(dth) / (Pi / 2) - 1e-9));
  dlt := dth / n;
  t := 4 / 3 * Tan(dlt / 4);
  for i := 0 to n - 1 do
  begin
    a1 := th1 + i * dlt;
    a2 := a1 + dlt;
    ux1 := Cos(a1); uy1 := Sin(a1);
    ux2 := Cos(a2); uy2 := Sin(a2);
    c1x := ux1 - t * uy1; c1y := uy1 + t * ux1;
    c2x := ux2 + t * uy2; c2y := uy2 - t * ux2;
    Map(c1x, c1y, p1x, p1y);
    Map(c2x, c2y, p2x, p2y);
    if i = n - 1 then
    begin
      p3x := X;
      p3y := Y;
    end
    else
      Map(ux2, uy2, p3x, p3y);
    AddCmd(CMD_CUBIC, [p1x, p1y, p2x, p2y, p3x, p3y]);
  end;
end;

{ Path data: every command, relative or absolute, arcs as cubics. }
procedure PathDataFull(B: TBuilder; const D: string);
var
  p, n: Integer;
  cmd, prev: Char;
  cx, cy, sx, sy, lcx, lcy, lqx, lqy, ox, oy, x1, y1, x2, y2: Double;
  v: array[0..6] of Double;
  rel, open, large, sweep: Boolean;

  function Num(out AValue: Double): Boolean;
  begin
    SkipSep(D, p);
    Result := ReadNumber(D, p, AValue);
  end;

  function Nums(ACount: Integer): Boolean;
  var
    i: Integer;
  begin
    for i := 0 to ACount - 1 do
      if not Num(v[i]) then Exit(False);
    Result := True;
  end;

  function Flag(out AFlag: Boolean): Boolean;
  begin
    SkipSep(D, p);
    Result := (p <= n) and (D[p] in ['0', '1']);
    if Result then
    begin
      AFlag := D[p] = '1';
      Inc(p);
    end;
  end;

  procedure EnsureOpen;
  begin
    if not open then
    begin
      B.AddCmd(CMD_MOVE, [cx, cy]);
      open := True;
    end;
  end;

var
  rx, ry, phi: Double;
begin
  n := Length(D);
  p := 1;
  cx := 0; cy := 0; sx := 0; sy := 0;
  lcx := 0; lcy := 0; lqx := 0; lqy := 0;
  prev := ' ';
  cmd := ' ';
  open := False;
  while True do
  begin
    SkipSep(D, p);
    if p > n then Break;
    if D[p] in ['A'..'Z', 'a'..'z'] then
    begin
      cmd := D[p];
      Inc(p);
      if not (cmd in ['M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c', 'S', 's', 'Q', 'q', 'T', 't',
        'A', 'a', 'Z', 'z']) then Break;     // a path stops at its first error, as in browsers
    end
    else if (cmd = ' ') or (cmd in ['Z', 'z']) then Break;
    rel := cmd in ['a'..'z'];
    if rel then begin ox := cx; oy := cy; end else begin ox := 0; oy := 0; end;
    case UpCase(cmd) of
      'M':
        begin
          if not Nums(2) then Break;
          cx := ox + v[0]; cy := oy + v[1];
          sx := cx; sy := cy;
          B.AddCmd(CMD_MOVE, [cx, cy]);
          open := True;
          // Pairs after a moveto are linetos.
          if cmd = 'M' then cmd := 'L' else cmd := 'l';
        end;
      'L':
        begin
          if not Nums(2) then Break;
          EnsureOpen;
          cx := ox + v[0]; cy := oy + v[1];
          B.AddCmd(CMD_LINE, [cx, cy]);
        end;
      'H':
        begin
          if not Nums(1) then Break;
          EnsureOpen;
          cx := ox + v[0];
          B.AddCmd(CMD_LINE, [cx, cy]);
        end;
      'V':
        begin
          if not Nums(1) then Break;
          EnsureOpen;
          if rel then cy := cy + v[0] else cy := v[0];
          B.AddCmd(CMD_LINE, [cx, cy]);
        end;
      'C':
        begin
          if not Nums(6) then Break;
          EnsureOpen;
          x1 := ox + v[0]; y1 := oy + v[1]; x2 := ox + v[2]; y2 := oy + v[3];
          cx := ox + v[4]; cy := oy + v[5];
          B.AddCmd(CMD_CUBIC, [x1, y1, x2, y2, cx, cy]);
          lcx := x2; lcy := y2;
        end;
      'S':
        begin
          if not Nums(4) then Break;
          EnsureOpen;
          if UpCase(prev) in ['C', 'S'] then begin x1 := 2 * cx - lcx; y1 := 2 * cy - lcy; end
          else begin x1 := cx; y1 := cy; end;
          x2 := ox + v[0]; y2 := oy + v[1];
          cx := ox + v[2]; cy := oy + v[3];
          B.AddCmd(CMD_CUBIC, [x1, y1, x2, y2, cx, cy]);
          lcx := x2; lcy := y2;
        end;
      'Q':
        begin
          if not Nums(4) then Break;
          EnsureOpen;
          lqx := ox + v[0]; lqy := oy + v[1];
          x2 := ox + v[2]; y2 := oy + v[3];
          B.AddCmd(CMD_CUBIC, [cx + 2 / 3 * (lqx - cx), cy + 2 / 3 * (lqy - cy),
            x2 + 2 / 3 * (lqx - x2), y2 + 2 / 3 * (lqy - y2), x2, y2]);
          cx := x2; cy := y2;
        end;
      'T':
        begin
          if not Nums(2) then Break;
          EnsureOpen;
          if UpCase(prev) in ['Q', 'T'] then begin lqx := 2 * cx - lqx; lqy := 2 * cy - lqy; end
          else begin lqx := cx; lqy := cy; end;
          x2 := ox + v[0]; y2 := oy + v[1];
          B.AddCmd(CMD_CUBIC, [cx + 2 / 3 * (lqx - cx), cy + 2 / 3 * (lqy - cy),
            x2 + 2 / 3 * (lqx - x2), y2 + 2 / 3 * (lqy - y2), x2, y2]);
          cx := x2; cy := y2;
        end;
      'A':
        begin
          if not Num(rx) or not Num(ry) or not Num(phi) then Break;
          if not Flag(large) or not Flag(sweep) then Break;
          if not Nums(2) then Break;
          EnsureOpen;
          x2 := ox + v[0]; y2 := oy + v[1];
          B.ArcTo(cx, cy, rx, ry, phi, large, sweep, x2, y2);
          cx := x2; cy := y2;
        end;
      'Z':
        begin
          if open then B.AddCmd(CMD_CLOSE, []);
          open := False;
          cx := sx; cy := sy;
        end;
    end;
    prev := cmd;
  end;
end;

procedure TBuilder.Points(const S: string; AClose: Boolean);
var
  p: Integer;
  x, y: Double;
  first: Boolean;
begin
  p := 1;
  first := True;
  while True do
  begin
    SkipSep(S, p);
    if not ReadNumber(S, p, x) then Break;
    SkipSep(S, p);
    if not ReadNumber(S, p, y) then Break;
    if first then AddCmd(CMD_MOVE, [x, y]) else AddCmd(CMD_LINE, [x, y]);
    first := False;
  end;
  if AClose and not first then AddCmd(CMD_CLOSE, []);
end;

procedure TBuilder.FinishShape(AFirstCmd, AFirstPt: Integer; const AStyle: TStyle; const AM: TRtSvgMatrix);
var
  sh: TRtSvgShape;
  p: TPaint;
begin
  if Img.FCmdCount = AFirstCmd then Exit;
  if AStyle.Hidden then
  begin
    Img.FCmdCount := AFirstCmd;
    Img.FPtCount := AFirstPt;
    Exit;
  end;
  sh := Default(TRtSvgShape);
  sh.First := AFirstCmd;
  sh.Count := Img.FCmdCount - AFirstCmd;
  sh.PtFirst := AFirstPt;
  sh.M := AM;
  p := AStyle.Fill;
  if p.Kind = pkCurrent then begin p.Lum := AStyle.ColorLum; p.Alpha := AStyle.ColorAlpha; end;
  if p.Kind <> pkNone then
  begin
    sh.FillLum := p.Lum;
    sh.FillAlpha := p.Alpha * AStyle.FillOpacity * AStyle.Opacity;
  end;
  p := AStyle.Stroke;
  if p.Kind = pkCurrent then begin p.Lum := AStyle.ColorLum; p.Alpha := AStyle.ColorAlpha; end;
  if (p.Kind <> pkNone) and (AStyle.StrokeWidth > 0) then
  begin
    sh.StrokeLum := p.Lum;
    sh.StrokeAlpha := p.Alpha * AStyle.StrokeOpacity * AStyle.Opacity;
  end;
  sh.StrokeWidth := AStyle.StrokeWidth;
  sh.MiterLimit := AStyle.MiterLimit;
  sh.DashOffset := AStyle.DashOffset;
  sh.Dash := Copy(AStyle.Dash);
  sh.Cap := AStyle.Cap;
  sh.Join := AStyle.Join;
  sh.EvenOdd := AStyle.EvenOdd;
  if (sh.FillAlpha <= 0) and (sh.StrokeAlpha <= 0) then
  begin
    Img.FCmdCount := AFirstCmd;
    Img.FPtCount := AFirstPt;
    Exit;
  end;
  if Img.FShapeCount >= RTSVG_MAX_SHAPES then TooBig('shapes');
  if Img.FShapeCount >= Length(Img.FShapes) then
    SetLength(Img.FShapes, Max(256, Length(Img.FShapes) * 2));
  Img.FShapes[Img.FShapeCount] := sh;
  Inc(Img.FShapeCount);
end;

{ White space as XML collapses it in a text. }
function Collapse(const S: string): string;
var
  i: Integer;
  sp: Boolean;
begin
  Result := '';
  sp := False;
  for i := 1 to Length(S) do
    if IsSpace(S[i]) then sp := True
    else
    begin
      if sp and (Result <> '') then Result := Result + ' ';
      sp := False;
      Result := Result + S[i];
    end;
  if sp and (Result <> '') then Result := Result + ' ';
end;

procedure TBuilder.TextElement(ANode: Integer; const AStyle: TStyle; const AM: TRtSvgMatrix);
var
  x, y: Double;
  buf: string;
  run: TStyle;

  procedure Flush;
  var
    t: TRtSvgText;
    p: TPaint;
  begin
    buf := Trim(buf);
    if (buf <> '') and not run.Hidden then
    begin
      t := Default(TRtSvgText);
      t.X := x;
      t.Y := y;
      t.M := AM;
      t.Size := run.FontSize;
      t.Bold := run.Bold;
      t.Italic := run.Italic;
      t.Mono := run.Mono;
      t.Anchor := run.Anchor;
      t.Baseline := run.Baseline;
      t.Text := buf;
      t.Order := Img.FShapeCount;
      p := run.Fill;
      if p.Kind = pkCurrent then begin p.Lum := run.ColorLum; p.Alpha := run.ColorAlpha; end;
      if p.Kind = pkNone then
      begin
        p := run.Stroke;
        if p.Kind = pkCurrent then begin p.Lum := run.ColorLum; p.Alpha := run.ColorAlpha; end;
      end;
      if p.Kind <> pkNone then
      begin
        t.Lum := p.Lum;
        t.Alpha := p.Alpha * run.FillOpacity * run.Opacity;
        if Img.FTextCount >= RTSVG_MAX_SHAPES then TooBig('texts');
        if Img.FTextCount >= Length(Img.FTexts) then
          SetLength(Img.FTexts, Max(64, Length(Img.FTexts) * 2));
        Img.FTexts[Img.FTextCount] := t;
        Inc(Img.FTextCount);
      end;
    end;
    buf := '';
  end;

  procedure Visit(ANodeIdx: Integer; const AParent: TStyle);
  var
    ch: Integer;
    st: TStyle;
    v: string;
    moved: Boolean;
  begin
    ch := Doc.Nodes[ANodeIdx].FirstChild;
    while ch >= 0 do
    begin
      if Doc.Nodes[ch].Name = '' then
      begin
        if Length(buf) < 100000 then buf := buf + Collapse(' ' + Doc.Nodes[ch].Text + ' ');
      end
      else if ((Doc.Nodes[ch].Name = 'tspan') or (Doc.Nodes[ch].Name = 'textPath') or
        (Doc.Nodes[ch].Name = 'a')) and not IsHidden(Doc.Nodes[ch]) then
      begin
        st := AParent;
        ApplyStyle(st, Doc.Nodes[ch]);
        // A tspan placed on its own starts a run of its own.
        moved := False;
        if Attr(Doc.Nodes[ch], 'x', v) or Attr(Doc.Nodes[ch], 'y', v) or Attr(Doc.Nodes[ch], 'dy', v) then
        begin
          Flush;
          if Attr(Doc.Nodes[ch], 'x', v) then x := Length_(v, x, st.FontSize, ViewW);
          if Attr(Doc.Nodes[ch], 'y', v) then y := Length_(v, y, st.FontSize, ViewH);
          if Attr(Doc.Nodes[ch], 'dy', v) then y := y + Length_(v, 0, st.FontSize, ViewH);
          if Attr(Doc.Nodes[ch], 'dx', v) then x := x + Length_(v, 0, st.FontSize, ViewW);
          run := st;
          moved := True;
        end
        else if Trim(buf) = '' then
          run := st;
        Visit(ch, st);
        if moved then Flush;
      end;
      ch := Doc.Nodes[ch].Next;
    end;
  end;

var
  v: string;
begin
  // Only the first value of a list of positions counts.
  v := AttrOr(Doc.Nodes[ANode], 'x', '0');
  x := Length_(v, 0, AStyle.FontSize, ViewW);
  v := AttrOr(Doc.Nodes[ANode], 'y', '0');
  y := Length_(v, 0, AStyle.FontSize, ViewH);
  if Attr(Doc.Nodes[ANode], 'dx', v) then x := x + Length_(v, 0, AStyle.FontSize, ViewW);
  if Attr(Doc.Nodes[ANode], 'dy', v) then y := y + Length_(v, 0, AStyle.FontSize, ViewH);
  buf := '';
  run := AStyle;
  Visit(ANode, AStyle);
  Flush;
end;

const
  SKIPPED: array[0..15] of string = ('defs', 'symbol', 'clipPath', 'mask', 'pattern', 'marker',
    'linearGradient', 'radialGradient', 'style', 'script', 'metadata', 'title', 'desc',
    'foreignObject', 'image', 'filter');

procedure TBuilder.Element(ANode: Integer; const AStyle: TStyle; const AM: TRtSvgMatrix);
var
  name, v: string;
  c0, p0, ref, ch: Integer;
  x, y, w, h, rx, ry: Double;
  m: TRtSvgMatrix;
  hasRx, hasRy: Boolean;
begin
  name := Doc.Nodes[ANode].Name;
  c0 := Img.FCmdCount;
  p0 := Img.FPtCount;
  if name = 'path' then
  begin
    if Attr(Doc.Nodes[ANode], 'd', v) then PathDataFull(Self, v);
    FinishShape(c0, p0, AStyle, AM);
  end
  else if name = 'rect' then
  begin
    x := Length_(AttrOr(Doc.Nodes[ANode], 'x', '0'), 0, AStyle.FontSize, ViewW);
    y := Length_(AttrOr(Doc.Nodes[ANode], 'y', '0'), 0, AStyle.FontSize, ViewH);
    w := Length_(AttrOr(Doc.Nodes[ANode], 'width', '0'), 0, AStyle.FontSize, ViewW);
    h := Length_(AttrOr(Doc.Nodes[ANode], 'height', '0'), 0, AStyle.FontSize, ViewH);
    if (w <= 0) or (h <= 0) then Exit;
    hasRx := Attr(Doc.Nodes[ANode], 'rx', v);
    rx := Length_(v, 0, AStyle.FontSize, ViewW);
    hasRy := Attr(Doc.Nodes[ANode], 'ry', v);
    ry := Length_(v, 0, AStyle.FontSize, ViewH);
    if hasRx and not hasRy then ry := rx;
    if hasRy and not hasRx then rx := ry;
    RoundRect(x, y, w, h, Min(Max(rx, 0), w / 2), Min(Max(ry, 0), h / 2));
    FinishShape(c0, p0, AStyle, AM);
  end
  else if (name = 'circle') or (name = 'ellipse') then
  begin
    x := Length_(AttrOr(Doc.Nodes[ANode], 'cx', '0'), 0, AStyle.FontSize, ViewW);
    y := Length_(AttrOr(Doc.Nodes[ANode], 'cy', '0'), 0, AStyle.FontSize, ViewH);
    if name = 'circle' then
    begin
      rx := Length_(AttrOr(Doc.Nodes[ANode], 'r', '0'), 0, AStyle.FontSize,
        Sqrt((Sqr(ViewW) + Sqr(ViewH)) / 2));
      ry := rx;
    end
    else
    begin
      rx := Length_(AttrOr(Doc.Nodes[ANode], 'rx', '0'), 0, AStyle.FontSize, ViewW);
      ry := Length_(AttrOr(Doc.Nodes[ANode], 'ry', '0'), 0, AStyle.FontSize, ViewH);
    end;
    if (rx <= 0) or (ry <= 0) then Exit;
    Ellipse(x, y, rx, ry);
    FinishShape(c0, p0, AStyle, AM);
  end
  else if name = 'line' then
  begin
    AddCmd(CMD_MOVE, [Length_(AttrOr(Doc.Nodes[ANode], 'x1', '0'), 0, AStyle.FontSize, ViewW),
      Length_(AttrOr(Doc.Nodes[ANode], 'y1', '0'), 0, AStyle.FontSize, ViewH)]);
    AddCmd(CMD_LINE, [Length_(AttrOr(Doc.Nodes[ANode], 'x2', '0'), 0, AStyle.FontSize, ViewW),
      Length_(AttrOr(Doc.Nodes[ANode], 'y2', '0'), 0, AStyle.FontSize, ViewH)]);
    FinishShape(c0, p0, AStyle, AM);
  end
  else if (name = 'polyline') or (name = 'polygon') then
  begin
    Points(AttrOr(Doc.Nodes[ANode], 'points', ''), name = 'polygon');
    FinishShape(c0, p0, AStyle, AM);
  end
  else if name = 'text' then
    TextElement(ANode, AStyle, AM)
  else if name = 'use' then
  begin
    if not (Attr(Doc.Nodes[ANode], 'href', v)) or (Copy(v, 1, 1) <> '#') then Exit;   // never outside
    ref := FindId(Copy(v, 2, MaxInt));
    if (ref < 0) or (UseDepth >= RTSVG_MAX_USE_DEPTH) then Exit;
    x := Length_(AttrOr(Doc.Nodes[ANode], 'x', '0'), 0, AStyle.FontSize, ViewW);
    y := Length_(AttrOr(Doc.Nodes[ANode], 'y', '0'), 0, AStyle.FontSize, ViewH);
    m := RtSvgMul(AM, RtSvgTranslate(x, y));
    Inc(UseDepth);
    try
      if Doc.Nodes[ref].Name = 'symbol' then
      begin
        ch := Doc.Nodes[ref].FirstChild;
        while ch >= 0 do
        begin
          Walk(ch, AStyle, m);
          ch := Doc.Nodes[ch].Next;
        end;
      end
      else
        Walk(ref, AStyle, m);
    finally
      Dec(UseDepth);
    end;
  end
  else if (name = 'g') or (name = 'a') or (name = 'switch') or (name = 'svg') then
  begin
    m := AM;
    if (name = 'svg') and (Doc.Nodes[ANode].Parent >= 0) then
    begin
      x := Length_(AttrOr(Doc.Nodes[ANode], 'x', '0'), 0, AStyle.FontSize, ViewW);
      y := Length_(AttrOr(Doc.Nodes[ANode], 'y', '0'), 0, AStyle.FontSize, ViewH);
      m := RtSvgMul(AM, RtSvgTranslate(x, y));
    end;
    ch := Doc.Nodes[ANode].FirstChild;
    while ch >= 0 do
    begin
      Walk(ch, AStyle, m);
      ch := Doc.Nodes[ch].Next;
    end;
  end;
end;

procedure TBuilder.Walk(ANode: Integer; AStyle: TStyle; const AM: TRtSvgMatrix);
var
  name, v: string;
  i: Integer;
  m, t: TRtSvgMatrix;
begin
  name := Doc.Nodes[ANode].Name;
  if name = '' then Exit;
  // (Codex review 90) Every element walked counts, drawing or not: uses of
  // uses of empty groups cannot multiply without end.
  Inc(Visits);
  if Visits > RTSVG_MAX_VISITS then TooBig('elements drawn');
  for i := Low(SKIPPED) to High(SKIPPED) do
    if name = SKIPPED[i] then Exit;
  if Pos(':', name) > 0 then Exit;    // an editor's own elements
  if IsHidden(Doc.Nodes[ANode]) then Exit;
  m := AM;
  if Attr(Doc.Nodes[ANode], 'transform', v) and ParseTransform(v, t) then
    m := RtSvgMul(AM, t);
  ApplyStyle(AStyle, Doc.Nodes[ANode]);
  Element(ANode, AStyle, m);
end;

{ ---------------------------------------------------------------------------
  TRtSvgImage
  --------------------------------------------------------------------------- }

procedure TRtSvgImage.Clear;
begin
  FWidth := 0;
  FHeight := 0;
  FCmds := nil;
  FCmdCount := 0;
  FPts := nil;
  FPtCount := 0;
  FShapes := nil;
  FShapeCount := 0;
  FTexts := nil;
  FTextCount := 0;
  FTextHidden := nil;
end;

function TRtSvgImage.GetText(AIndex: Integer): TRtSvgText;
begin
  Result := FTexts[AIndex];
end;

function TRtSvgImage.GetTextHidden(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FTextHidden)) and FTextHidden[AIndex];
end;

procedure TRtSvgImage.SetTextHidden(AIndex: Integer; AValue: Boolean);
begin
  if (AIndex < 0) or (AIndex >= FTextCount) then Exit;
  if Length(FTextHidden) <> FTextCount then SetLength(FTextHidden, FTextCount);
  FTextHidden[AIndex] := AValue;
end;

procedure TRtSvgImage.ShowAllTexts;
begin
  FTextHidden := nil;
end;

procedure TRtSvgImage.LoadFromString(const AData: RawByteString);
var
  b: TBuilder;
  s, v: string;
  root, ch, p, i: Integer;
  vb: array[0..3] of Double;
  hasVb: Boolean;
  w, h, sx, sy, sc: Double;
  m: TRtSvgMatrix;
  par: string;
  slice: Boolean;
  st: TStyle;
begin
  Clear;
  if Length(AData) > RTSVG_MAX_BYTES then TooBig('size');
  if not RtSvgSniff(AData) then raise ERtSvg.Create(rsSvgNotSvg);
  s := ToUtf8(AData);
  b := TBuilder.Create;
  try
    b.Img := Self;
    ParseXml(s, b.Doc);
    root := 0;
    if b.Doc.Nodes[root].Name <> 'svg' then raise ERtSvg.Create(rsSvgNotSvg);
    b.IndexIds;
    // The viewBox, and the size: width / height, else the viewBox's.
    hasVb := False;
    if Attr(b.Doc.Nodes[root], 'viewBox', v) then
    begin
      p := 1;
      hasVb := True;
      for i := 0 to 3 do
      begin
        SkipSep(v, p);
        if not ReadNumber(v, p, vb[i]) then hasVb := False;
      end;
      hasVb := hasVb and (vb[2] > 0) and (vb[3] > 0);
    end;
    w := 0;
    h := 0;
    if Attr(b.Doc.Nodes[root], 'width', v) and (Pos('%', v) = 0) then w := Length_(v, 0, 16, 0);
    if Attr(b.Doc.Nodes[root], 'height', v) and (Pos('%', v) = 0) then h := Length_(v, 0, 16, 0);
    if hasVb then
    begin
      if (w <= 0) and (h <= 0) then begin w := vb[2]; h := vb[3]; end
      else if w <= 0 then w := h * vb[2] / vb[3]
      else if h <= 0 then h := w * vb[3] / vb[2];
    end
    else
    begin
      if w <= 0 then w := 300;    // the defaults of a replaced element
      if h <= 0 then h := 150;
      vb[0] := 0; vb[1] := 0; vb[2] := w; vb[3] := h;
    end;
    if (w < 1e-6) or (h < 1e-6) or (w > RTSVG_MAX_SIDE) or (h > RTSVG_MAX_SIDE) then
      TooBig('width / height');
    FWidth := w;
    FHeight := h;
    b.ViewW := vb[2];
    b.ViewH := vb[3];
    // preserveAspectRatio: the viewBox fitted (meet, by default) or
    // filling (slice), aligned; 'none' stretches it.
    par := LowerCase(Trim(AttrOr(b.Doc.Nodes[root], 'preserveAspectRatio', 'xMidYMid meet')));
    sx := w / vb[2];
    sy := h / vb[3];
    if Pos('none', par) = 1 then
      m := RtSvgMul(RtSvgScale(sx, sy), RtSvgTranslate(-vb[0], -vb[1]))
    else
    begin
      slice := Pos('slice', par) > 0;
      if slice then sc := Max(sx, sy) else sc := Min(sx, sy);
      m := RtSvgMul(RtSvgScale(sc, sc), RtSvgTranslate(-vb[0], -vb[1]));
      if Pos('xmid', par) > 0 then m.E := m.E + (w - vb[2] * sc) / 2
      else if Pos('xmax', par) > 0 then m.E := m.E + (w - vb[2] * sc);
      if Pos('ymid', par) > 0 then m.F := m.F + (h - vb[3] * sc) / 2
      else if Pos('ymax', par) > 0 then m.F := m.F + (h - vb[3] * sc);
    end;
    st := DefaultStyle;
    b.ApplyStyle(st, b.Doc.Nodes[root]);
    ch := b.Doc.Nodes[root].FirstChild;
    while ch >= 0 do
    begin
      b.Walk(ch, st, m);
      ch := b.Doc.Nodes[ch].Next;
    end;
  finally
    b.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Rasterizer: the signed-area accumulation of font-rs (Raph Levien), written
  again here: each edge adds, along the rows it crosses, the exact area it
  covers; a running sum along a row gives the coverage.
  --------------------------------------------------------------------------- }

type
  TFlat = record
    X, Y: array of Double;
    Count: Integer;
    Starts: array of Integer;
    Closed: array of Boolean;
    Subs: Integer;
    MinX, MinY, MaxX, MaxY: Double;
    Bad: Boolean;                  // a point not finite: the shape is left out
  end;

  TRas = class
    W, H, Stride: Integer;
    Acc: array of Single;
    MinX, MaxX, MinY, MaxY: Integer;
    Pts: array of Double;          // scratch polygon (x, y, x, y...)
    constructor Create(AW, AH: Integer);
    procedure DrawLine(X0, Y0, X1, Y1: Double; ASign: Single);
    procedure Seg(X0, Y0, X1, Y1: Double; ASign: Single);
    { The polygon held in Pts (ACount points), added so that its inside
      counts positively whatever its direction (a stroke is a union). }
    procedure PolyPositive(ACount: Integer);
    procedure Quad(AX, AY, BX, BY, CX, CY, DX, DY: Double);
    procedure Tri(AX, AY, BX, BY, CX, CY: Double);
    procedure Disc(CX, CY, R: Double);
    procedure Composite(var R: TRtSvgRaster; ALum, AAlpha: Single; AEvenOdd: Boolean);
    procedure StrokePolyline(const X, Y: array of Double; AFrom, ACount: Integer; AClosed: Boolean;
      HW: Double; ACap: TRtSvgCap; AJoin: TRtSvgJoin; AMiter: Double);
  end;

constructor TRas.Create(AW, AH: Integer);
begin
  inherited Create;
  W := AW;
  H := AH;
  Stride := AW + 2;
  SetLength(Acc, Int64(Stride) * AH);
  MinX := MaxInt;
  MaxX := -1;
  MinY := MaxInt;
  MaxY := -1;
end;

procedure TRas.DrawLine(X0, Y0, X1, Y1: Double; ASign: Single);
var
  dir, dxdy, x, xnext, dy, d, xa, xb, x0f, x1f, s, a0, a1, a2, am, xmf, t: Double;
  y, ylo, yhi, base, x0i, x1i, xi: Integer;
begin
  if Y0 = Y1 then Exit;
  if Y0 < Y1 then dir := ASign
  else
  begin
    dir := -ASign;
    t := X0; X0 := X1; X1 := t;
    t := Y0; Y0 := Y1; Y1 := t;
  end;
  dxdy := (X1 - X0) / (Y1 - Y0);
  x := X0;
  ylo := Max(0, Floor(Y0));
  yhi := Min(H - 1, Ceil(Y1) - 1);
  if ylo < MinY then MinY := ylo;
  if yhi > MaxY then MaxY := yhi;
  for y := ylo to yhi do
  begin
    base := y * Stride;
    dy := Min(y + 1, Y1) - Max(y, Y0);
    xnext := x + dxdy * dy;
    d := dy * dir;
    if x < xnext then begin xa := x; xb := xnext; end else begin xa := xnext; xb := x; end;
    xa := EnsureRange(xa, 0, W);
    xb := EnsureRange(xb, 0, W);
    x0i := Floor(xa);
    x1i := Ceil(xb);
    if x0i < MinX then MinX := x0i;
    if x1i <= x0i + 1 then
    begin
      xmf := 0.5 * (xa + xb) - x0i;
      Acc[base + x0i] := Acc[base + x0i] + d - d * xmf;
      Acc[base + x0i + 1] := Acc[base + x0i + 1] + d * xmf;
      if x0i + 1 > MaxX then MaxX := x0i + 1;
    end
    else
    begin
      s := 1 / (xb - xa);
      x0f := xa - x0i;
      a0 := 0.5 * s * Sqr(1 - x0f);
      x1f := xb - x1i + 1;
      am := 0.5 * s * Sqr(x1f);
      Acc[base + x0i] := Acc[base + x0i] + d * a0;
      if x1i = x0i + 2 then
        Acc[base + x0i + 1] := Acc[base + x0i + 1] + d * (1 - a0 - am)
      else
      begin
        a1 := s * (1.5 - x0f);
        Acc[base + x0i + 1] := Acc[base + x0i + 1] + d * (a1 - a0);
        for xi := x0i + 2 to x1i - 2 do
          Acc[base + xi] := Acc[base + xi] + d * s;
        a2 := a1 + (x1i - x0i - 3) * s;
        Acc[base + x1i - 1] := Acc[base + x1i - 1] + d * (1 - a2 - am);
      end;
      Acc[base + x1i] := Acc[base + x1i] + d * am;
      if x1i > MaxX then MaxX := x1i;
    end;
    x := xnext;
  end;
end;

{ An edge clipped to the raster's rows; the parts left or right of it are
  pressed against its sides (what lies left still counts for the pixels to
  its right). }
procedure TRas.Seg(X0, Y0, X1, Y1: Double; ASign: Single);
var
  dy, dx, t0, t1, ta, tb, tx: Double;
  ts: array[0..3] of Double;
  n, i, j: Integer;
  xa, ya, xb, yb, xm: Double;
begin
  dy := Y1 - Y0;
  if dy = 0 then Exit;
  if (Y0 <= 0) and (Y1 <= 0) then Exit;
  if (Y0 >= H) and (Y1 >= H) then Exit;
  ta := (0 - Y0) / dy;
  tb := (H - Y0) / dy;
  if dy > 0 then begin t0 := Max(0, ta); t1 := Min(1, tb); end
  else begin t0 := Max(0, tb); t1 := Min(1, ta); end;
  if t0 >= t1 then Exit;
  dx := X1 - X0;
  n := 0;
  ts[n] := t0; Inc(n);
  if dx <> 0 then
  begin
    tx := (0 - X0) / dx;
    if (tx > t0) and (tx < t1) then begin ts[n] := tx; Inc(n); end;
    tx := (W - X0) / dx;
    if (tx > t0) and (tx < t1) then begin ts[n] := tx; Inc(n); end;
  end;
  ts[n] := t1; Inc(n);
  for i := 1 to n - 1 do
    for j := i downto 1 do
      if ts[j] < ts[j - 1] then begin tx := ts[j]; ts[j] := ts[j - 1]; ts[j - 1] := tx; end;
  for i := 0 to n - 2 do
  begin
    xa := X0 + dx * ts[i];
    ya := Y0 + dy * ts[i];
    xb := X0 + dx * ts[i + 1];
    yb := Y0 + dy * ts[i + 1];
    xm := (xa + xb) / 2;
    if xm < 0 then begin xa := 0; xb := 0; end
    else if xm > W then begin xa := W; xb := W; end;
    DrawLine(xa, ya, xb, yb, ASign);
  end;
end;

procedure TRas.PolyPositive(ACount: Integer);
var
  i, j: Integer;
  area: Double;
  sg: Single;
begin
  if ACount < 3 then Exit;
  area := 0;
  for i := 0 to ACount - 1 do
  begin
    j := (i + 1) mod ACount;
    area := area + Pts[2 * i] * Pts[2 * j + 1] - Pts[2 * j] * Pts[2 * i + 1];
  end;
  if Abs(area) < 1e-12 then Exit;
  if area > 0 then sg := 1 else sg := -1;
  for i := 0 to ACount - 1 do
  begin
    j := (i + 1) mod ACount;
    Seg(Pts[2 * i], Pts[2 * i + 1], Pts[2 * j], Pts[2 * j + 1], sg);
  end;
end;

procedure TRas.Quad(AX, AY, BX, BY, CX, CY, DX, DY: Double);
begin
  if Length(Pts) < 8 then SetLength(Pts, 8);
  Pts[0] := AX; Pts[1] := AY; Pts[2] := BX; Pts[3] := BY;
  Pts[4] := CX; Pts[5] := CY; Pts[6] := DX; Pts[7] := DY;
  PolyPositive(4);
end;

procedure TRas.Tri(AX, AY, BX, BY, CX, CY: Double);
begin
  if Length(Pts) < 6 then SetLength(Pts, 6);
  Pts[0] := AX; Pts[1] := AY; Pts[2] := BX; Pts[3] := BY; Pts[4] := CX; Pts[5] := CY;
  PolyPositive(3);
end;

procedure TRas.Disc(CX, CY, R: Double);
var
  n, i: Integer;
  a: Double;
begin
  if not (R > 0) then Exit;
  // (bounded before any conversion: Codex review 90)
  if R > 128 then n := 256 else n := Max(8, Ceil(R * 2));
  if Length(Pts) < 2 * n then SetLength(Pts, 2 * n);
  for i := 0 to n - 1 do
  begin
    a := 2 * Pi * i / n;
    Pts[2 * i] := CX + R * Cos(a);
    Pts[2 * i + 1] := CY + R * Sin(a);
  end;
  PolyPositive(n);
end;

procedure TRas.Composite(var R: TRtSvgRaster; ALum, AAlpha: Single; AEvenOdd: Boolean);
var
  x, y, base, i, hiX: Integer;
  sum, c, a: Single;
begin
  if (MaxY >= MinY) and (MaxX >= MinX) then
  begin
    hiX := Min(MaxX, Stride - 1);
    for y := MinY to MaxY do
    begin
      base := y * Stride;
      sum := 0;
      for x := MinX to hiX do
      begin
        sum := sum + Acc[base + x];
        Acc[base + x] := 0;
        if x >= W then Continue;
        c := Abs(sum);
        if AEvenOdd then
        begin
          c := c - 2 * Floor(c / 2);
          if c > 1 then c := 2 - c;
        end
        else if c > 1 then c := 1;
        if c < 0.002 then Continue;
        a := c * AAlpha;
        i := y * W + x;
        R.Lum[i] := ALum * a + R.Lum[i] * (1 - a);
        R.Alpha[i] := a + R.Alpha[i] * (1 - a);
      end;
    end;
  end;
  MinX := MaxInt;
  MaxX := -1;
  MinY := MaxInt;
  MaxY := -1;
end;

{ A stroke as polygons whose union is its outline: a quad per segment, a
  wedge or a disc per join, the caps. }
procedure TRas.StrokePolyline(const X, Y: array of Double; AFrom, ACount: Integer; AClosed: Boolean;
  HW: Double; ACap: TRtSvgCap; AJoin: TRtSvgJoin; AMiter: Double);
var
  px, py: array of Double;
  n, i, i0, i1, i2, segs: Integer;
  dx, dy, len, d1x, d1y, d2x, d2y, n1x, n1y, n2x, n2y, cr, dt, sx, ratio, mx, my, ml: Double;
  ax, ay, bx, by, ex0, ey0, ex1, ey1: Double;
begin
  // The points without repeats (a closed polyline loses its last when it
  // is its first).
  SetLength(px, ACount);
  SetLength(py, ACount);
  n := 0;
  for i := AFrom to AFrom + ACount - 1 do
    if (n = 0) or (Abs(X[i] - px[n - 1]) > 1e-7) or (Abs(Y[i] - py[n - 1]) > 1e-7) then
    begin
      px[n] := X[i];
      py[n] := Y[i];
      Inc(n);
    end;
  if AClosed and (n > 1) and (Abs(px[n - 1] - px[0]) <= 1e-7) and (Abs(py[n - 1] - py[0]) <= 1e-7) then
    Dec(n);
  if n = 0 then Exit;
  if n = 1 then
  begin
    // A lone point: drawn by a round or square cap only.
    if ACap = rcRound then Disc(px[0], py[0], HW)
    else if ACap = rcSquare then
      Quad(px[0] - HW, py[0] - HW, px[0] + HW, py[0] - HW, px[0] + HW, py[0] + HW, px[0] - HW, py[0] + HW);
    Exit;
  end;
  if AClosed and (n >= 3) then segs := n
  else
  begin
    segs := n - 1;
    AClosed := False;
  end;
  for i := 0 to segs - 1 do
  begin
    i1 := (i + 1) mod n;
    dx := px[i1] - px[i];
    dy := py[i1] - py[i];
    len := Sqrt(dx * dx + dy * dy);
    dx := dx / len;
    dy := dy / len;
    n1x := -dy * HW;
    n1y := dx * HW;
    ex0 := px[i]; ey0 := py[i]; ex1 := px[i1]; ey1 := py[i1];
    if not AClosed and (ACap = rcSquare) then
    begin
      if i = 0 then begin ex0 := ex0 - dx * HW; ey0 := ey0 - dy * HW; end;
      if i = segs - 1 then begin ex1 := ex1 + dx * HW; ey1 := ey1 + dy * HW; end;
    end;
    Quad(ex0 + n1x, ey0 + n1y, ex1 + n1x, ey1 + n1y, ex1 - n1x, ey1 - n1y, ex0 - n1x, ey0 - n1y);
  end;
  // Joins: every inner vertex, and every vertex of a closed polyline.
  for i := 0 to n - 1 do
  begin
    if not AClosed and ((i = 0) or (i = n - 1)) then Continue;
    i0 := (i - 1 + n) mod n;
    i2 := (i + 1) mod n;
    d1x := px[i] - px[i0]; d1y := py[i] - py[i0];
    len := Sqrt(d1x * d1x + d1y * d1y); d1x := d1x / len; d1y := d1y / len;
    d2x := px[i2] - px[i]; d2y := py[i2] - py[i];
    len := Sqrt(d2x * d2x + d2y * d2y); d2x := d2x / len; d2y := d2y / len;
    cr := d1x * d2y - d1y * d2x;
    dt := d1x * d2x + d1y * d2y;
    if (Abs(cr) < 1e-9) and (dt > 0) then Continue;
    if AJoin = rjRound then
    begin
      Disc(px[i], py[i], HW);
      Continue;
    end;
    // The outer side, away from the turn.
    if cr > 0 then sx := -1 else sx := 1;
    n1x := -d1y * HW * sx; n1y := d1x * HW * sx;
    n2x := -d2y * HW * sx; n2y := d2x * HW * sx;
    ax := px[i] + n1x; ay := py[i] + n1y;
    bx := px[i] + n2x; by := py[i] + n2y;
    if AJoin = rjMiter then
    begin
      ratio := Sqrt(Max(0, (1 + dt) / 2));
      if (ratio > 1e-9) and (1 / ratio <= AMiter) then
      begin
        mx := n1x + n2x;
        my := n1y + n2y;
        ml := Sqrt(mx * mx + my * my);
        if ml > 1e-12 then
        begin
          mx := px[i] + mx / ml * HW / ratio;
          my := py[i] + my / ml * HW / ratio;
          Quad(px[i], py[i], ax, ay, mx, my, bx, by);
          Continue;
        end;
      end;
    end;
    Tri(px[i], py[i], ax, ay, bx, by);
  end;
  if not AClosed and (ACap = rcRound) then
  begin
    Disc(px[0], py[0], HW);
    Disc(px[n - 1], py[n - 1], HW);
  end;
end;

{ The shape's path in device space: lines, and cubics cut into segments
  enough for an error under FLAT_TOLERANCE pixel. A cubic wholly off the
  raster (beyond AMargin) is its chord: left of the raster both count the
  same, elsewhere neither counts. Bounded (RTSVG_MAX_FLAT points: then
  chords only); F.Bad when a point is not a finite, sane number. }
procedure Flatten(AImg: TRtSvgImage; const AShape: TRtSvgShape; const AT: TRtSvgMatrix;
  AW, AH, AMargin: Double; var F: TFlat);

  procedure AddPt(AX, AY: Double);
  begin
    if IsNan(AX) or IsNan(AY) or (Abs(AX) > 1e15) or (Abs(AY) > 1e15) then
    begin
      F.Bad := True;
      Exit;
    end;
    if F.Count >= Length(F.X) then
    begin
      SetLength(F.X, Max(256, 2 * Length(F.X)));
      SetLength(F.Y, Length(F.X));
    end;
    F.X[F.Count] := AX;
    F.Y[F.Count] := AY;
    Inc(F.Count);
    if AX < F.MinX then F.MinX := AX;
    if AX > F.MaxX then F.MaxX := AX;
    if AY < F.MinY then F.MinY := AY;
    if AY > F.MaxY then F.MaxY := AY;
  end;

  procedure NewSub;
  begin
    if F.Subs >= Length(F.Starts) then
    begin
      SetLength(F.Starts, Max(16, 2 * Length(F.Starts)));
      SetLength(F.Closed, Length(F.Starts));
    end;
    F.Starts[F.Subs] := F.Count;
    F.Closed[F.Subs] := False;
    Inc(F.Subs);
  end;

var
  c, pt, k, n: Integer;
  x, y, x1, y1, x2, y2, x3, y3, x0, y0, l, t, mt, v: Double;
begin
  F.Count := 0;
  F.Subs := 0;
  F.Bad := False;
  F.MinX := MaxDouble; F.MinY := MaxDouble; F.MaxX := -MaxDouble; F.MaxY := -MaxDouble;
  pt := AShape.PtFirst;
  x0 := 0; y0 := 0;
  for c := AShape.First to AShape.First + AShape.Count - 1 do
  begin
    if F.Bad then Exit;
    case AImg.FCmds[c] of
      CMD_MOVE:
        begin
          RtSvgApply(AT, AImg.FPts[pt], AImg.FPts[pt + 1], x, y);
          Inc(pt, 2);
          NewSub;
          AddPt(x, y);
          x0 := x; y0 := y;
        end;
      CMD_LINE:
        begin
          RtSvgApply(AT, AImg.FPts[pt], AImg.FPts[pt + 1], x, y);
          Inc(pt, 2);
          if F.Subs = 0 then begin NewSub; AddPt(x0, y0); end;
          AddPt(x, y);
          x0 := x; y0 := y;
        end;
      CMD_CUBIC:
        begin
          RtSvgApply(AT, AImg.FPts[pt], AImg.FPts[pt + 1], x1, y1);
          RtSvgApply(AT, AImg.FPts[pt + 2], AImg.FPts[pt + 3], x2, y2);
          RtSvgApply(AT, AImg.FPts[pt + 4], AImg.FPts[pt + 5], x3, y3);
          Inc(pt, 6);
          if F.Subs = 0 then begin NewSub; AddPt(x0, y0); end;
          // Segments from the curve's second differences, bounded before
          // any conversion (Codex review 90); one when off the raster or
          // past the budget.
          l := Max(Sqrt(Sqr(x0 - 2 * x1 + x2) + Sqr(y0 - 2 * y1 + y2)),
            Sqrt(Sqr(x1 - 2 * x2 + x3) + Sqr(y1 - 2 * y2 + y3)));
          v := Sqrt(l * 0.75 / FLAT_TOLERANCE);
          if IsNan(v) or (v > 500) then n := 500 else n := Max(1, Ceil(v));
          if (Max(Max(x0, x1), Max(x2, x3)) < -AMargin) or (Min(Min(x0, x1), Min(x2, x3)) > AW + AMargin) or
            (Max(Max(y0, y1), Max(y2, y3)) < -AMargin) or (Min(Min(y0, y1), Min(y2, y3)) > AH + AMargin) or
            (F.Count + n > RTSVG_MAX_FLAT) then
            n := 1;
          for k := 1 to n do
          begin
            t := k / n;
            mt := 1 - t;
            AddPt(mt * mt * mt * x0 + 3 * mt * mt * t * x1 + 3 * mt * t * t * x2 + t * t * t * x3,
              mt * mt * mt * y0 + 3 * mt * mt * t * y1 + 3 * mt * t * t * y2 + t * t * t * y3);
          end;
          x0 := x3; y0 := y3;
        end;
      CMD_CLOSE:
        if F.Subs > 0 then
        begin
          F.Closed[F.Subs - 1] := True;
          x0 := F.X[F.Starts[F.Subs - 1]];
          y0 := F.Y[F.Starts[F.Subs - 1]];
        end;
    end;
  end;
end;

{ X modulo APeriod (> 0), in [0, APeriod), exact: the multiples of the
  period by powers of two taken off one by one, each subtraction exact
  (q <= X < 2q). (Codex reviews 91, 92: Floor returns 32 bits, and a
  quotient then a product loses the remainder of a huge X.) }
function FMod(X, APeriod: Double): Double;
var
  neg: Boolean;
  q: Double;
begin
  if IsNan(X) or IsInfinite(X) or not (APeriod > 0) then Exit(0);
  neg := X < 0;
  X := Abs(X);
  if X >= APeriod then
  begin
    q := APeriod;
    while q * 2 <= X do q := q * 2;
    while q >= APeriod do
    begin
      if X >= q then X := X - q;
      q := q / 2;
    end;
  end;
  if neg and (X > 0) then X := APeriod - X;
  if (X >= APeriod) or (X < 0) then X := 0;
  Result := X;
end;

{ The pieces a dash pattern draws (device lengths), each stroked open.
  (Codex review 90) Only what lies on the raster (with AMargin) is cut into
  dashes: elsewhere the pattern's phase is advanced by arithmetic. }
procedure DashedStroke(ARas: TRas; const F: TFlat; AFrom, ACount: Integer; AClosed: Boolean;
  const ADash: array of Double; AOffset, HW, AMargin: Double; ACap: TRtSvgCap; AJoin: TRtSvgJoin;
  AMiter: Double);
var
  xs, ys, bufX, bufY: array of Double;
  n, i, k, di, bn: Integer;
  total, pos, remain, segLen, t, ax, ay, bx, by, la, lb, ux, uy, sx, sy, vis: Double;
  drawing: Boolean;
  guard: Integer;

  procedure Put(AX, AY: Double);
  begin
    if bn >= Length(bufX) then
    begin
      SetLength(bufX, Max(16, 2 * Length(bufX)));
      SetLength(bufY, Length(bufX));
    end;
    bufX[bn] := AX;
    bufY[bn] := AY;
    Inc(bn);
  end;

  procedure FlushPiece;
  begin
    if bn >= 2 then ARas.StrokePolyline(bufX, bufY, 0, bn, False, HW, ACap, AJoin, AMiter);
    bn := 0;
  end;

  { The pattern moved on by AL without drawing (whole periods skipped). }
  procedure Advance(AL: Double);
  var
    guard: Integer;
  begin
    // (Codex review 92) Whole periods off first: a short remainder is never
    // lost against a huge distance.
    AL := FMod(AL, total);
    if AL < remain then
    begin
      remain := remain - AL;
      Exit;
    end;
    AL := AL - remain;
    di := (di + 1) mod Length(ADash);
    drawing := not drawing;
    // An even pattern: a whole period comes back to the same dash.
    AL := FMod(AL, total);
    remain := ADash[di];
    guard := 0;
    while (AL >= remain) and (guard < 2 * Length(ADash) + 2) do
    begin
      AL := AL - remain;
      di := (di + 1) mod Length(ADash);
      drawing := not drawing;
      remain := ADash[di];
      Inc(guard);
    end;
    remain := Max(0, remain - AL);
  end;

  { The part of the segment A-B (its length L) within the raster grown by
    AMargin, as distances from A; False when none. }
  function Visible(L: Double; out ALo, AHi: Double): Boolean;
  var
    t0, t1, d, p, q: Double;
    e: Integer;
  begin
    t0 := 0;
    t1 := 1;
    for e := 0 to 3 do
    begin
      case e of
        0: begin d := bx - ax; p := -d; q := ax - (-AMargin); end;
        1: begin d := bx - ax; p := d; q := (ARas.W + AMargin) - ax; end;
        2: begin d := by - ay; p := -d; q := ay - (-AMargin); end;
      else
        begin d := by - ay; p := d; q := (ARas.H + AMargin) - ay; end;
      end;
      if p = 0 then
      begin
        if q < 0 then Exit(False);
      end
      else if p < 0 then t0 := Max(t0, q / p)
      else t1 := Min(t1, q / p);
    end;
    Result := t0 < t1;
    ALo := t0 * L;
    AHi := t1 * L;
  end;

begin
  n := ACount;
  if AClosed then Inc(n);
  SetLength(xs, n);
  SetLength(ys, n);
  for i := 0 to ACount - 1 do
  begin
    xs[i] := F.X[AFrom + i];
    ys[i] := F.Y[AFrom + i];
  end;
  if AClosed then
  begin
    xs[n - 1] := xs[0];
    ys[n - 1] := ys[0];
  end;
  total := 0;
  for k := 0 to High(ADash) do total := total + ADash[k];
  // Where in the pattern the path starts.
  pos := FMod(AOffset, total);
  di := 0;
  while (pos >= ADash[di]) and (pos > 0) do
  begin
    pos := pos - ADash[di];
    di := (di + 1) mod Length(ADash);
  end;
  remain := Max(0, ADash[di] - pos);
  drawing := not Odd(di);
  bn := 0;
  for i := 0 to n - 2 do
  begin
    ax := xs[i]; ay := ys[i];
    bx := xs[i + 1]; by := ys[i + 1];
    segLen := Sqrt(Sqr(bx - ax) + Sqr(by - ay));
    if segLen <= 0 then Continue;
    if not Visible(segLen, la, lb) then
    begin
      FlushPiece;
      Advance(segLen);
      Continue;
    end;
    if la > 0 then
    begin
      FlushPiece;
      Advance(la);
    end;
    // (Codex review 91) Walked from the visible part's own start: far from
    // the segment's start, adding a short dash to a huge distance would not
    // move it. Each period is a pixel at least: the guard is never reached
    // in honest use.
    ux := (bx - ax) / segLen;
    uy := (by - ay) / segLen;
    sx := ax + ux * la;
    sy := ay + uy * la;
    vis := lb - la;
    t := 0;
    // (Codex review 92) A pattern too fine for the length shown (millions
    // of dashes): that part drawn plain, the phase still carried on.
    if Length(ADash) * (vis / total + 2) > 4e6 then
    begin
      // (Codex review 93) Added to the piece under way, which goes on when
      // the dash does: its corners keep their joins.
      Put(sx, sy);
      Put(sx + ux * vis, sy + uy * vis);
      Advance(vis);
      if not drawing then FlushPiece;
      if lb < segLen then
      begin
        FlushPiece;
        Advance(segLen - lb);
      end;
      Continue;
    end;
    guard := Round(2 * Length(ADash) * (vis / total + 2)) + 16;
    if drawing then Put(sx, sy);
    while (vis - t > remain) and (guard > 0) do
    begin
      Dec(guard);
      t := t + remain;
      if drawing then
      begin
        Put(sx + ux * t, sy + uy * t);
        FlushPiece;
      end;
      di := (di + 1) mod Length(ADash);
      remain := ADash[di];
      drawing := not drawing;
      if drawing then Put(sx + ux * t, sy + uy * t);
    end;
    remain := Max(0, remain - (vis - t));
    if drawing then Put(sx + ux * vis, sy + uy * vis);
    if lb < segLen then
    begin
      FlushPiece;
      Advance(segLen - lb);
    end;
  end;
  FlushPiece;
end;

procedure TRtSvgImage.Render(const AM: TRtSvgMatrix; var ARaster: TRtSvgRaster;
  AFirst: Integer; ALast: Integer);
var
  ras: TRas;
  f: TFlat;
  i, s, j, cnt: Integer;
  t: TRtSvgMatrix;
  k, wdev, alpha, hw, margin, total: Double;
  dash: array of Double;
begin
  if (ARaster.Width <= 0) or (ARaster.Height <= 0) then Exit;
  ARaster.Lum := nil;
  ARaster.Alpha := nil;
  SetLength(ARaster.Lum, Int64(ARaster.Width) * ARaster.Height);
  SetLength(ARaster.Alpha, Int64(ARaster.Width) * ARaster.Height);
  ras := TRas.Create(ARaster.Width, ARaster.Height);
  try
    f := Default(TFlat);
    for i := Max(0, AFirst) to Min(FShapeCount, ALast) - 1 do
    begin
      t := RtSvgMul(AM, FShapes[i].M);
      k := Sqrt(Abs(t.A * t.D - t.B * t.C));
      if IsNan(k) or (k > 1e12) then Continue;
      // Off the raster (strokes and their miters counted): nothing to do.
      margin := 2;
      if FShapes[i].StrokeAlpha > 0 then
        margin := margin + Min(1e7, FShapes[i].StrokeWidth * k * Max(1, FShapes[i].MiterLimit));
      // (Codex review 91) A dashed stroke needs every length (its phase):
      // no curve shortened to its chord off the raster then.
      if (FShapes[i].StrokeAlpha > 0) and (Length(FShapes[i].Dash) > 0) then
        Flatten(Self, FShapes[i], t, ras.W, ras.H, 1e300, f)
      else
        Flatten(Self, FShapes[i], t, ras.W, ras.H, margin, f);
      if f.Bad or (f.Count = 0) then Continue;
      if (f.MaxX < -margin) or (f.MaxY < -margin) or (f.MinY > ras.H + margin) or
        (f.MinX > ras.W + margin) then Continue;
      if FShapes[i].FillAlpha > 0 then
      begin
        for s := 0 to f.Subs - 1 do
        begin
          if s < f.Subs - 1 then cnt := f.Starts[s + 1] - f.Starts[s] else cnt := f.Count - f.Starts[s];
          for j := 0 to cnt - 1 do
            ras.Seg(f.X[f.Starts[s] + j], f.Y[f.Starts[s] + j],
              f.X[f.Starts[s] + (j + 1) mod cnt], f.Y[f.Starts[s] + (j + 1) mod cnt], 1);
        end;
        ras.Composite(ARaster, FShapes[i].FillLum, FShapes[i].FillAlpha, FShapes[i].EvenOdd);
      end;
      if FShapes[i].StrokeAlpha > 0 then
      begin
        wdev := Min(1e7, FShapes[i].StrokeWidth * k);
        alpha := FShapes[i].StrokeAlpha;
        // A line thinner than a pixel: one pixel, lighter.
        if wdev < 1 then
        begin
          alpha := alpha * Max(0, wdev);
          wdev := 1;
        end;
        if alpha <= 0.002 then Continue;
        hw := wdev / 2;
        dash := nil;
        total := 0;
        if Length(FShapes[i].Dash) > 0 then
        begin
          SetLength(dash, Length(FShapes[i].Dash));
          for j := 0 to High(dash) do
          begin
            dash[j] := FShapes[i].Dash[j] * k;
            total := total + dash[j];
          end;
          // A pattern finer than a pixel reads as a plain line.
          if (total < 1) or IsNan(total) or (total > 1e15) then dash := nil;
        end;
        for s := 0 to f.Subs - 1 do
        begin
          if s < f.Subs - 1 then cnt := f.Starts[s + 1] - f.Starts[s] else cnt := f.Count - f.Starts[s];
          if dash = nil then
            ras.StrokePolyline(f.X, f.Y, f.Starts[s], cnt, f.Closed[s], hw, FShapes[i].Cap,
              FShapes[i].Join, FShapes[i].MiterLimit)
          else
            DashedStroke(ras, f, f.Starts[s], cnt, f.Closed[s], dash, FShapes[i].DashOffset * k, hw,
              margin, FShapes[i].Cap, FShapes[i].Join, FShapes[i].MiterLimit);
        end;
        ras.Composite(ARaster, FShapes[i].StrokeLum, alpha, False);
      end;
    end;
  finally
    ras.Free;
  end;
end;


{ ------------------------------------------------------------------------
  An image cropped (RtSvgCrop) }

function RtSvgCrop(AImage: TRtSvgImage; const AM: TRtSvgMatrix; AW, AH: Double;
  out AKept: TRtSvgIndexes): RawByteString;
var
  buf: RawByteString;
  blen: Integer;
  f: TFlat;
  i, ti, newText: Integer;
  t: TRtSvgMatrix;
  k: Double;
  px, py: array of Double;
  qx, qy: array of Double;
  d: string;

  function N(AValue: Double): string;
  begin
    Result := FormatFloat('0.###', AValue, Dot);
  end;

  function Grey(ALum: Single): string;
  var
    v: Integer;
  begin
    v := EnsureRange(Round(ALum * 255), 0, 255);
    Result := '#' + IntToHex(v, 2) + IntToHex(v, 2) + IntToHex(v, 2);
  end;

  procedure Put(const S: string);
  begin
    if S = '' then Exit;
    if blen + Length(S) > RTSVG_CROP_MAX_BYTES then TooBig('cropped image');
    if blen + Length(S) > Length(buf) then SetLength(buf, Max(blen + Length(S), 2 * Length(buf) + 4096));
    Move(S[1], buf[blen + 1], Length(S));
    Inc(blen, Length(S));
  end;

  function Xml(const S: string): string;
  var
    c: Integer;
  begin
    Result := '';
    for c := 1 to Length(S) do
      case S[c] of
        '&': Result := Result + '&amp;';
        '<': Result := Result + '&lt;';
        '>': Result := Result + '&gt;';
        '"': Result := Result + '&quot;';
      else
        if S[c] >= ' ' then Result := Result + S[c];
      end;
  end;

  { One polygon (a subpath filled) clipped to the frame (Sutherland-Hodgman,
    edge by edge), its points left in px / py. }
  procedure ClipPolygon(const AX, AY: array of Double; AFrom, ACount: Integer; out AOut: Integer);
  var
    edge, e, m: Integer;
    ax0, ay0, ax1, ay1, tt, lim: Double;
    in0, in1: Boolean;

    function Inside(X, Y: Double): Boolean;
    begin
      case edge of
        0: Result := X >= 0;
        1: Result := X <= AW;
        2: Result := Y >= 0;
      else
        Result := Y <= AH;
      end;
    end;

    procedure Cross(X0, Y0, X1, Y1: Double; out X, Y: Double);
    begin
      case edge of
        0, 1:
          begin
            if edge = 0 then lim := 0 else lim := AW;
            tt := (lim - X0) / (X1 - X0);
            X := lim;
            Y := Y0 + (Y1 - Y0) * tt;
          end;
      else
        if edge = 2 then lim := 0 else lim := AH;
        tt := (lim - Y0) / (Y1 - Y0);
        X := X0 + (X1 - X0) * tt;
        Y := lim;
      end;
    end;

    procedure Emit(X, Y: Double);
    begin
      if m >= Length(qx) then
      begin
        SetLength(qx, Max(64, 2 * Length(qx)));
        SetLength(qy, Length(qx));
      end;
      qx[m] := X;
      qy[m] := Y;
      Inc(m);
    end;

  var
    x, y: Double;
  begin
    // the points work in px / py, each edge's result in qx / qy
    if Length(px) < ACount then
    begin
      SetLength(px, ACount);
      SetLength(py, ACount);
    end;
    for e := 0 to ACount - 1 do
    begin
      px[e] := AX[AFrom + e];
      py[e] := AY[AFrom + e];
    end;
    AOut := ACount;
    for edge := 0 to 3 do
    begin
      if AOut = 0 then Break;
      m := 0;
      for e := 0 to AOut - 1 do
      begin
        ax0 := px[e];
        ay0 := py[e];
        ax1 := px[(e + 1) mod AOut];
        ay1 := py[(e + 1) mod AOut];
        in0 := Inside(ax0, ay0);
        in1 := Inside(ax1, ay1);
        if in0 then Emit(ax0, ay0);
        if in0 <> in1 then
        begin
          Cross(ax0, ay0, ax1, ay1, x, y);
          Emit(x, y);
        end;
      end;
      if Length(px) < m then
      begin
        SetLength(px, m);
        SetLength(py, m);
      end;
      for e := 0 to m - 1 do
      begin
        px[e] := qx[e];
        py[e] := qy[e];
      end;
      AOut := m;
    end;
  end;

  { A segment clipped to the frame (Liang-Barsky): False when it is out. }
  function ClipSegment(var X0, Y0, X1, Y1: Double): Boolean;
  var
    t0, t1, dx, dy: Double;

    function Edge(P, Q: Double): Boolean;
    var
      r: Double;
    begin
      Result := True;
      if Abs(P) < 1e-15 then
      begin
        if Q < 0 then Result := False;
        Exit;
      end;
      r := Q / P;
      if P < 0 then
      begin
        if r > t1 then Result := False
        else if r > t0 then t0 := r;
      end
      else
      begin
        if r < t0 then Result := False
        else if r < t1 then t1 := r;
      end;
    end;

  begin
    t0 := 0;
    t1 := 1;
    dx := X1 - X0;
    dy := Y1 - Y0;
    Result := Edge(-dx, X0) and Edge(dx, AW - X0) and Edge(-dy, Y0) and Edge(dy, AH - Y0);
    if not Result then Exit;
    X1 := X0 + t1 * dx;
    Y1 := Y0 + t1 * dy;
    X0 := X0 + t0 * dx;
    Y0 := Y0 + t0 * dy;
  end;

  procedure WriteText(AIndex: Integer);
  var
    tx: TRtSvgText;
    m: TRtSvgMatrix;
    x, y: Double;
    attrs: string;
  begin
    tx := AImage.Texts[AIndex];
    m := RtSvgMul(AM, tx.M);
    RtSvgApply(m, tx.X, tx.Y, x, y);
    // kept whole when its anchor is inside
    if IsNan(x) or IsNan(y) or (x < 0) or (y < 0) or (x > AW) or (y > AH) or (tx.Text = '') then Exit;
    attrs := ' font-size="' + N(tx.Size) + '" fill="' + Grey(tx.Lum) + '"';
    if tx.Alpha < 0.999 then attrs := attrs + ' fill-opacity="' + N(tx.Alpha) + '"';
    if tx.Mono then attrs := attrs + ' font-family="monospace"' else attrs := attrs + ' font-family="sans-serif"';
    if tx.Bold then attrs := attrs + ' font-weight="bold"';
    if tx.Italic then attrs := attrs + ' font-style="italic"';
    case tx.Anchor of
      1: attrs := attrs + ' text-anchor="middle"';
      2: attrs := attrs + ' text-anchor="end"';
    end;
    case tx.Baseline of
      1: attrs := attrs + ' dominant-baseline="central"';
      2: attrs := attrs + ' dominant-baseline="hanging"';
    end;
    Put('<text x="' + N(tx.X) + '" y="' + N(tx.Y) + '"' + attrs + ' transform="matrix(' + N(m.A) + ' ' + N(m.B) + ' ' +
      N(m.C) + ' ' + N(m.D) + ' ' + N(m.E) + ' ' + N(m.F) + ')">' + Xml(tx.Text) + '</text>' + LineEnding);
    AKept[AIndex] := newText;
    Inc(newText);
  end;

  procedure WriteTexts(AOrder: Integer);
  begin
    // the texts standing before shape AOrder (all those left after the last)
    while (ti < AImage.TextCount) and ((AImage.Texts[ti].Order <= AOrder) or (AOrder >= AImage.ShapeCount)) do
    begin
      WriteText(ti);
      Inc(ti);
    end;
  end;

  procedure WriteShape(AIndex: Integer);
  var
    sh: TRtSvgShape;
    m, e, run, s, cnt: Integer;
    x0, y0, x1, y1, ax, ay, bx, by, dist, seg, offStart: Double;
    stroke: string;
    inRun: Boolean;
    dash: string;

    procedure Flush(var APath: string; AOffset: Double);
    begin
      if APath = '' then Exit;
      if dash <> '' then
        Put('<path d="' + APath + '"' + stroke + ' stroke-dashoffset="' + N(sh.DashOffset * k + AOffset) + '"/>' +
          LineEnding)
      else
        Put('<path d="' + APath + '"' + stroke + '/>' + LineEnding);
      APath := '';
    end;

  begin
    sh := AImage.FShapes[AIndex];
    t := RtSvgMul(AM, sh.M);
    k := Sqrt(Abs(t.A * t.D - t.B * t.C));
    if IsNan(k) or (k > 1e12) then Exit;
    f := Default(TFlat);
    Flatten(AImage, sh, t, AW, AH, 1e300, f);
    if f.Bad or (f.Count = 0) then Exit;
    // nothing of it inside (its stroke counted)
    if (f.MaxX < -sh.StrokeWidth * k) or (f.MaxY < -sh.StrokeWidth * k) or (f.MinX > AW + sh.StrokeWidth * k) or
      (f.MinY > AH + sh.StrokeWidth * k) then Exit;
    if sh.FillAlpha > 0 then
    begin
      d := '';
      for s := 0 to f.Subs - 1 do
      begin
        if s < f.Subs - 1 then cnt := f.Starts[s + 1] - f.Starts[s] else cnt := f.Count - f.Starts[s];
        if cnt < 3 then Continue;
        ClipPolygon(f.X, f.Y, f.Starts[s], cnt, m);
        if m < 3 then Continue;
        d := d + 'M' + N(px[0]) + ' ' + N(py[0]);
        for e := 1 to m - 1 do d := d + 'L' + N(px[e]) + ' ' + N(py[e]);
        d := d + 'Z';
        if Length(d) > RTSVG_CROP_MAX_BYTES then TooBig('cropped image');
      end;
      if d <> '' then
      begin
        Put('<path d="' + d + '" fill="' + Grey(sh.FillLum) + '"');
        if sh.FillAlpha < 0.999 then Put(' fill-opacity="' + N(sh.FillAlpha) + '"');
        if sh.EvenOdd then Put(' fill-rule="evenodd"');
        Put(' stroke="none"/>' + LineEnding);
      end;
    end;
    if sh.StrokeAlpha > 0 then
    begin
      stroke := ' fill="none" stroke="' + Grey(sh.StrokeLum) + '" stroke-width="' + N(sh.StrokeWidth * k) + '"';
      if sh.StrokeAlpha < 0.999 then stroke := stroke + ' stroke-opacity="' + N(sh.StrokeAlpha) + '"';
      case sh.Cap of
        rcRound: stroke := stroke + ' stroke-linecap="round"';
        rcSquare: stroke := stroke + ' stroke-linecap="square"';
      end;
      case sh.Join of
        rjRound: stroke := stroke + ' stroke-linejoin="round"';
        rjBevel: stroke := stroke + ' stroke-linejoin="bevel"';
      else
        stroke := stroke + ' stroke-miterlimit="' + N(sh.MiterLimit) + '"';
      end;
      dash := '';
      if Length(sh.Dash) > 0 then
      begin
        for e := 0 to High(sh.Dash) do
        begin
          if e > 0 then dash := dash + ' ';
          dash := dash + N(sh.Dash[e] * k);
        end;
        stroke := stroke + ' stroke-dasharray="' + dash + '"';
      end;
      for s := 0 to f.Subs - 1 do
      begin
        if s < f.Subs - 1 then cnt := f.Starts[s + 1] - f.Starts[s] else cnt := f.Count - f.Starts[s];
        if cnt < 2 then Continue;
        // its segments inside, in runs (a run broken where it leaves the
        // frame); a dashed run starts at the phase it had there
        d := '';
        inRun := False;
        dist := 0;
        offStart := 0;
        if f.Closed[s] then run := cnt else run := cnt - 1;
        for e := 0 to run - 1 do
        begin
          ax := f.X[f.Starts[s] + e];
          ay := f.Y[f.Starts[s] + e];
          bx := f.X[f.Starts[s] + (e + 1) mod cnt];
          by := f.Y[f.Starts[s] + (e + 1) mod cnt];
          seg := Hypot(bx - ax, by - ay);
          x0 := ax; y0 := ay; x1 := bx; y1 := by;
          if ClipSegment(x0, y0, x1, y1) then
          begin
            if not inRun then
            begin
              if dash <> '' then Flush(d, offStart);
              offStart := dist + Hypot(x0 - ax, y0 - ay);
              d := d + 'M' + N(x0) + ' ' + N(y0);
              inRun := True;
            end;
            d := d + 'L' + N(x1) + ' ' + N(y1);
            // it leaves the frame on this segment: the run ends
            if (Abs(x1 - bx) > 1e-9) or (Abs(y1 - by) > 1e-9) then inRun := False;
          end
          else
            inRun := False;
          dist := dist + seg;
          if Length(d) > RTSVG_CROP_MAX_BYTES then TooBig('cropped image');
        end;
        Flush(d, offStart);
      end;
    end;
  end;

begin
  AKept := nil;
  SetLength(AKept, AImage.TextCount);
  for i := 0 to High(AKept) do AKept[i] := -1;
  if (AW <= 0) or (AH <= 0) or IsNan(AW) or IsNan(AH) or (AW > RTSVG_MAX_SIDE) or (AH > RTSVG_MAX_SIDE) then
    raise ERtSvg.Create('Unusable frame to crop to');
  newText := 0;
  ti := 0;
  buf := '';
  blen := 0;
  begin
    Put('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + N(AW) + ' ' + N(AH) + '" width="' + N(AW) +
      '" height="' + N(AH) + '">' + LineEnding);
    for i := 0 to AImage.ShapeCount - 1 do
    begin
      WriteTexts(i);
      WriteShape(i);
    end;
    WriteTexts(MaxInt);
    Put('</svg>' + LineEnding);
    SetLength(buf, blen);
    Result := buf;
  end;
end;

initialization
  Dot := DefaultFormatSettings;
  Dot.DecimalSeparator := '.';
  Dot.ThousandSeparator := #0;

end.
