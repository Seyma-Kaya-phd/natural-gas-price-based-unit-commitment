* ===========================================================================
*  Annual Profit-Based Unit Commitment (PBUC) for a Price-Taking
*  Natural Gas-Fired Power Plant  --  PIECEWISE LINEAR MILP (GAMS / Gurobi)
* ---------------------------------------------------------------------------
*  Paper   : "Solving Large-Scale Annual Profit-Based Unit Commitment Problems
*             for Price-Taking Natural Gas Power Plants"
*  Model   : Section 3.2 of the paper, Eqs. (12)-(16). The quadratic fuel cost
*            of the exact MIQP is replaced by a sequentially filled piecewise
*            linear approximation, which turns the problem into a MILP that is
*            solved over the full 8,784-hour horizon of 2024.
*  Data    : an Excel workbook read through GDXXRW. Sheet "index" lists every
*            parameter and the cell range it is read from; sheet
*            "Linearization" holds the segment slopes f_il of Eq. (16).
*  Sample  : data/basic_linearization_sampledata.xlsx holds the parameters of
*            the literature benchmark unit (Unit A) as generator G1, the 2024
*            hourly market clearing price series and the slopes for L = 3.
*  Segments: the number of segments L is set by the set l below (/l1*l3/ for
*            L = 3, /l1*l10/ for L = 10). The slope table f_il in the
*            workbook and the range it is read from in sheet "index" have to
*            describe the same number of segments as the set l.
*  Requires: GAMS with a MIP solver (Gurobi was used for the results reported
*            in the paper) and GDXXRW, which needs Microsoft Excel.
*  Run     : gams basic_linearization.gms   (from the folder of this file)
*  Output  : the CSV report, the solution GDX and the solution workbook listed
*            in the configuration block below.
*
*  The model statements in this file are unchanged with respect to the version
*  used to produce the results reported in the paper. Only the file paths were
*  moved into the configuration block below, and the comments were written in
*  English.
* ===========================================================================

* ---------------------------------------------------------------------------
*  USER CONFIGURATION -- file locations
* ---------------------------------------------------------------------------
*  Paths are relative to the directory from which GAMS is started, which is
*  normally the folder containing this file. Windows separators are used, as
*  GDXXRW requires Microsoft Excel and therefore Windows.
*  XLS_FILE : input workbook with the hourly, generator and slope parameters
*  GDX_IN   : GDX container produced from XLS_FILE by GDXXRW
*  GDX_OUT  : GDX container of the solution
*  CSV_OUT  : text report written with PUT statements
*  XLS_OUT  : solution written back to Excel by GDXXRW
* ---------------------------------------------------------------------------
$setglobal XLS_FILE ..\data\basic_linearization_sampledata.xlsx
$setglobal GDX_IN   basic_linearization_sampledata.gdx
$setglobal GDX_OUT  ..\results\2024_parametersOUT.gdx
$setglobal CSV_OUT  ..\results\outputs_linearization.csv
$setglobal XLS_OUT  ..\results\2024_OUTPUT.xlsx

* ---------------------------------------------------------------------------
*  GDXXRW control file: the read instructions live in sheet "index", cell A1
* ---------------------------------------------------------------------------

$onecho > gdxxrw_index.txt
index=index!A1
$offecho

* Convert the workbook into a GDX container with GDXXRW and open that
* container so that the sets and parameters can be loaded from it.
$call gdxxrw.exe "%XLS_FILE%" O=%GDX_IN% @gdxxrw_index.txt
$gdxin %GDX_IN%

* ---------------------------------------------------------------------------
*  SETS
*    t : hourly periods of the planning horizon, loaded from the workbook
*    l : piecewise linear segments. /l1*l3/ corresponds to L = 3 in the paper;
*        replace it with /l1*l10/ for the L = 10 configuration and update the
*        slope table f_il in the workbook accordingly.
*    i : generating units. The sample workbook provides data for G1 only,
*        so the set is declared as / G1 /.
* ---------------------------------------------------------------------------
SETS
         t(*)            hourly time step
         l               linearization steps             /l1*l3/
         i               Generators                      / G1 /;

$load t
display t;

ALIAS (t,h);



*Scalar Ll /10/;


* ---------------------------------------------------------------------------
*  PARAMETERS (paper notation in brackets)
*    e_price(t)        market clearing price                        [e_t]
*    reserve(t), Q_D(t) upper bound used by the Demand equation below
*    M(t,i)            maintenance indicator, 1 = unit unavailable  [M_t,i]
*    F(i)              natural gas price                           [F_i]
*    A(i), B(i), C(i)  quadratic heat-rate coefficients        [A_i, B_i, C_i]
*    SC(i)             start-up cost                               [SC_i]
*    Lup(i), Ldown(i)  minimum up and down times           [L^up_i, L^down_i]
*    RampUp(i), RampDown(i)          ramp limits, online      [RU_i, RD_i]
*    StartRampUp(i), CloseRampDown(i) start-up / shut-down ramp limits
*                                                            [SRU_i, CRD_i]
*    Qmin(t,i), Qmax(t,i)            output limits     [Qmin_t,i, Qmax_t,i]
*    f_il(l,i)         marginal heat-rate slope of segment l        [S_i,l]
*    DeltaQ(t,i)       segment width, computed below            [Delta Q_i]
* ---------------------------------------------------------------------------
PARAMETERS

         e_price(t)              hourly electiric price at time t
         reserve(t)              reserve demand at time t
         M(t,i)                  avaliability of generator i at time t
         F(i)                    natural gas price for generator i
         A(i)                    heat function accelarator parameter for generator i
         B(i)                    heat function linear parameter for generator i
         C(i)                    heat function scalar parameter for generator i
         SC(i)                   Start up cost for generator i
         Lup(i)                  Minimum start time for generation i
         Ldown(i)                Minimum close time for generation i
         RampUp(i)               maximum electiric generation capacity of generator i
         StartRampUp(i)          electricity generation capacity increase-decrease rate for power plant i
         RampDown(i)             maximum electiric generation capacity of generator i
         CloseRampDown(i)        electricity generation capacity increase-decrease rate for power plant i
         Qmin(t,i)               minimum electiric production capacity of generator i at time t
         Qmax(t,i)               maximum electiric production capacity of generator i at time t
         Q_D(t)                  amount of electricity produced from the unit and transmitted to the free market at time t
         f_il(l,i)               linearization parameters
         DeltaQ(t,i)             width of one linearization segment (MW);

$load e_price reserve M F A B C SC Lup Ldown RampUp StartRampUp RampDown CloseRampDown Qmin Qmax Q_D f_il
$gdxin

* Uniform segment width Delta Q_i = (Qmax - Qmin) / L, used in Eqs. (13)-(15)
DeltaQ(t,i) = (Qmax(t,i) - Qmin(t,i)) /card(l);

display e_price, reserve, M, F, A, B, C, SC, Lup, Ldown, RampUp, StartRampUp, RampDown, CloseRampDown, Qmin, Qmax, Q_D, f_il, deltaQ;




* ---------------------------------------------------------------------------
*  VARIABLES
*    Q(t,i)      power output, continuous and non-negative         [Q_t,i]
*    delta(t,i,l) power dispatched in segment l                  [delta_t,i,l]
*    u(t,i)      commitment status, binary                        [u_t,i]
*    sUP(t,i), sDOWN(t,i) start-up and shut-down indicators, binary
*                                                       [s^up_t,i, s^down_t,i]
*    z(t,i,l)    sequential filling indicator, binary             [z_t,i,l]
*    rev, heatCost, fixCost, OBJ  accounting variables of the objective
* ---------------------------------------------------------------------------
variables

         Q(t,i)          amount of electiric generation by generator i at time t
*         X(t,i)          generator i starts to work at time t
         rev
         heatCost
         fixCost
         delta(t,i,l)
         OBJ;

Binary Variables
         sUP(t,i)        generator i opens at time t
         sDOWN(t,i)      generator i closes at time t
         u(t,i)          generator i open or close at time t
         z(t,i,l)        segment l must be filled before segment l+1 is used;



*binary variables sUP, sDOWN, u;
positive variable Q;

* ---------------------------------------------------------------------------
*  EQUATIONS and their counterparts in the paper
*    Revenue, HeatFunction, FCost, Objective   Eq. (1) with the fuel cost
*                                              replaced by the piecewise
*                                              linear expression of Eq. (16)
*    Production                                Eq. (12)
*    Delta_lower, Delta_upper                  Eq. (13)
*    Eq_SeqFill1                               Eq. (14)
*    Eq_SeqFill2                               Eq. (15)
*    CapacityMin, CapacityMax                  Eq. (2)
*    RampUpE                                   Eq. (3)
*    RampDownE                                 Eq. (4)
*    MinOpen                                   Eq. (5)
*    MinClose                                  Eq. (6)
*    UandS                                     Eq. (7)
*    OpenAndClose                              Eq. (8)
*    Avaliable                                 Eq. (9)
*    Demand                                    upper bound on hourly output.
*        It is not part of the price-taker formulation of the paper; with the
*        sample data (Q_D = 1000, reserve = 10000) it is not binding for the
*        case units and therefore does not restrict the solution.
* ---------------------------------------------------------------------------
Equations

         Objective               Profit Maximization
         Revenue                 Revenue
         HeatFunction            Heat Function Cost
         FCost                   Fix Cost
         RampUpE(t,i)            Ramp Up
         RampDownE(t,i)          Ramp Down
         UandS(t,i)              U and S
         OpenAndClose(t,i)       Open or Close
         MinOpen(t,i)            Working Time
         MinClose(t,i)           Closing Time
         Avaliable(t,i)          Generator Avaliability
         Demand(t)               Electiric Demand
         CapacityMin(t,i)        Min Production Capacity
         CapacityMax(t,i)        Max Production Capacity
         Delta_lower(t,i,l)      Lower bound of delta
         Delta_upper(t,i,l)      Upper bound of delta
         Eq_SeqFill1(t,i,l)      sequential filling rule 1 (segment l must be full)
         Eq_SeqFill2(t,i,l)      sequential filling rule 2 (blocks segment l+1)
         Production(t,i)         Production amount;
*         Demand2(t);


Revenue                  ..      sum(t, sum(i, Q(t,i)*e_price(t)))                                                                             =E=     rev;
*Revenue                  ..      sum(t, sum(i, e_price(t)*(Qmin(t,i)*u(t,i)+sum(l,delta(t,i,l)))))                                            =E=     rev;
*HeatFunction             ..      sum(t, sum(i, F(i)*(C(i)*u(t,i)+sum(l,f_il(l,i)*delta(t,i,l)))))                                             =E=     heatCost;
HeatFunction             ..      sum(t, sum(i, F(i)*((A(i)*Qmin(t,i)*Qmin(t,i)+B(i)*Qmin(t,i)+C(i))*u(t,i)+sum(l,f_il(l,i)*delta(t,i,l)))))    =E=     heatCost;
FCost                    ..      sum(t, sum(i, SC(i)*sUP(t,i)))                                                                                =E=     fixCost;
Objective                ..      rev - heatCost - fixCost                                                                                      =E=     OBJ;
Production(t,i)          ..      Q(t,i)                                                                                                        =E=     Qmin(t,i)*u(t,i)+ sum(l, delta(t,i,l));
Delta_lower(t,i,l)       ..      0                                                                                                             =L=     delta(t,i,l);
Delta_upper(t,i,l)       ..      delta(t,i,l)                                                                                                  =L=     ((Qmax(t,i)-Qmin(t,i))/card(l))*u(t,i);
Eq_SeqFill1(t,i,l)$(ord(l) < card(l))..      DeltaQ(t,i) * z(t,i,l)                                                                            =L= delta(t,i,l);
Eq_SeqFill2(t,i,l)$(ord(l) < card(l)).. delta(t,i,l+1) =L= DeltaQ(t,i) * z(t,i,l);                                                             
RampUpE(t,i)             ..      Q(t, i) - Q(t-1, i)                                                                                           =L=     StartRampUp(i)*sUP(t,i)+ RampUp(i)*u(t-1,i);
RampDownE(t,i)           ..      Q(t-1, i) - Q(t, i)                                                                                           =L=     CloseRampDown(i)*sDown(t,i)+ RampDown(i)*u(t,i);
UandS(t,i)               ..      u(t, i) - u(t-1, i)                                                                                           =E=     sUP(t, i) - sDOWN(t, i);
OpenAndClose(t,i)        ..      sUP(t, i) + sDOWN(t, i)                                                                                       =L=     1;
MinOpen(t,i)             ..      sUP(t,i) + sum(h$(ord(h) ge ord(t) and ord(h) le ord(t)+Lup(i)-1), sDOWN(h,i))                                  =L=     1;
MinClose(t,i)            ..      sDOWN(t,i) + sum(h$(ord(h) ge ord(t) and ord(h) le ord(t)+Ldown(i)-1), sUP(h,i))                                =L=     1;
Avaliable(t,i)           ..      u(t,i)                                                                                                        =L=     1-M(t,i);
Demand(t)                ..      sum(i, Q(t,i))                                                                                                =L=     Q_D(t) + reserve(t);
CapacityMin(t,i)         ..      Qmin(t,i)*u(t,i)                                                                                              =L=     Q(t,i);
CapacityMax(t,i)         ..      Q(t,i)                                                                                                        =L=     Qmax(t,i)*u(t,i);
*Demand2(t)                ..      sum(i, Q(t,i))                                                                                              =G=     1;











* ---------------------------------------------------------------------------
*  MODEL, SOLVER OPTIONS AND SOLVE
*  The linearized model is solved as a MIP. OPTCR = 0 requests a zero relative
*  optimality tolerance for the linearized problem; note that an optimal
*  solution of this MILP is not an optimality certificate for the original
*  quadratic problem (Section 3.2 of the paper).
* ---------------------------------------------------------------------------
MODEL NATURALGAS_OPTIMIZE "Natural Gas Optimization Program"                                                      /ALL/;

* Resource limit in seconds (about 55 hours), as imposed in the paper
NATURALGAS_OPTIMIZE.reslim  = 200000;
* Iteration limit
NATURALGAS_OPTIMIZE.iterlim = 100000000;
* Node limit
NATURALGAS_OPTIMIZE.nodlim  = 5000000;


OPTION OPTCR = 0;



*NATURALGAS_OPTIMIZE.memnodes = 200000;

*option memnodes = 200000;


*option iterlim = 1000000;
*option nlp=conopt3;

* Alternative solver set-up: CPLEX for the MIP part
*option mip   = cplex;
* CPLEX for the continuous QCP part as well
*option qcp   = cplex;
* and CPLEX for the MIQCP
*option miqcp = cplex;

* Solver set-up used for the reported results: Gurobi for the MIP part
option mip   = gurobi;
* Gurobi for the continuous QCP part as well
option qcp   = gurobi;
* and Gurobi for the MIQCP
option miqcp = gurobi;





***** --- Optional SBB option file: enlarge memnodes ---
*$onecho > sbb.opt
*****memnodes 50000
*$offecho

***** Let this model read the sbb.opt file
*NATURALGAS_OPTIMIZE.optfile = 1 ;

**** (or state it explicitly:
***** option miqcp = sbb ; )






SOLVE NATURALGAS_OPTIMIZE USING MIP MAXIMIZING OBJ;

*MIQCP



* ---------------------------------------------------------------------------
*  REPORTING: display the solution, unload it to GDX, write a CSV report and
*  push the variable levels back into an Excel workbook.
* ---------------------------------------------------------------------------
Display OBJ.L, rev.L, heatCost.L, fixCost.L, Q.L, u.L, sUP.L, sDOWN.L, delta.L;
display i;


*Scalar
*    q156_g2,
*    u156_g2,
*    qmin156_g2,
*    qmax156_g2;

*q156_g2    = Q.l('H156','G2');
*u156_g2    = u.l('H156','G2');
*qmin156_g2 = Qmin('H156','G2');
*qmax156_g2 = Qmax('H156','G2');

*display q156_g2, u156_g2, qmin156_g2, qmax156_g2;



display NATURALGAS_OPTIMIZE.modelstat, NATURALGAS_OPTIMIZE.solvestat;


execute_unload '%GDX_OUT%', Q.L, OBJ.L, sUP.L, sDOWN.L, u.L, rev.L, heatCost.L, fixCost.L, OBJ.L, t;

FILE csv Report File /%CSV_OUT%/;
csv.pc = 5;
PUT csv;



PUT 'ModelStatus'/;
PUT  NATURALGAS_OPTIMIZE.modelstat/;
PUT 'SolverStatus'/;
PUT  NATURALGAS_OPTIMIZE.solvestat/;
PUT 'NETREVENUE'/;
PUT  OBJ.L/;


PUT 'GENERATION'/;
PUT 'HOUR','G1'/;
LOOP((t),
         PUT t.TL, Q.L(t,"G1")/;
);




PUT 'S UP'/;
PUT 'HOUR','G1'/;
LOOP((t),
         PUT t.TL, sUP.L(t,"G1")/;
);

PUT 'S DOWN'/;
PUT 'HOUR','G1'/;
LOOP((t),
         PUT t.TL, sDOWN.L(t,"G1")/;
);


PUT 'U'/;
PUT 'HOUR','G1'/;
LOOP((t),
         PUT t.TL, u.L(t,"G1")/;
);


PUT 'REVENUE and COST'/;
PUT 'REVENUE'/;
PUT rev.L/;
PUT 'HEAT COST'/;
PUT heatCost.L/;
PUT 'FIX COST'/;
PUT fixCost.L/;
PUT 'NETREVENUE'/;
PUT  OBJ.L/;




*=== Now write to variable levels to Excel file from GDX
*=== Since we do not specify a sheet, data is placed in first sheet
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=Q.L rng=Generation!A2 rdim=2'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=sUP.L rng=sUP!A2 rdim=2'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=sDOWN.L rng=sDOWN!A2 rdim=2'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=u.L rng=u!A2 rdim=2'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=OBJ.L rng=GAMSOut!A2 rdim=0'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=rev.L rng=GAMSOut!B2 rdim=0'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=heatCost.L rng=GAMSOut!C2 rdim=0'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% var=fixCost.L rng=GAMSOut!D2 rdim=0'
execute 'gdxxrw.exe %GDX_OUT% O=%XLS_OUT% set=t rng=time!A2 rdim=1'



