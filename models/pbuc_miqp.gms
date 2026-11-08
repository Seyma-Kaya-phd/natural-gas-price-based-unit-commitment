$title PBUC of a gas-fired unit, exact quadratic heat-rate function (MIQP)
$onText
Profit-based unit commitment of a price-taking gas-fired unit with the exact
quadratic heat-rate function. Model of Section 2 of the paper:
  max  sum_t  e_t Q_t - F (A Q_t^2 + B Q_t + C u_t) - SC s_t^up
  s.t. capacity limits, ramp limits with start-up and shut-down ramp limits,
       minimum up and down times (sum from t to t+L-1), logical constraints,
       unit availability u_t <= 1 - M_t; the unit is offline before hour 1.

Horizon
  The year (8,784 hours) is solved as a sequence of windows. Each window has a
  commitment block of COMMIT hours and a look-ahead of LOOK hours; only the
  decisions in the block are fixed, and the next window starts after it. The
  last max(Lup, Ldown) hours of the preceding blocks stay in the model as fixed
  variables, so ramp limits and minimum up and down times are enforced across
  windows.
    --COMMIT=8784 --LOOK=0   full-year model (one window)
    --LOOK=0                 myopic planning (no look-ahead)

Fuel-cost constraint (--QFORM)
  eq   : one quadratic equality for the total fuel cost (default). Required for
         units with a concave heat-rate function (A < 0).
  ineq : hourly fuel-cost variables c_t >= F (A Q_t^2 + B Q_t + C u_t) for units
         with A >= 0 (convex constraint, tight at the optimum); the equality is
         kept for units with A < 0. Same optimum, usually much faster for A >= 0.

Options (defaults in brackets)
  --XLS=<parameter file> [..\data\params_unitA.xlsx]   --IDX=<index sheet> [index]
  --FPRICE=<USD/MMBtu>   gas price; overrides the value in the parameter file
  --COMMIT=<h> [168]  --LOOK=<h> [48]
  --QFORM=eq|ineq [eq]
  --WRESLIM=<time limit per window, s> [3600]  --OPTCR=<relative gap> [0]
  --OUT=<prefix of the output files> [miqp_c<COMMIT>_l<LOOK>]
  --SUM=<summary file> [rh_miqp_summary.csv]

Output
  <OUT>_report.csv  settings, annual results, windows, hourly schedule
  <OUT>_out.gdx     solution
  <SUM>             one line per run (appended)
$offText

$if not set XLS     $set XLS     ..\data\params_unitA.xlsx
$if not set IDX     $set IDX     index
$if not set COMMIT  $set COMMIT  168
$if not set LOOK    $set LOOK    48
$if not set WRESLIM $set WRESLIM 3600
$if not set OPTCR   $set OPTCR   0
$if not set QFORM   $set QFORM   eq
$if not set OUT     $set OUT     miqp_c%COMMIT%_l%LOOK%
$if not set SUM     $set SUM     rh_miqp_summary.csv

$set WRITEHDR 0
$if not exist %SUM% $set WRITEHDR 1

$onEcho > rhq_idx.txt
index='%IDX%'!A1
$offEcho
$call gdxxrw.exe "%XLS%" output=rhq_base.gdx @rhq_idx.txt
$ifE errorLevel<>0 $abort gdxxrw failed

SETS
         t(*)            hourly time step
         i               Generators                      / G1 /
         wnd             rolling-horizon windows         / w1*w9000 /
         tw(t)           hours optimized in the current window
         hist(t)         fixed hours kept in the model to carry the state
         act(t)          tw + hist;

$gdxIn rhq_base.gdx
$load t
ALIAS (t,h);

PARAMETERS
         e_price(t), M(t,i), F(i), A(i), B(i), C(i), SC(i), Lup(i), Ldown(i)
         RampUp(i), StartRampUp(i), RampDown(i), CloseRampDown(i)
         Qmin(t,i), Qmax(t,i);

$load e_price M F A B C SC Lup Ldown RampUp StartRampUp RampDown CloseRampDown Qmin Qmax
$gdxIn

$if set FPRICE F(i) = %FPRICE%;
display F, A, B, C, SC, Lup, Ldown;

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
* Model (Section 2 of the paper), restricted to the current window
*-------------------------------------------------------------------------------
variables
         Q(t,i), rev, heatCost, fixCost, OBJ, hc(t,i);
Binary Variables
         sUP(t,i), sDOWN(t,i), u(t,i);
positive variable Q;

Equations
         Objective, Revenue, HeatFunction, FCost
         RampUpE(t,i), RampDownE(t,i), UandS(t,i), OpenAndClose(t,i)
         MinOpen(t,i), MinClose(t,i), Avaliable(t,i)
         CapacityMin(t,i), CapacityMax(t,i);

Revenue          ..  sum((t,i)$tw(t), Q(t,i)*e_price(t)) =E= rev;

$ifThenI %QFORM%==ineq
Equations HeatHourCvx(t,i), HeatHourNcv(t,i);
HeatFunction     ..  sum((t,i)$tw(t), hc(t,i)) =E= heatCost;
HeatHourCvx(t,i)$(tw(t) and A(i) >= 0)..
                     hc(t,i) =G= F(i)*(A(i)*Q(t,i)*Q(t,i) + B(i)*Q(t,i) + C(i)*u(t,i));
HeatHourNcv(t,i)$(tw(t) and A(i) < 0)..
                     hc(t,i) =E= F(i)*(A(i)*Q(t,i)*Q(t,i) + B(i)*Q(t,i) + C(i)*u(t,i));
$else
HeatFunction     ..  sum((t,i)$tw(t), F(i)*(A(i)*Q(t,i)*Q(t,i) + B(i)*Q(t,i) + C(i)*u(t,i))) =E= heatCost;
$endIf

FCost            ..  sum((t,i)$tw(t), SC(i)*sUP(t,i)) =E= fixCost;
Objective        ..  rev - heatCost - fixCost =E= OBJ;

* lagged terms at the window start refer to fixed hours of the previous window
RampUpE(t,i)$tw(t)..     Q(t,i) - Q(t-1,i) =L= StartRampUp(i)*sUP(t,i) + RampUp(i)*u(t-1,i);
RampDownE(t,i)$tw(t)..   Q(t-1,i) - Q(t,i) =L= CloseRampDown(i)*sDOWN(t,i) + RampDown(i)*u(t,i);
UandS(t,i)$tw(t)..       u(t,i) - u(t-1,i) =E= sUP(t,i) - sDOWN(t,i);
OpenAndClose(t,i)$tw(t)..  sUP(t,i) + sDOWN(t,i) =L= 1;

* same as the PWL models (sum from t to t+Lup-1 / t+Ldown-1), written also
* for the history hours so that earlier start-ups and shut-downs are respected
MinOpen(t,i)$act(t)..   sUP(t,i)   + sum(h$(act(h) and ord(h) ge ord(t) and ord(h) le ord(t)+Lup(i)-1),   sDOWN(h,i)) =L= 1;
MinClose(t,i)$act(t)..  sDOWN(t,i) + sum(h$(act(h) and ord(h) ge ord(t) and ord(h) le ord(t)+Ldown(i)-1), sUP(h,i))   =L= 1;

Avaliable(t,i)$tw(t)..   u(t,i) =L= 1 - M(t,i);
CapacityMin(t,i)$tw(t).. Qmin(t,i)*u(t,i) =L= Q(t,i);
CapacityMax(t,i)$tw(t).. Q(t,i) =L= Qmax(t,i)*u(t,i);

MODEL RHQ / all /;
RHQ.reslim    = %WRESLIM%;
RHQ.iterlim   = 500000000;
RHQ.nodlim    = 10000000;
RHQ.solvelink = 5;
option mip = gurobi, qcp = gurobi, miqcp = gurobi, optcr = %OPTCR%;

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

   solve RHQ using miqcp maximizing OBJ;

   winStart(wnd)     = wStart;
   winCommitEnd(wnd) = cEnd;
   winEnd(wnd)       = wEnd;
   winStat(wnd)      = RHQ.modelstat;
   winObj(wnd)       = OBJ.l;
   winTime(wnd)      = RHQ.resusd;
   winGap(wnd)       = abs(RHQ.objest - RHQ.objval) / max(1e-9, abs(RHQ.objval));

*  1 optimal, 2 locally optimal, 7 feasible solution (nonconvex model stopped
*  at a limit), 8 integer solution (MIP stopped at a limit)
   abort$(RHQ.modelstat <> 1 and RHQ.modelstat <> 2 and RHQ.modelstat <> 7 and RHQ.modelstat <> 8)
         'window not solved to a feasible solution', wStart, winStat;

   u.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)     = round(u.l(t,i));
   sUP.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)   = round(sUP.l(t,i));
   sDOWN.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd) = round(sDOWN.l(t,i));
   Q.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)     = Q.l(t,i);
$ifThenI %QFORM%==ineq
   hc.fx(t,i)$(ord(t) >= wStart and ord(t) <= cEnd)    = hc.l(t,i);
$endIf
);

*-------------------------------------------------------------------------------
* Full-year evaluation of the stitched schedule
*-------------------------------------------------------------------------------
Parameters gasUse(t,i) hourly gas use (MMBtu);
Scalars revTot, heatTot, startCost, nStarts, gasTot, gasPeak, hoursOn,
        profit, totTime, maxGap, nOptimal, nTimeLimit;

gasUse(t,i) = A(i)*sqr(Q.l(t,i)) + B(i)*Q.l(t,i) + C(i)*u.l(t,i);
revTot      = sum((t,i), e_price(t)*Q.l(t,i));
heatTot     = sum((t,i), F(i)*gasUse(t,i));
startCost   = sum((t,i), SC(i)*sUP.l(t,i));
nStarts     = sum((t,i), sUP.l(t,i));
gasTot      = sum((t,i), gasUse(t,i));
gasPeak     = smax(t, sum(i, gasUse(t,i)));
hoursOn     = sum((t,i), u.l(t,i));
profit      = revTot - heatTot - startCost;
totTime     = sum(wnd, winTime(wnd));
maxGap      = smax(wnd$(ord(wnd) <= nW), winGap(wnd));
nOptimal    = sum(wnd$(ord(wnd) <= nW and winStat(wnd) = 1), 1);
nTimeLimit  = sum(wnd$(ord(wnd) <= nW and (winStat(wnd) = 7 or winStat(wnd) = 8)), 1);

display nW, profit, revTot, heatTot, startCost, nStarts, gasTot, gasPeak, hoursOn,
        totTime, maxGap, nOptimal, nTimeLimit;

execute_unload '%OUT%_out.gdx', Q, u, sUP, sDOWN, gasUse, winStart, winEnd,
               winStat, winObj, winGap, winTime;

FILE csv / %OUT%_report.csv /;
csv.pc = 5;
put csv;
put 'COMMIT', commitLen / 'LOOK', lookLen / 'QFORM', '%QFORM%' / 'GasPrice', smax(i, F(i)) / 'Windows', nW /;
put 'Profit', profit / 'BestBoundLastWindow', RHQ.objest:0:2 / 'Revenue', revTot / 'HeatCost', heatTot / 'StartCost', startCost /;
put 'Starts', nStarts / 'HoursOn', hoursOn / 'GasTotal_MMBtu', gasTot / 'GasPeak_MMBtu_h', gasPeak /;
put 'SolverTime_s', totTime / 'MaxWindowGap', maxGap:0:8 / 'WindowsOptimal', nOptimal / 'WindowsTimeLimit', nTimeLimit /;
put / 'window', 'start', 'commitEnd', 'end', 'status', 'objective', 'gap', 'time_s' /;
loop(wnd$(ord(wnd) <= nW),
   put wnd.tl, winStart(wnd), winCommitEnd(wnd), winEnd(wnd), winStat(wnd), winObj(wnd), winGap(wnd):0:8, winTime(wnd) /;
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
put 'out', 'COMMIT', 'LOOK', 'QFORM', 'F', 'windows', 'profit', 'starts', 'hoursOn',
    'gasTotal', 'gasPeak', 'solverTime_s', 'maxGap', 'windowsOptimal', 'windowsTimeLimit' /;
$endIf
put '%OUT%', commitLen, lookLen, '%QFORM%', smax(i, F(i)), nW, profit, nStarts, hoursOn,
    gasTot, gasPeak, totTime, maxGap:0:8, nOptimal, nTimeLimit /;
putclose sumf;
