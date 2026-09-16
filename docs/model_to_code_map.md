# Mapping between the paper and the code

A reading guide for the three implementations. Equation numbers refer to the
accompanying paper.

## 1. Symbols

| Paper | GAMS (`basic_model.gms`, `basic_linearization.gms`) | Python (`DPmodel.py`) | Meaning |
| --- | --- | --- | --- |
| `e_t` | `e_price(t)` | `prices[t-1]` | market clearing price, $/MWh |
| `F_i` | `F(i)` | `UCParams.F` | natural gas price, $/MMBtu |
| `A_i`, `B_i`, `C_i` | `A(i)`, `B(i)`, `C(i)` | `UCParams.A/B/C` | quadratic heat-rate coefficients |
| `SC_i` | `SC(i)` | `UCParams.startup_cost` | start-up cost, $ |
| `L^up_i`, `L^down_i` | `Lup(i)`, `Ldown(i)` | `UCParams.L_up`, `L_down` | minimum up / down times, h |
| `RU_i`, `RD_i` | `RampUp(i)`, `RampDown(i)` | `UCParams.ramp_up`, `ramp_down` | ramp limits while online |
| `SRU_i`, `CRD_i` | `StartRampUp(i)`, `CloseRampDown(i)` | `UCParams.startup_ramp`, `shutdown_ramp` | start-up / shut-down ramp limits |
| `Qmin_t,i`, `Qmax_t,i` | `Qmin(t,i)`, `Qmax(t,i)` | `UCParams.q_min`, `q_max` | output limits, MW |
| `M_t,i` | `M(t,i)` | — (no maintenance in the DP runs) | maintenance indicator |
| `Q_t,i` | `Q(t,i)` | `q`, `Decision2D.q` | power output, MW |
| `u_t,i` | `u(t,i)` | implied by the sign of the state `s` | commitment status |
| `s^up_t,i`, `s^down_t,i` | `sUP(t,i)`, `sDOWN(t,i)` | actions `"start"`, `"shut_down"` | start-up / shut-down indicators |
| `δ_t,i,l` | `delta(t,i,l)` | — | output in PWL segment `l` |
| `z_t,i,l` | `z(t,i,l)` | — | sequential filling indicator |
| `S_i,l` | `f_il(l,i)` | — | marginal slope of segment `l` |
| `ΔQ_i` | `DeltaQ(t,i)` | — | width of one PWL segment |
| `Δq` | — | `UCParams.q_step` | dispatch discretisation step |

## 2. Exact MIQP — `gams/basic_model.gms`

| Equation | GAMS equation |
| --- | --- |
| (1) objective | `Objective`, split into `Revenue`, `HeatFunction` and `FCost` |
| (2) capacity limits | `CapacityMin`, `CapacityMax` |
| (3) ramp-up with start-up trajectory | `RampUpE` |
| (4) ramp-down with shut-down trajectory | `RampDownE` |
| (5) minimum up time | `MinOpen` |
| (6) minimum down time | `MinClose` |
| (7) status ↔ transition logic | `UandS` |
| (8) no simultaneous start-up and shut-down | `OpenAndClose` |
| (9) maintenance | `Avaliable` |
| (10), (11) variable domains | `Binary Variables` block, `positive variable Q` |
| — | `Demand`: an upper bound on hourly output that is not part of the price-taker formulation and is not binding with the sample data |

The quadratic term `A(i)*Q(t,i)*Q(t,i)` in `HeatFunction` is what makes the
model an MIQCP, which is why it is solved with `SOLVE ... USING MIQCP`.

## 3. Piecewise linear MILP — `gams/basic_linearization.gms`

Same constraint set, with the fuel cost replaced by the sequentially filled
piecewise linear approximation:

| Equation | GAMS equation |
| --- | --- |
| (12) output reconstruction from segments | `Production` |
| (13) segment bounds | `Delta_lower`, `Delta_upper` |
| (14) segment `l` must be full before `l+1` opens | `Eq_SeqFill1` |
| (15) segment `l+1` is blocked while `l` is not full | `Eq_SeqFill2` |
| (16) linearized heat rate | `HeatFunction` |

The segment width `ΔQ_i` is computed once after the data are loaded:

```gams
DeltaQ(t,i) = (Qmax(t,i) - Qmin(t,i)) / card(l);
```

Because the model is linear in the decision variables, it is solved with
`SOLVE ... USING MIP`.

## 4. Dynamic programming — `python/DPmodel.py`

**State.** `(s, q_prev)`:

* `s >= 1` — the unit has been online for `s` consecutive hours;
* `s <= -1` — the unit has been offline for `|s|` consecutive hours;
* `s = 0` — the initial state, which exists at `t = 1` only;
* `q_prev` — the dispatch level of the previous hour, `0` whenever offline.

Embedding `q_prev` in the state is what lets the ramp limits be enforced inside
the transitions instead of in a separate economic-dispatch step.

**Actions and feasible dispatch windows.**

| Action | Condition | Dispatch window for `q_t` |
| --- | --- | --- |
| `stay_off` | always feasible while offline | `q_t = 0` |
| `start` | `s <= -L_down` | `[q_min, min(q_max, startup_ramp)]` |
| `stay_on` | always feasible while online | `[max(q_min, q_prev - ramp_down), min(q_max, q_prev + ramp_up)]` |
| `shut_down` | `s >= L_up` and `q_prev <= max(shutdown_ramp, ramp_down)` | `q_t = 0` |

**Bellman recursion, Eq. (17).** `solve_single_unit_uc_dp_with_susd` runs
backwards from `t = T` to `t = 2` with the terminal condition `V_{T+1} = 0`,
stores the optimal decision of each stage on disk, then reconstructs the
schedule forwards from `(s, q_prev) = (0, 0)`.

| Code element | Role |
| --- | --- |
| `UCParams` | technical and economic parameters of the unit |
| `Decision2D` | optimal action, dispatch level and successor state of one state |
| `_profit_on` | single-hour profit of Eq. (18) with the exact quadratic fuel cost |
| `_build_q_grid` | dispatch grid over `[q_min, q_max]` with step `q_step` |
| `_valid_s` | operating-duration counters reachable at stage `t` |
| `_best_q_with_future` | dispatch level maximising immediate profit plus future value |
| `getV` | value of a successor state; `-inf` marks an unreachable state |
| `policy_store/policy_t_*.pkl` | per-stage policy, written to disk to bound memory use |

**Differences from the mathematical formulation.** The DP evaluates dispatch on
a discrete grid of step `q_step`, so its schedule is optimal for the discretised
problem rather than for the continuous one; the paper therefore reports DP
objective values as obtained values rather than as certified optima. Maintenance
(`M_t,i`) and the `Demand` bound of the GAMS models are not represented in the
DP implementation.
