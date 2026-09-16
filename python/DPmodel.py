#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Dynamic programming (DP) solution of the annual profit-based unit commitment
(PBUC) problem for a single price-taking natural gas-fired generating unit.

This script implements the state-dependent DP framework described in Section 3.3
of the accompanying paper, "Solving Large-Scale Annual Profit-Based Unit
Commitment Problems for Price-Taking Natural Gas Power Plants".

Model summary
-------------
State       (s, q_prev), a two-dimensional state where
              * s      : operating-duration counter. s >= 1 means the unit has
                         been online for s consecutive hours, s <= -1 means it
                         has been offline for |s| consecutive hours, and s = 0
                         is the initial state, which exists at t = 1 only.
              * q_prev : power output dispatched in the previous hour (MW).
                         q_prev = 0 whenever the unit is offline.
Actions     "stay_off", "start", "stay_on", "shut_down". The selected action also
            fixes the dispatch level q_t of the current hour, so the dispatch
            decision is embedded directly in the state space instead of being
            delegated to a separate economic-dispatch step.
Reward      e_t * q - F * (A * q^2 + B * q + C) for an online hour, minus the
            start-up cost in the hour of synchronisation. The exact quadratic
            heat-rate function is preserved, i.e. no linearisation is applied.
Recursion   Backward Bellman recursion from t = T down to t = 1 with a terminal
            value of zero, V_{T+1} = 0.
Constraints Minimum up/down times (L_up, L_down), ramp-up/ramp-down limits for
            continued operation (ramp_up, ramp_down) and the start-up/shut-down
            ramp limits (startup_ramp, shutdown_ramp) are all enforced inside the
            state transitions.

Inputs
------
data/2024_Price.csv            Hourly market clearing prices in USD/MWh
                               (Turkish day-ahead market, 2024).
data/generator_params1.xlsx    Technical and economic parameters of the unit.

Outputs
-------
results/results1.csv                   Hourly schedule plus the total profit.
results/policy_store/policy_t_*.pkl    Per-stage optimal policy, written to disk
                                       so that peak memory use stays bounded over
                                       the full 8,784-hour horizon.

Notes
-----
The dispatch domain is discretised with a uniform step q_step (delta_q in the
paper). A smaller step yields a finer dispatch representation at the cost of a
substantially longer run time.

Created on Thu Dec 18 16:20:37 2025

@author: seymakaya
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Dict, Tuple, List
import pandas as pd
import time

import pickle
import os


# ---------------------------------------------------------------------------
# Repository paths (input/output wiring only, no model logic depends on this
# block). Paths are resolved relative to this file, so the script can be run
# from any working directory, e.g. "python python/DPmodel.py" from the repo root.
# ---------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))       # .../python
REPO_DIR = os.path.dirname(BASE_DIR)                        # repository root
DATA_DIR = os.path.join(REPO_DIR, "data")                   # input data files
RESULTS_DIR = os.path.join(REPO_DIR, "results")             # output files
POLICY_DIR = os.path.join(RESULTS_DIR, "policy_store")      # per-stage policies

PRICE_FILE = os.path.join(DATA_DIR, "2024_Price.csv")
PARAM_FILE = os.path.join(DATA_DIR, "generator_params1.xlsx")
RESULT_FILE = os.path.join(RESULTS_DIR, "results1.csv")

os.makedirs(RESULTS_DIR, exist_ok=True)
os.makedirs(POLICY_DIR, exist_ok=True)


@dataclass(frozen=True)
class UCParams:
    """Technical and economic parameters of a single generating unit.

    A, B, C        Quadratic, linear and no-load coefficients of the heat-rate
                   function ($/MW^2, $/MWh, $/h).
    F              Fuel (natural gas) price of the unit ($/MMBtu).
    startup_cost   Start-up cost charged in the hour of synchronisation ($).
    idle_cost      Cost charged per offline hour ($); zero in the reported runs.
    L_up, L_down   Minimum up and minimum down times (hours).
    q_min, q_max   Minimum and maximum power output when online (MW).
    ramp_up        Ramp-up limit while the unit stays online, ON -> ON (MW/h).
    ramp_down      Ramp-down limit while the unit stays online, ON -> ON (MW/h).
    startup_ramp   Start-up ramp limit, OFF -> ON (MW/h).
    shutdown_ramp  Shut-down ramp limit, ON -> OFF (MW/h).
    q_step         Discretisation step of the dispatch grid, delta_q (MW).
    """

    A: float; B: float; C: float; F: float
    startup_cost: float
    idle_cost: float = 0.0
    L_up: int = 1
    L_down: int = 1
    q_min: float = 0.0
    q_max: float = 1.0

    ramp_up: float = 1.0        # ON->ON
    ramp_down: float = 1.0      # ON->ON

    # These will be set to q_min by construction (Solution A)
    startup_ramp: float = 0.0   # OFF->ON (SU)
    shutdown_ramp: float = 0.0  # ON->OFF (SD)

    q_step: float = 1.0


@dataclass
class Decision2D:
    """Optimal decision stored for one state at one stage of the recursion.

    action   One of "stay_off", "start", "stay_on", "shut_down".
    q        Dispatch level selected for the current hour (MW).
    next_s   Operating-duration counter of the successor state.
    next_q   Previous-hour output of the successor state (MW).
    """

    action: str          # "stay_off", "start", "stay_on", "shut_down"
    q: float
    next_s: int
    next_q: float

def _profit_on(e_t: float, q: float, p: UCParams) -> float:
    """Single-hour profit of an online unit: revenue minus exact quadratic fuel cost."""
    return e_t * q - p.F * (p.A * q*q + p.B * q + p.C)

def _valid_s(t: int) -> List[int]:
    """Operating-duration counters that can be reached at stage t.

    At t = 1 the unit is in the initial state s = 0. From t = 2 onwards, at most
    t - 1 consecutive online or offline hours can have accumulated, so s ranges
    over -(t-1)..-1 (offline) and 1..t-1 (online).
    """
    # IP2.4: s=0 only at the start (t=1).
    if t == 1:
        return [0]
    k = t - 1
    return list(range(-k, 0)) + list(range(1, k + 1))

def _build_q_grid(p: UCParams) -> List[float]:
    """Build the discretised dispatch grid over [q_min, q_max] with step q_step.

    The grid is used for online hours only (an offline hour always has q = 0).
    q_max is appended explicitly when it is not hit exactly by the step size.
    """
    # ON grid (OFF is always q=0)
    on_grid: List[float] = []
    q = p.q_min
    while q <= p.q_max + 1e-12:
        on_grid.append(round(q, 12))
        q += p.q_step
    if not on_grid:
        return []
    if abs(on_grid[-1] - p.q_max) > 1e-9:
        on_grid.append(p.q_max)
    return on_grid

def _best_q_with_future(e_t, p, grid, lo, hi, next_s, getV):
    """Pick the dispatch level that maximises current profit plus future value.

    Only grid points inside the feasible ramp window [lo, hi] are evaluated. The
    objective is the immediate profit plus the value of the successor state
    (next_s, q), which is what couples the dispatch choice to the remaining
    horizon. Returns (best_q, its immediate profit, its total value), or None
    when no grid point is feasible.
    """
    best_q = None
    best_total = float("-inf")
    best_prof = float("-inf")

    for q in grid:
        if lo - 1e-12 <= q <= hi + 1e-12:
            prof = _profit_on(e_t, q, p)
            total = prof + getV(next_s, q)   # <-- the key difference: future value included
            if total > best_total:
                best_total = total
                best_q = q
                best_prof = prof

    if best_q is None:
        return None
    return best_q, best_prof, best_total








def solve_single_unit_uc_dp_with_susd(prices: List[float],p: UCParams,) -> Tuple[float, List[Tuple[int, int, float, str, float, float]]]:
    """
    State = (s, q_prev)
      - if s <= 0 => q_prev = 0
      - if s >= 1 => q_prev in on_grid (>= q_min)

    Ramps:
      - stay_on:  q_t in [q_prev - RD, q_prev + RU]
      - start:    q_t in [q_min, min(q_max, SU)]
      - shut_down allowed only if q_prev <= SD  (since q_t=0)

    Returns
    -------
    total : float
        Total profit of the optimal schedule over the horizon ($).
    schedule : list of tuples
        One row per hour: (t, s, q_prev, action, q_t, period_profit).
    """
    T = len(prices)
    on_grid = _build_q_grid(p)
    if p.q_min > 0 and not on_grid:
        raise ValueError("q_grid empty. Check q_min/q_max/q_step.")

    # Terminal V_{T+1} = 0
    V_next: Dict[Tuple[int, float], float] = {}
    for s in range(-T, 1):
        V_next[(s, 0.0)] = 0.0
    for s in range(1, T + 1):
        for q in on_grid:
            V_next[(s, q)] = 0.0

    

    def getV(s: int, q: float) -> float:
        """Value of state (s, q) at the next stage; -inf marks an unreachable state."""
        return V_next.get((s, q), float("-inf"))

    # Backward: t = T..2
    for t in range(T, 1, -1):
        print("T", t)   # progress indicator: backward stage currently being solved
        e_t = prices[t - 1]
        V_curr: Dict[Tuple[int, float], float] = {}
        
        policy_t: Dict[Tuple[int, int, float], Decision2D] = {}
    
        
        
        
        

        for s in _valid_s(t):
            if s < 0:
                # ---- OFF states: the unit has been offline for |s| hours ----
                q_prev = 0.0

                if s <= -p.L_down:
                    # Minimum down time satisfied: both staying off and starting up
                    # are feasible, so the two alternatives are compared.
                    # stay_off
                    stay_val = (-p.idle_cost) + getV(s - 1, 0.0)

                    # start with SU bound (OFF->ON)
                    lo = p.q_min
                    hi = min(p.q_max, p.startup_ramp)
                    best = _best_q_with_future(e_t, p, on_grid, lo, hi, next_s=1, getV=getV)
                    
                    if best is None:
                        start_val = float("-inf")
                    else:
                        q_t, prof, total = best
                        start_val = total - p.startup_cost   # (prof + future) - SC
                    
                    
                    if start_val >= stay_val:
                        V_curr[(s, q_prev)] = start_val
                        policy_t[(t, s, q_prev)] = Decision2D("start", q_t, 1, q_t)
                    else:
                        V_curr[(s, q_prev)] = stay_val
                        policy_t[(t, s, q_prev)] = Decision2D("stay_off", 0.0, s - 1, 0.0)
                else:
                    # Minimum down time not yet elapsed: the unit must remain offline.
                    # forced stay_off
                    val = (-p.idle_cost) + getV(s - 1, 0.0)
                    V_curr[(s, q_prev)] = val
                    policy_t[(t, s, q_prev)] = Decision2D("stay_off", 0.0, s - 1, 0.0)

            else:
                # ON states
                for q_prev in on_grid:
                    if s >= p.L_up:
                        # Minimum up time satisfied: staying online and shutting
                        # down are compared against each other.
                        # stay_on with RU/RD bounds (ON->ON)
                        lo = max(p.q_min, q_prev - p.ramp_down)
                        hi = min(p.q_max, q_prev + p.ramp_up)
                        
                        best_on = _best_q_with_future(e_t, p, on_grid, lo, hi, next_s=s+1, getV=getV)
                        if best_on is None:
                            stay_val = float("-inf")
                            stay_q = None
                        else:
                            q_t, prof, total = best_on
                            stay_q = q_t
                            stay_val = total  # profit + future

                        # shut_down with SD feasibility (ON->OFF)
                        shutdown_limit = max(p.shutdown_ramp, p.ramp_down)  # allow earlier shutdown if RD permits
                        if q_prev <= shutdown_limit + 1e-12:
                            shut_val = (-p.idle_cost) + getV(-1, 0.0)
                        else:
                            shut_val = float("-inf")

                        if stay_val >= shut_val:
                            V_curr[(s, q_prev)] = stay_val
                            policy_t[(t, s, q_prev)] = Decision2D("stay_on", float(stay_q), s + 1, float(stay_q))
                        else:
                            V_curr[(s, q_prev)] = shut_val
                            policy_t[(t, s, q_prev)] = Decision2D("shut_down", 0.0, -1, 0.0)
                    else:
                        # Minimum up time not yet elapsed: the unit must stay online
                        # and only the dispatch level is optimised.
                        # forced stay_on
                        lo = max(p.q_min, q_prev - p.ramp_down)
                        hi = min(p.q_max, q_prev + p.ramp_up)
                        
                        best_on = _best_q_with_future(e_t, p, on_grid, lo, hi, next_s=s+1, getV=getV)
                        if best_on is None:
                            val = float("-inf")
                        else:
                            q_t, prof, total = best_on
                            val = total  # profit + future
                            V_curr[(s, q_prev)] = val
                            policy_t[(t, s, q_prev)] = Decision2D("stay_on", q_t, s + 1, q_t)                    
                        
                        
                        
                        
                        
                        
        #V_next.update(V_curr)
        V_next = V_curr.copy()
        
        
        # Moving backwards from stage T: store the policy of this stage on disk.
        with open(os.path.join(POLICY_DIR, f"policy_t_{t}.pkl"), "wb") as f:
            pickle.dump(policy_t, f)
        
        # Release the policy from memory (essential for the full-year horizon).
        del policy_t


    # t=1 start state: only (0,0)
    e_1 = prices[0]
    #s0, q0 = 0, 0.0
    policy_t: Dict[Tuple[int, int, float], Decision2D] = {}

    stay_off_val = (-p.idle_cost) + getV(-1, 0.0)

    
    lo = p.q_min
    hi = min(p.q_max, p.startup_ramp)
    
    best = _best_q_with_future(e_1, p, on_grid, lo, hi, next_s=1, getV=getV)
    if best is None:
        start_val = float("-inf")
    else:
        q1, profit1, total = best
        start_val = (profit1 - p.startup_cost) + getV(1, q1)


    if start_val >= stay_off_val:
        policy_t[(1, 0, 0.0)] = Decision2D("start", q1, 1, q1)
    else:
        policy_t[(1, 0, 0.0)] = Decision2D("stay_off", 0.0, -1, 0.0)

    # Forward reconstruction
    # Walk forward from the initial state (s = 0, q_prev = 0), reading back the
    # stored policy of each stage to recover the schedule and its profit.
    schedule: List[Tuple[int, int, float, str, float, float]] = []
    total = 0.0
    s, q_prev = 0, 0.0

    for t in range(1, T + 1):
        
        
        if t>1:
            with open(os.path.join(POLICY_DIR, f"policy_t_{t}.pkl"), "rb") as f:
                policy_t = pickle.load(f)
            
            

        
        
        dec = policy_t[(t, s, q_prev)]
        e_t = prices[t - 1]

        if dec.action in ("start", "stay_on"):
            period_profit = _profit_on(e_t, dec.q, p)
            if dec.action == "start":
                period_profit -= p.startup_cost
        else:
            period_profit = -p.idle_cost

        schedule.append((t, s, q_prev, dec.action, dec.q, period_profit))
        total += period_profit
        s, q_prev = dec.next_s, dec.next_q

    return total, schedule



# --- Example
# Small illustrative instance: 10 hourly prices, used as a quick sanity check of
# the recursion. It runs only when the file is executed directly.
if __name__ == "__main__":
    prices = [50, -10, 6, 3, 1000, -1000, 3, -100, 10, 50]  # e_t

    params = UCParams(
        A=0.01, B=2.0, C=10.0, F=1.0,
        startup_cost=200.0,
        idle_cost=0.0,
        L_up=1, L_down=1,
        q_min=40.0, q_max=100.0,
        ramp_up=30.0, ramp_down=40.0,
        startup_ramp  = 40,
        shutdown_ramp = 40,

        q_step=10.0,
    )

    total, sched = solve_single_unit_uc_dp_with_susd(prices, params)
    print("Total Profit:", total)
    for row in sched:
        print(row)
        
        
        
##############################################
# Annual case study: read the 2024 hourly price series and the unit parameters,
# solve the DP over the selected horizon and write the resulting schedule.
##############################################



df = pd.read_csv(PRICE_FILE)
#print(df)
x = 8784  # number of rows to read: 8784 for the full year 2024, 2184 for the first three months
prices = df.iloc[:x, -1].astype(float).tolist()   # last column holds the hourly price (USD/MWh)
#print(prices)



# Parameter workbook layout: column A holds the parameter name, column B its value.
d = pd.read_excel(PARAM_FILE, header=None).set_index(0)[1].to_dict()

print(d)

params1 = UCParams(
    A=float(d["A"]), B=float(d["B"]), C=float(d["C"]), F=float(d["F"]),
    startup_cost=float(d["startup_cost"]),
    idle_cost=float(d["idle_cost"]),
    L_up=int(d["L_up"]), L_down=int(d["L_down"]),
    q_min=float(d["q_min"]), q_max=float(d["q_max"]),
    ramp_up=float(d["ramp_up"]), ramp_down=float(d["ramp_down"]),
    startup_ramp=float(d["startup_ramp"]), shutdown_ramp=float(d["shutdown_ramp"]),
    q_step=float(d["q_step"]),
)


#prices = [5000, -10, 6, 3, 1000, -1000, 3, -100, 10, 50]  # e_t

start_DP = time.time()    

total, sched = solve_single_unit_uc_dp_with_susd(prices, params1)
print("Total Profit:", total)
for row in sched:
    print(row)

df_sonuc = pd.DataFrame(sched, columns=["t", "s", "q_prev", "action", "q_t", "period_profit"])
df_sonuc["total_profit"] = total  # repeat the total profit on every row, if desired

df_sonuc.to_csv(RESULT_FILE, index=False)

stop_DP = time.time()
print("DP runtime: ", stop_DP-start_DP)       
        
        
        
