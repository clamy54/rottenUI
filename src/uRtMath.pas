// Copyright (C) 2024 - 2026 Cyril LAMY
// SPDX-License-Identifier: GPL-3.0-or-later
unit uRtMath;

{$mode objfpc}{$H+}

{ Trigonometry of rottenUI's own, the same to the bit on every system: only
  IEEE additions, multiplications and divisions (correctly rounded
  everywhere), never the platform's library, whose last bits differ (a
  drawing then shifts a pixel). Accurate to a few units in the last place
  over the angles a drawing uses. }

interface

function RtSin(X: Double): Double;
function RtCos(X: Double): Double;
function RtTan(X: Double): Double;
function RtArcTan2(Y, X: Double): Double;

implementation

uses
  Math;

const
  // pi / 2 split in two (Cody and Waite): the reduction stays exact
  PIO2_HI = 1.5707963267341256;
  PIO2_LO = 6.077100506506192601e-11;
  TWO_O_PI = 0.63661977236758134308;
  PI_D = 3.141592653589793116;
  PIO4_D = 0.785398163397448279;

{ sin and cos of R in [-pi/4, pi/4], by their series (Horner). }
function SinPoly(R: Double): Double;
var
  r2: Double;
begin
  r2 := R * R;
  Result := R * (1 + r2 * (-1 / 6 + r2 * (1 / 120 + r2 * (-1 / 5040 + r2 * (1 / 362880 + r2 * (-1 / 39916800 +
    r2 * (1 / 6227020800 + r2 * (-1 / 1307674368000 + r2 * (1 / 355687428096000)))))))));
end;

function CosPoly(R: Double): Double;
var
  r2: Double;
begin
  r2 := R * R;
  Result := 1 + r2 * (-1 / 2 + r2 * (1 / 24 + r2 * (-1 / 720 + r2 * (1 / 40320 + r2 * (-1 / 3628800 +
    r2 * (1 / 479001600 + r2 * (-1 / 87178291200 + r2 * (1 / 20922789888000))))))));
end;

procedure Reduce(X: Double; out R: Double; out Q: Integer);
var
  k: Double;
begin
  k := Floor(X * TWO_O_PI + 0.5);
  R := (X - k * PIO2_HI) - k * PIO2_LO;
  Q := Integer(Trunc(k - 4 * Floor(k / 4)));   // 0..3
end;

function RtSin(X: Double): Double;
var
  r: Double;
  q: Integer;
begin
  if IsNan(X) or IsInfinite(X) then Exit(NaN);
  if Abs(X) > 1e9 then Exit(0);
  Reduce(X, r, q);
  case q of
    0: Result := SinPoly(r);
    1: Result := CosPoly(r);
    2: Result := -SinPoly(r);
  else
    Result := -CosPoly(r);
  end;
end;

function RtCos(X: Double): Double;
var
  r: Double;
  q: Integer;
begin
  if IsNan(X) or IsInfinite(X) then Exit(NaN);
  if Abs(X) > 1e9 then Exit(1);
  Reduce(X, r, q);
  case q of
    0: Result := CosPoly(r);
    1: Result := -SinPoly(r);
    2: Result := -CosPoly(r);
  else
    Result := SinPoly(r);
  end;
end;

function RtTan(X: Double): Double;
var
  c: Double;
begin
  c := RtCos(X);
  if c = 0 then Exit(Sign(RtSin(X)) * 1e300);
  Result := RtSin(X) / c;
end;

{ atan of T in [0, 1]: brought to |u| <= tan(pi/8) around pi/4, then its
  series. }
function ArcTan01(T: Double): Double;
var
  u, u2, term, sum: Double;
  base: Double;
  n: Integer;
begin
  if T > 0.41421356237309503 then
  begin
    u := (T - 1) / (T + 1);
    base := PIO4_D;
  end
  else
  begin
    u := T;
    base := 0;
  end;
  u2 := u * u;
  term := u;
  sum := 0;
  // |u| <= 0.4143: 24 terms reach below 1e-18
  for n := 0 to 23 do
  begin
    if Odd(n) then sum := sum - term / (2 * n + 1) else sum := sum + term / (2 * n + 1);
    term := term * u2;
  end;
  Result := base + sum;
end;

function RtArcTan2(Y, X: Double): Double;
var
  ax, ay, a: Double;
begin
  if IsNan(X) or IsNan(Y) then Exit(NaN);
  ax := Abs(X);
  ay := Abs(Y);
  if (ax = 0) and (ay = 0) then Exit(0);
  if ay <= ax then a := ArcTan01(ay / ax)
  else a := PI_D / 2 - ArcTan01(ax / ay);
  if X < 0 then a := PI_D - a;
  if Y < 0 then a := -a;
  Result := a;
end;

end.
