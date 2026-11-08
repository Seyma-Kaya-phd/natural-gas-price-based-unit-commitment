#!/usr/bin/env python3
"""
Dynamic programming (DP) formulation of the single-unit profit-based unit
commitment problem (Section 3.3 of the paper).

State  : (tau, q_prev)
         tau > 0  number of consecutive hours online
         tau < 0  number of consecutive hours offline
         tau = 0  initial state in hour 1 (offline, start-up allowed)
         q_prev   output in the preceding hour (0 if offline)
Actions: stay_off, start, stay_on, shut_down
Output : hourly schedule and total profit; the decision rules of each stage
         are stored on disk during the backward pass and read during the
         forward reconstruction.

The fuel cost is evaluated exactly with the quadratic heat-rate function on
a discrete grid of output levels with step q_step (10 MW or 1 MW in the
paper). Only the base case without unavailability (M = 0) is supported.

Usage (from the models folder)
  python pbuc_dp.py --unit unitA --F 9 --qstep 10 --out dp_unitA_F9.csv
Options
  --unit    unit name in ../data/units.csv (unitA, samsun, gebze)
  --F       gas price (USD/MMBtu) [9]
  --qstep   output step of the grid (MW) [10]
  --hours   number of hours from 1 January 2024 [8784]
  --prices  price file [../data/prices_2024.csv]
  --units   unit file [../data/units.csv]
  --out     output file (hourly schedule) [dp_<unit>_F<F>.csv]
"""
from __future__ import annotations

import argparse
import os
import pickle
import shutil
import time
from dataclasses import dataclass
from typing import Dict, List, Tuple

import pandas as pd


@dataclass(frozen=True)
class UCParams:
    A: float
    B: float
    C: float
    F: float
    startup_cost: float
    idle_cost: float = 0.0
    L_up: int = 1
    L_down: int = 1
    q_min: float = 0.0
    q_max: float = 1.0
    ramp_up: float = 1.0          # online to online
    ramp_down: float = 1.0        # online to online
    startup_ramp: float = 0.0     # offline to online
    shutdown_ramp: float = 0.0    # online to offline
    q_step: float = 1.0


@dataclass
class Decision:
    action: str
    q: float
    next_s: int
    next_q: float


def profit_on(e_t: float, q: float, p: UCParams) -> float:
    return e_t * q - p.F * (p.A * q * q + p.B * q + p.C)


def valid_states(t: int) -> List[int]:
    if t == 1:
        return [0]
    k = t - 1
    return list(range(-k, 0)) + list(range(1, k + 1))


def output_grid(p: UCParams) -> List[float]:
    grid, q = [], p.q_min
    while q <= p.q_max + 1e-12:
        grid.append(round(q, 12))
        q += p.q_step
    if grid and abs(grid[-1] - p.q_max) > 1e-9:
        grid.append(p.q_max)
    return grid


def best_output(e_t, p, grid, lo, hi, next_s, value):
    best = None
    for q in grid:
        if lo - 1e-12 <= q <= hi + 1e-12:
            prof = profit_on(e_t, q, p)
            total = prof + value(next_s, q)
            if best is None or total > best[2]:
                best = (q, prof, total)
    return best


def solve(prices: List[float], p: UCParams, store: str = "policy_store"):
    os.makedirs(store, exist_ok=True)
    T = len(prices)
    grid = output_grid(p)
    V_next: Dict[Tuple[int, float], float] = {}
    for s in range(-T, 1):
        V_next[(s, 0.0)] = 0.0
    for s in range(1, T + 1):
        for q in grid:
            V_next[(s, q)] = 0.0

    def value(s, q):
        return V_next.get((s, q), float("-inf"))

    # backward pass, t = T..2
    for t in range(T, 1, -1):
        e_t = prices[t - 1]
        V: Dict[Tuple[int, float], float] = {}
        policy: Dict[Tuple[int, int, float], Decision] = {}
        for s in valid_states(t):
            if s < 0:
                stay = -p.idle_cost + value(s - 1, 0.0)
                if s <= -p.L_down:
                    b = best_output(e_t, p, grid, p.q_min, min(p.q_max, p.startup_ramp), 1, value)
                    start = float("-inf") if b is None else b[2] - p.startup_cost
                    if start >= stay:
                        V[(s, 0.0)] = start
                        policy[(t, s, 0.0)] = Decision("start", b[0], 1, b[0])
                        continue
                V[(s, 0.0)] = stay
                policy[(t, s, 0.0)] = Decision("stay_off", 0.0, s - 1, 0.0)
            else:
                for q_prev in grid:
                    lo = max(p.q_min, q_prev - p.ramp_down)
                    hi = min(p.q_max, q_prev + p.ramp_up)
                    b = best_output(e_t, p, grid, lo, hi, s + 1, value)
                    stay = float("-inf") if b is None else b[2]
                    shut = float("-inf")
                    # shut-down after the minimum up time, output in the
                    # preceding hour bounded by the shut-down ramp limit
                    if s >= p.L_up and q_prev <= p.shutdown_ramp + 1e-12:
                        shut = -p.idle_cost + value(-1, 0.0)
                    if b is None and shut == float("-inf"):
                        continue
                    if stay >= shut:
                        V[(s, q_prev)] = stay
                        policy[(t, s, q_prev)] = Decision("stay_on", b[0], s + 1, b[0])
                    else:
                        V[(s, q_prev)] = shut
                        policy[(t, s, q_prev)] = Decision("shut_down", 0.0, -1, 0.0)
        V_next = V
        with open(os.path.join(store, f"policy_t_{t}.pkl"), "wb") as fh:
            pickle.dump(policy, fh)
        del policy

    # hour 1: unit offline, start-up allowed
    e_1 = prices[0]
    stay = -p.idle_cost + value(-1, 0.0)
    b = best_output(e_1, p, grid, p.q_min, min(p.q_max, p.startup_ramp), 1, value)
    start = float("-inf") if b is None else b[2] - p.startup_cost
    policy = {(1, 0, 0.0): Decision("start", b[0], 1, b[0]) if start >= stay
              else Decision("stay_off", 0.0, -1, 0.0)}

    # forward reconstruction
    rows, total, s, q_prev = [], 0.0, 0, 0.0
    for t in range(1, T + 1):
        if t > 1:
            with open(os.path.join(store, f"policy_t_{t}.pkl"), "rb") as fh:
                policy = pickle.load(fh)
        d = policy[(t, s, q_prev)]
        e_t = prices[t - 1]
        if d.action in ("start", "stay_on"):
            pr = profit_on(e_t, d.q, p) - (p.startup_cost if d.action == "start" else 0.0)
            gas = p.A * d.q ** 2 + p.B * d.q + p.C
        else:
            pr, gas = -p.idle_cost, 0.0
        rows.append((t, s, q_prev, d.action, d.q, gas, pr))
        total += pr
        s, q_prev = d.next_s, d.next_q
    return total, rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--unit", default="unitA")
    ap.add_argument("--F", type=float, default=9.0)
    ap.add_argument("--qstep", type=float, default=10.0)
    ap.add_argument("--hours", type=int, default=8784)
    ap.add_argument("--prices", default="../data/prices_2024.csv")
    ap.add_argument("--units", default="../data/units.csv")
    ap.add_argument("--out", default=None)
    ap.add_argument("--store", default="policy_store")
    a = ap.parse_args()

    prices = pd.read_csv(a.prices)["price_usd_mwh"].iloc[:a.hours].astype(float).tolist()
    u = pd.read_csv(a.units).set_index("unit").loc[a.unit]
    p = UCParams(A=float(u.A_MMBtu_per_MW2h), B=float(u.B_MMBtu_per_MWh), C=float(u.C_MMBtu_per_h),
                 F=a.F, startup_cost=float(u.startup_cost_USD), idle_cost=0.0,
                 L_up=int(u.min_up_h), L_down=int(u.min_down_h),
                 q_min=float(u.Qmin_MW), q_max=float(u.Qmax_MW),
                 ramp_up=float(u.ramp_up_MW), ramp_down=float(u.ramp_down_MW),
                 startup_ramp=float(u.startup_ramp_MW), shutdown_ramp=float(u.shutdown_ramp_MW),
                 q_step=a.qstep)
    out = a.out or f"dp_{a.unit}_F{a.F:g}.csv"

    t0 = time.time()
    total, rows = solve(prices, p, a.store)
    df = pd.DataFrame(rows, columns=["t", "s", "q_prev", "action", "q_t", "gas_MMBtu", "period_profit"])
    df["total_profit"] = total
    df.to_csv(out, index=False)
    shutil.rmtree(a.store, ignore_errors=True)
    print(f"Total profit: {total:.2f} USD   runtime: {time.time() - t0:.1f} s   written: {out}")


if __name__ == "__main__":
    main()
