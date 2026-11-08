$title PBUC of a gas-fired unit, piecewise linear heat-rate function (MILP)
$onText
Same model as pbuc_miqp.gms with the quadratic heat-rate function replaced by
a piecewise linear function with NSEG segments of equal width between the
minimum and maximum output (sequentially filled segments). Profit and gas
consumption of the schedule are also evaluated with the exact function.

Horizon
  The year (8,784 hours) is solved as a sequence of windows. Each window has a
  commitment block of COMMIT hours and a look-ahead of LOOK hours; only the
  decisions in the block are fixed, and the next window starts after it. The
  last max(Lup, Ldown) hours of the preceding blocks stay in the model as fixed
  variables, so ramp limits and minimum up and down times are enforced across
  windows.
    --COMMIT=8784 --LOOK=0   full-year model (one window)
    --LOOK=0                 myopic planning (no look-ahead)

Options (defaults in brackets)
  --XLS=<parameter file> [..\data\params_unitA.xlsx]   --IDX=<index sheet> [index]
  --FPRICE=<USD/MMBtu>   gas price; overrides the value in the parameter file
  --COMMIT=<h> [168]  --LOOK=<h> [48]
  --NSEG=<number of segments> [10]
  --FIL=calc|excel [calc]  segment slopes computed from the heat-rate
                           coefficients (chord slopes) or read from the
                           parameter file (symbol f_il)
  --SEQ=all|auto [all]     sequencing binaries for all units or only for A < 0
  --WRESLIM=<time limit per window, s> [3600]  --OPTCR=<relative gap> [0]
  --OUT=<prefix of the output files> [rh_c<COMMIT>_l<LOOK>]
  --SUM=<summary file> [rh_summary.csv]

Output
  <OUT>_report.csv  settings, annual results, windows, hourly schedule
  <OUT>_out.gdx     solution
  <SUM>             one line per run (appended)
  profitPWL is the PWL objective, profitExact the profit of the same schedule
  with the exact heat-rate function.
$offText

$if not set XLS     $set XLS     ..\data\params_unitA.xlsx
$if not set IDX     $set IDX     index
$if not set COMMIT  $set COMMIT  168
$if not set LOOK    $set LOOK    48
$if not set NSEG    $set NSEG    10
$if not set FIL     $set FIL     calc
$if not set WRESLIM $set WRESLIM 3600
$if not set OPTCR   $set OPTCR   0
$if not set OUT     $set OUT     rh_c%COMMIT%_l%LOOK%
$if not set SEQ     $set SEQ     all

$if not set SUM     $set SUM     rh_summary.csv
$set WRITEHDR 0
$if not exist %SUM% $set WRITEHDR 1

$onEcho > rh_idx.txt
index='%IDX%'!A1
$offEcho
$call gdxxrw.exe "%XLS%" output=rh_base.gdx @rh_idx.txt
$ifE errorLevel<>0 $abort gdxxrw failed

SETS
         t(*)            hourly time step
         l               linearization steps             / l1*l%NSEG% /
         i               Generators                      / G1 /
         wnd             rolling-horizon windows         / w1*w9000 /
         tw(t)           hours optimized in the current window
         hist(t)         fixed hours kept in the model to carry the state
         act(t)          tw + hist;

$gdxIn rh_base.gdx
$load t
ALIAS (t,h);

PARAMETERS
         e_price(t), M(t,i), F(i), A(i), B(i), C(i), SC(i), Lup(i), Ldown(i)
         RampUp(i), StartRampUp(i), RampDown(i), CloseRampDown(i)
         Qmin(t,i), Qmax(t,i)
         f_il(l,i)       linearization slopes
         DeltaQ(t,i)     segment width;

$load e_price M F A B C SC Lup Ldown RampUp StartRampUp RampDown CloseRampDown Qmin Qmax
$ifThenI %FIL%==excel
$load f_il
$endIf
$gdxIn

DeltaQ(t,i) = (Qmax(t,i) - Qmin(t,i)) / card(l);

$if set FPRICE F(i) = %FPRICE%;

Parameter useSeq(i) 1 if sequencing binaries are generated for unit i;
$ifThenI %SEQ%==auto
useSeq(i) = 1$(A(i) < 0);
$else
useSeq(i) = 1;
$endIf
display F, useSeq;

$ifThenI %FIL%==calc
Parameters Qlo(i), Qhi(i), Wseg(i);
Qlo(i)  = smin(t$(Qmin(t,i) > 0), Qmin(t,i));
Qhi(i)  = smax(t, Qmax(t,i));
Wseg(i) = (Qhi(i) - Qlo(i)) / card(l);
f_il(l,i) = A(i)*(2*Qlo(i) + (2*ord(l) - 1)*Wseg(i)) + B(i);
$endIf
abort$(smin((l,i), abs(f_il(l,i))) = 0) 'f_il has missing segments: NSEG must match the Linearization sheet, or use --FIL=calc';

* consistency check: the slopes must match the heat-rate coefficients of the
* unit for NSEG equal segments between the lowest Qmin and the highest Qmax.
* A mismatch means that the Linearization range in the index sheet does not
* have NSEG rows or belongs to another unit.
Parameters chkQlo(i), chkW(i), chkSlope(l,i), chkDev;
chkQlo(i)     = smin(t$(Qmin(t,i) > 0), Qmin(t,i));
chkW(i)       = (smax(t, Qmax(t,i)) - chkQlo(i)) / card(l);
chkSlope(l,i) = A(i)*(2*chkQlo(i) + (2*ord(l) - 1)*chkW(i)) + B(i);
chkDev        = smax((l,i), abs(f_il(l,i) - chkSlope(l,i)) / abs(chkSlope(l,i)));
display chkSlope, chkDev;
abort$(chkDev > 0.01) 'f_il does not match NSEG and the unit coefficients (deviation > 1%): check --NSEG and the f_il range in the index sheet, or use --FIL=calc', chkDev;
display f_il;

Scalars
   Tn         number of hours
   commitLen  / %COMMIT% /
   lookLen    / %LOOK% /
   nW         number of windows
   Hmax       history length kept for state carry
   wStart, cEnd, wEnd;

Tn   = card(t);
nW   = ceil(Tn / commitLen);
Hmax = max(1, smax(i, max(Lup(i), Ldown(i))));
abort$(nW > card(wnd)) 'too many windows: enlarge set wnd';

*-------------------------------------------------------------------------------
* Model (Section 2 of the paper, PWL fuel cost), restricted to the current window
*-------------------------------------------------------------------------------
variables
         Q(t,i), rev, heatCost, fixCost, delta(t,i,l), OBJ;
Binary Variables
         sUP(t,i), sDOWN(t,i), u(t,i), z(t,i,l);
positive variable Q;

Equations
         Objective, Revenue, HeatFunction, FCost
         RampUpE(t,i), RampDownE(t,i), UandS(t,i), OpenAndClose(t,i)
         MinOpen(t,i), MinClose(t,i), Avaliable(t,i)
         CapacityMin(t,i), CapacityMax(t,i)
         Delta_lower(t,i,l), Delta_upper(t,i,l), Eq_SeqFill1(t,i,l), Eq_SeqFill2(t,i,l)
         Production(t,i);

Revenue          ..  sum((t,i)$tw(t), Q(t,i)*e_price(t)) =E= rev;
HeatFunction     ..  sum((t,i)$tw(t), F(i)*((A(i)*Qmin(t,i)*Qmin(t,i) + B(i)*Qmin(t,i) + C(i))*u(t,i)
                                            + sum(l, f_il(l,i)*delta(t,i,l)))) =E= heatCost;
FCost            ..  sum((t,i)$tw(t), SC(i)*sUP(t,i)) =E= fixCost;
Objective        ..  rev - heatCost - fixCost =E= OBJ;

Production(t,i)$tw(t)..          Q(t,i) =E= Qmin(t,i)*u(t,i) + sum(l, delta(t,i,l));
Delta_lower(t,i,l)$tw(t)..       0 =L= delta(t,i,l);
Delta_upper(t,i,l)$tw(t)..       delta(t,i,l) =L= ((Qmax(t,i) - Qmin(t,i))/card(l))*u(t,i);
Eq_SeqFill1(t,i,l)$(tw(t) and useSeq(i) and ord(l) < card(l))..  DeltaQ(t,i)*z(t,i,l) =L= delta(t,i,l);
Eq_SeqFill2(t,i,l)$(tw(t) and useSeq(i) and ord(l) < card(l))..  delta(t,i,l+1) =L= DeltaQ(t,i)*z(t,i,l);

* lagged terms at the window start refer to fixed hours of the previous window
RampUpE(t,i)$tw(t)..     Q(t,i) - Q(t-1,i) =L= StartRampUp(i)*sUP(t,i) + RampUp(i)*u(t-1,i);
RampDownE(t,i)$tw(t)..   Q(t-1,i) - Q(t,i) =L= CloseRampDown(i)*sDOWN(t,i) + RampDown(i)*u(t,i);
UandS(t,i)$tw(t)..       u(t,i) - u(t-1,i) =E= sUP(t,i) - sDOWN(t,i);
OpenAndClose(t,i)$tw(t)..  sUP(t,i) + sDOWN(t,i) =L= 1;

* written also for the history hours, so that a start-up / shut-down in the
* previous window still restricts the first hours of the current window
MinOpen(t,i)$act(t)..   sUP(t,i)   + sum(h$(act(h) and ord(h) ge ord(t) and ord(h) le ord(t)+Lup(i)-1),   sDOWN(h,i)) =L= 1;
MinClose(t,i)$act(t)..  sDOWN(t,i) + sum(h$(act(h) and ord(h) ge ord(t) and ord(h) le ord(t)+Ldown(i)-1), sUP(h,i))   =L= 1;

Avaliable(t,i)$tw(t)..   u(t,i) =L= 1 - M(t,i);
CapacityMin(t,i)$tw(t).. Qmin(t,i)*u(t,i) =L= Q(t,i);
CapacityMax(t,i)$tw(t).. Q(t,i) =L= Qmax(t,i)*u(t,i);

MODEL RH / all /;
RH.reslim    = %WRESLIM%;
RH.solvelink = 5;
option mip = gurobi, optcr = %OPTCR%;

*-------------------------------------------------------------------------------
* Rolling-horizon loop
*-------------------------------------------------------------------------------
Parameters
   winStart(wnd), winCommitEnd(wnd), winEnd(wnd)
   winStat(wnd)     model status
   winObj(wnd)      window objective incl. look-ahead (USD)
   winGap(wnd)      relative MIP gap
   winTime(wnd)     solver time (s);

loop(wnd$(ord(wnd) <= nW),
   wStart = (ord(wnd) - 1)*commitLen + 1;
   cEnd   = min(Tn, wStart + commitLen - 1);
   wEnd   = min(Tn, cEnd + lookLen);

   tw(t)   = yes$(ord(t) >= wStart and ord(t) <= wEnd);
   hist(t) = yes$(ord(t) <  wStart and ord(t) >= wStart - Hmax);
   act(t)  = tw(t) + hist(t);

   solve RH using mip maximizing OBJ;

   winStart(wnd)     = wStart;
   winCommitEnd(wnd) = cEnd;
   winEnd(wnd)       = wEnd;
   winStat(wnd)      = RH.modelstat;
   winObj(wnd)       = OBJ.l;
   winTime(wnd)      = RH.resusd;
   winGap(wnd)       = abs(RH.objest - RH.objval) / max(1e-9, abs(RH.objval));

   abort$(RH.modelstat <> 1 and RH.modelstat <> 8) 'window not solved to a feasible solution', wStart, winStat;

*  fix the committed block; look-ahead hours stay free for the next window
   u.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)       = round(u.l(t,i));
   sUP.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)     = round(sUP.l(t,i));
   sDOWN.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)   = round(sDOWN.l(t,i));
   z.fx(t,i,l)$(ord(t) >= wStart and ord(t) <= cEnd)     = round(z.l(t,i,l));
   Q.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)       = Q.l(t,i);
   delta.fx(t,i,l)$(ord(t) >= wStart and ord(t) <= cEnd) = delta.l(t,i,l);
);

*-------------------------------------------------------------------------------
* Full-year evaluation of the stitched schedule
*-------------------------------------------------------------------------------
Parameters gasUse(t,i) exact hourly gas use (MMBtu);
Scalars revTot, heatPWL, heatExact, startCost, nStarts, gasTot, gasPeak, hoursOn,
        profitPWL, profitExact, totTime, maxGap, nOptimal;

gasUse(t,i) = A(i)*sqr(Q.l(t,i)) + B(i)*Q.l(t,i) + C(i)*u.l(t,i);
revTot      = sum((t,i), e_price(t)*Q.l(t,i));
heatPWL     = sum((t,i), F(i)*((A(i)*sqr(Qmin(t,i)) + B(i)*Qmin(t,i) + C(i))*u.l(t,i)
                               + sum(l, f_il(l,i)*delta.l(t,i,l))));
heatExact   = sum((t,i), F(i)*gasUse(t,i));
startCost   = sum((t,i), SC(i)*sUP.l(t,i));
nStarts     = sum((t,i), sUP.l(t,i));
gasTot      = sum((t,i), gasUse(t,i));
gasPeak     = smax(t, sum(i, gasUse(t,i)));
hoursOn     = sum((t,i), u.l(t,i));
profitPWL   = revTot - heatPWL   - startCost;
profitExact = revTot - heatExact - startCost;
totTime     = sum(wnd, winTime(wnd));
maxGap      = smax(wnd$(ord(wnd) <= nW), winGap(wnd));
nOptimal    = sum(wnd$(ord(wnd) <= nW and winStat(wnd) = 1), 1);

display nW, profitPWL, profitExact, revTot, heatPWL, heatExact, startCost, nStarts,
        gasTot, gasPeak, hoursOn, totTime, maxGap, nOptimal;

execute_unload '%OUT%_out.gdx', Q, u, sUP, sDOWN, delta, gasUse, winStart, winEnd,
               winStat, winObj, winGap, winTime;

FILE csv / %OUT%_report.csv /;
csv.pc = 5;
put csv;
put 'COMMIT', commitLen / 'SEQ', '%SEQ%' / 'GasPrice', smax(i, F(i)) / 'LOOK', lookLen / 'NSEG', card(l) / 'Windows', nW /;
put 'ProfitPWL', profitPWL / 'ProfitExact', profitExact / 'Revenue', revTot /;
put 'HeatCostPWL', heatPWL / 'HeatCostExact', heatExact / 'StartCost', startCost /;
put 'Starts', nStarts / 'HoursOn', hoursOn / 'GasTotal_MMBtu', gasTot / 'GasPeak_MMBtu_h', gasPeak /;
put 'SolverTime_s', totTime / 'MaxWindowGap', maxGap / 'WindowsOptimal', nOptimal /;
put / 'window', 'start', 'commitEnd', 'end', 'status', 'objective', 'gap', 'time_s' /;
loop(wnd$(ord(wnd) <= nW),
   put wnd.tl, winStart(wnd), winCommitEnd(wnd), winEnd(wnd), winStat(wnd), winObj(wnd), winGap(wnd), winTime(wnd) /;
);
put / 'hour', 'Q', 'u', 'sUP', 'sDOWN', 'gas_MMBtu', 'price' /;
loop(t,
   put t.tl, Q.l(t,'G1'), u.l(t,'G1'), sUP.l(t,'G1'), sDOWN.l(t,'G1'), gasUse(t,'G1'), e_price(t) /;
);
putclose csv;

FILE sumf / %SUM% /;
sumf.pc = 5;
sumf.ap = 1;
put sumf;
$ifThen %WRITEHDR%==1
put 'out', 'COMMIT', 'LOOK', 'NSEG', 'SEQ', 'F', 'windows', 'profitPWL', 'profitExact', 'starts',
    'hoursOn', 'gasTotal', 'gasPeak', 'solverTime_s', 'maxGap', 'windowsOptimal' /;
$endIf
put '%OUT%', commitLen, lookLen, card(l), '%SEQ%', smax(i, F(i)), nW, profitPWL, profitExact, nStarts,
    hoursOn, gasTot, gasPeak, totTime, maxGap, nOptimal /;
putclose sumf;
