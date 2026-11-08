$title PBUC of a gas-fired unit (PWL) with planned maintenance and forced outages
$onText
Extension of pbuc_pwl.gms. The unavailability M_t is built from
  1. M in the parameter file,
  2. one planned maintenance period of PMDUR hours,
       --PM=none|auto|<start hour>  auto: the PMDUR-hour interval starting at
       midnight with the lowest mean electricity price,
  3. forced outages from a two-state Markov model with exponentially
     distributed times to failure and repair,
       --FOR=<forced outage rate> --MTTR=<mean time to repair, h> --SEED=<n>,
       MTTF = MTTR (1 - FOR) / FOR; failure times in calendar hours.
A forced outage is a trip: in its first hour the shut-down ramp limit and the
minimum up time do not apply.

Horizon
  The year (8,784 hours) is solved as a sequence of windows. Each window has a
  commitment block of COMMIT hours and a look-ahead of LOOK hours; only the
  decisions in the block are fixed, and the next window starts after it. The
  last max(Lup, Ldown) hours of the preceding blocks stay in the model as fixed
  variables, so ramp limits and minimum up and down times are enforced across
  windows.
    --COMMIT=8784 --LOOK=0   full-year model (one window)
    --LOOK=0                 myopic planning (no look-ahead)

Information on forced outages (--INFO)
  full   : all outages are known in every window.
  reveal : an outage, including its duration, becomes known in its first hour;
           the current block ends before it and a new window starts at the
           outage hour. With --COMMIT=8784 --LOOK=8784 this is full-year
           re-planning after each outage.
A maintenance period that starts within NOTICE hours after the end of a block
is included in the window.

Block boundaries
  --OFFSET=<h>  boundaries at hours OFFSET + k COMMIT (0: blocks start at midnight)
  --ALIGN=no    after an outage, blocks start at the outage hour
  --ALIGN=yes   after an outage, the block ends at the next regular boundary

Options (defaults in brackets): as pbuc_pwl.gms, and
  --PM=none|auto|<h> [none]  --PMDUR=<h> [336]  --NOTICE=<h> [168]
  --FOR=<rate> [0]  --MTTR=<h> [48]  --SEED=<n> [1]  --INFO=full|reveal [full]
  --OFFSET=<h> [0]  --ALIGN=no|yes [no]  --SUM=<summary file> [rh_outage_summary.csv]
$offText

$if not set XLS     $set XLS     ..\data\params_unitA.xlsx
$if not set IDX     $set IDX     index
$if not set COMMIT  $set COMMIT  168
$if not set LOOK    $set LOOK    48
$if not set NSEG    $set NSEG    10
$if not set FIL     $set FIL     calc
$if not set WRESLIM $set WRESLIM 3600
$if not set OPTCR   $set OPTCR   0
$if not set SEQ     $set SEQ     all
$if not set PM      $set PM      none
$if not set PMDUR   $set PMDUR   336
$if not set FOR     $set FOR     0
$if not set MTTR    $set MTTR    48
$if not set SEED    $set SEED    1
$if not set INFO    $set INFO    full
$if not set NOTICE  $set NOTICE  168
$if not set OFFSET  $set OFFSET  0
$if not set ALIGN   $set ALIGN   no
$if not set OUT     $set OUT     out_c%COMMIT%_l%LOOK%_%INFO%_s%SEED%
$if not set SUM     $set SUM     rh_outage_summary.csv

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
         wnd             rolling-horizon windows         / w1*w20000 /
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
* Unavailability: M from the parameter file + planned maintenance + forced outages
*-------------------------------------------------------------------------------
Parameters
   Mpl(t,i)     planned unavailability (M from the parameter file and maintenance)
   Mfo(t,i)     forced outage hours
   tripS(t,i)   1 in the first hour of a forced outage
   fsOrd(t,i)   first hour (ord) of the forced outage that covers hour t
   pS(t,i)      1 in the first hour of a planned outage
   Mtot(t,i)    all unavailability
   Mvis(t,i)    unavailability known in the current window
   tripV(t,i)   forced-outage start known in the current window
   avgP(t)      average price of a maintenance window starting at t;
Set cand(t) candidate maintenance start hours;
Scalars pmStart / 0 /, pmDur / %PMDUR% /, minP, FORr / %FOR% /, MTTRh / %MTTR% /,
        MTTF, pos, dur, nForced / 0 /, bigQ;

Mpl(t,i) = M(t,i);
$ifThenI %PM%==auto
cand(t)  = yes$(mod(ord(t) - 1, 24) = 0 and ord(t) + pmDur - 1 <= Tn);
avgP(t)$cand(t) = sum(h$(ord(h) >= ord(t) and ord(h) <= ord(t) + pmDur - 1), e_price(h)) / pmDur;
minP     = smin(t$cand(t), avgP(t));
pmStart  = smin(t$(cand(t) and avgP(t) = minP), ord(t));
$elseIfI not %PM%==none
pmStart  = %PM%;
$endIf
Mpl(t,i)$(pmStart > 0 and ord(t) >= pmStart and ord(t) < pmStart + pmDur) = 1;

Mfo(t,i) = 0;  tripS(t,i) = 0;  fsOrd(t,i) = 0;
execseed = %SEED%;
if(FORr > 0,
   MTTF = MTTRh*(1 - FORr)/FORr;
   pos  = 1 + max(1, round(-MTTF*log(uniform(1e-9, 1))));
   while(pos <= Tn,
      dur = max(1, round(-MTTRh*log(uniform(1e-9, 1))));
      Mfo(t,i)$(ord(t) >= pos and ord(t) < pos + dur)   = 1;
      fsOrd(t,i)$(ord(t) >= pos and ord(t) < pos + dur) = pos;
      tripS(t,i)$(ord(t) = pos) = 1;
      nForced = nForced + 1;
      pos = pos + dur + max(1, round(-MTTF*log(uniform(1e-9, 1))));
   );
);
Mtot(t,i) = max(Mpl(t,i), Mfo(t,i));
pS(t,i)   = 1$(Mpl(t,i) = 1 and Mpl(t-1,i) = 0);
bigQ      = smax((t,i), Qmax(t,i));

Scalars hoursPlanned, hoursForced;
hoursPlanned = sum((t,i), Mpl(t,i));
hoursForced  = sum((t,i), Mfo(t,i)*(1 - Mpl(t,i)));
display pmStart, nForced, hoursPlanned, hoursForced;
Mvis(t,i) = Mtot(t,i);  tripV(t,i) = tripS(t,i);

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
* a known forced-outage start (trip) lifts the ramp-down limit in that hour
RampDownE(t,i)$tw(t)..   Q(t-1,i) - Q(t,i) =L= CloseRampDown(i)*sDOWN(t,i) + RampDown(i)*u(t,i) + bigQ*tripV(t,i);
UandS(t,i)$tw(t)..       u(t,i) - u(t-1,i) =E= sUP(t,i) - sDOWN(t,i);
OpenAndClose(t,i)$tw(t)..  sUP(t,i) + sDOWN(t,i) =L= 1;

* written also for the history hours, so that a start-up / shut-down in the
* previous window still restricts the first hours of the current window
* a shut-down caused by a known trip does not violate the minimum up time
MinOpen(t,i)$act(t)..   sUP(t,i)   + sum(h$(act(h) and ord(h) ge ord(t) and ord(h) le ord(t)+Lup(i)-1),   sDOWN(h,i)*(1 - tripV(h,i))) =L= 1;
MinClose(t,i)$act(t)..  sDOWN(t,i) + sum(h$(act(h) and ord(h) ge ord(t) and ord(h) le ord(t)+Ldown(i)-1), sUP(h,i))   =L= 1;

Avaliable(t,i)$tw(t)..   u(t,i) =L= 1 - Mvis(t,i);
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

Scalars nextTrip, nCand, nUsed / 0 /, offsetH / %OFFSET% /;
abort$(offsetH < 0 or offsetH >= commitLen) 'OFFSET must be between 0 and COMMIT-1';
wStart = 1;
loop(wnd,
 if(wStart <= Tn,
$ifThenI %ALIGN%==yes
*  end the block at the next regular boundary (hours OFFSET + k*COMMIT)
   cEnd   = min(Tn, wStart - 1 + commitLen
                    - mod(wStart - 1 - offsetH + commitLen*ceil((offsetH + 1)/commitLen + 1), commitLen));
$else
   cEnd   = min(Tn, wStart + commitLen - 1);
*  the first block is shortened so that later boundaries fall at OFFSET + k*COMMIT
   if(nUsed = 0 and offsetH > 0, cEnd = min(Tn, offsetH));
$endIf

*  information available in this window
$ifThenI %INFO%==reveal
*  a forced outage is known once it has started (its duration is then known)
   Mvis(t,i)  = max(Mpl(t,i), Mfo(t,i)$(fsOrd(t,i) > 0 and fsOrd(t,i) <= wStart));
   tripV(t,i) = tripS(t,i)$(ord(t) <= wStart);
*  cut the block before the next (still unknown) forced outage
   nCand = sum(t$(ord(t) > wStart and ord(t) <= cEnd and sum(i, tripS(t,i))), 1);
   if(nCand > 0,
      nextTrip = smin(t$(ord(t) > wStart and ord(t) <= cEnd and sum(i, tripS(t,i))), ord(t));
      cEnd = nextTrip - 1;
   );
$else
   Mvis(t,i)  = Mtot(t,i);
   tripV(t,i) = tripS(t,i);
$endIf
*  past hours keep their realized status
   Mvis(t,i)$(ord(t) < wStart) = Mtot(t,i);

   wEnd   = min(Tn, cEnd + lookLen);
*  planned maintenance starting within NOTICE hours is always visible
   nCand = sum(t$(ord(t) > wEnd and ord(t) <= min(Tn, cEnd + %NOTICE%) and sum(i, pS(t,i))), 1);
   if(nCand > 0,
      wEnd = max(wEnd, smax(t$(ord(t) > wEnd and ord(t) <= min(Tn, cEnd + %NOTICE%) and sum(i, pS(t,i))), ord(t)));
   );

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

   nUsed  = nUsed + 1;
   wStart = cEnd + 1;
 );
);
abort$(wStart <= Tn) 'not all hours were scheduled: enlarge set wnd';
nW = nUsed;
* the stitched schedule must respect every outage
abort$(sum((t,i), u.l(t,i)*Mtot(t,i)) > 0.5) 'unit online during an outage hour';

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
put 'INFO', '%INFO%' / 'SEED', %SEED% / 'FOR', FORr / 'MTTR', MTTRh / 'pmStart', pmStart / 'nForced', nForced / 'hoursPlanned', hoursPlanned / 'hoursForced', hoursForced /
put 'COMMIT', commitLen / 'SEQ', '%SEQ%' / 'GasPrice', smax(i, F(i)) / 'LOOK', lookLen / 'NSEG', card(l) / 'Windows', nW /;
put 'ProfitPWL', profitPWL / 'ProfitExact', profitExact / 'Revenue', revTot /;
put 'HeatCostPWL', heatPWL / 'HeatCostExact', heatExact / 'StartCost', startCost /;
put 'Starts', nStarts / 'HoursOn', hoursOn / 'GasTotal_MMBtu', gasTot / 'GasPeak_MMBtu_h', gasPeak /;
put 'SolverTime_s', totTime / 'MaxWindowGap', maxGap / 'WindowsOptimal', nOptimal /;
put / 'window', 'start', 'commitEnd', 'end', 'status', 'objective', 'gap', 'time_s' /;
loop(wnd$(ord(wnd) <= nW),
   put wnd.tl, winStart(wnd), winCommitEnd(wnd), winEnd(wnd), winStat(wnd), winObj(wnd), winGap(wnd), winTime(wnd) /;
);
put / 'hour', 'Q', 'u', 'sUP', 'sDOWN', 'gas_MMBtu', 'price', 'M_planned', 'M_forced' /;
loop(t,
   put t.tl, Q.l(t,'G1'), u.l(t,'G1'), sUP.l(t,'G1'), sDOWN.l(t,'G1'), gasUse(t,'G1'), e_price(t), Mpl(t,'G1'), Mfo(t,'G1') /;
);
putclose csv;

FILE sumf / %SUM% /;
sumf.pc = 5;
sumf.ap = 1;
put sumf;
$ifThen %WRITEHDR%==1
put 'out', 'COMMIT', 'LOOK', 'INFO', 'SEED', 'FOR', 'MTTR', 'PM', 'pmStart', 'pmDur', 'nForced',
    'hoursPlanned', 'hoursForced', 'F', 'windows', 'profitPWL', 'profitExact', 'starts',
    'hoursOn', 'gasTotal', 'gasPeak', 'solverTime_s', 'maxGap', 'windowsOptimal', 'OFFSET', 'ALIGN' /;
$endIf
put '%OUT%', commitLen, lookLen, '%INFO%', %SEED%, FORr, MTTRh, '%PM%', pmStart, pmDur, nForced,
    hoursPlanned, hoursForced, smax(i, F(i)), nW, profitPWL, profitExact, nStarts,
    hoursOn, gasTot, gasPeak, totTime, maxGap, nOptimal, offsetH, '%ALIGN%' /;
putclose sumf;
