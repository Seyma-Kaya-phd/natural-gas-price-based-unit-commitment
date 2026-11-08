"""
All figures of the paper (main text and appendix).

Usage: python make_figures.py --dirs <folders with the run outputs> --out <folder>
(default: current folder; figures are written to ./figures).
Figures whose input files are missing are skipped, and the missing files are
listed at the end. Copies such as 'name (1).csv' or 'name_1.csv' are accepted.

Main text
  fig_prices.png        any *_mono_F9_report.csv (price column)
  fig_heatmaps.png      samsun_mono_F8_report.csv, samsun_mono_F9_report.csv,
                        unitA_mono_F9_report.csv
  fig_monthly_gas.png   {samsun,unitA,gebze}_mono_F8_report.csv and _F9_report.csv
  fig_gas_price.png     rh_summary_price_sensitivity.csv
  fig_rh_myopic.png     rh_summary_Fi8.csv, rh_summary_Fi9.csv
  fig_rh_monthly.png    samsun_mono_F9_report.csv, samsun_F9_c168_l0_report.csv,
                        samsun_F9_c24_l0_report.csv
  fig_outage_gas.png    rh_outage_summary.csv, for_sensitivity_summary.csv,
                        rh_summary_price_sensitivity.csv
Appendix
  fig_app_unitA.png     unitA_mono_F9_report.csv; optional: dp_unitA_F9.csv
                        (output of models/pbuc_dp.py for Unit A, F = 9)
  fig_app_units_F8.png  {samsun,unitA,gebze}_mono_F8_report.csv
Data files written: monthly_gas.csv, rh_monthly_gas.csv
"""
import csv
import glob
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
import numpy as np
import pandas as pd

plt.rcParams.update({
    "font.family": "serif", "font.size": 8, "axes.titlesize": 8,
    "axes.labelsize": 8, "legend.fontsize": 7, "xtick.labelsize": 7,
    "ytick.labelsize": 7, "axes.linewidth": 0.6, "lines.linewidth": 0.9,
    "savefig.dpi": 300, "savefig.bbox": "tight", "savefig.pad_inches": 0.03})
FULL, HALF = 7.0, 3.4                      # figure widths in inches
NAME = {"samsun": "Samsun", "unitA": "Unit A", "gebze": "Gebze"}
COL = {"samsun": "#1f4e79", "unitA": "#c55a11", "gebze": "#548235"}
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
MISSING = []


DIRS = ["."]          # set in __main__
ALIAS = {"rh_summary_price_sensitivity.csv": ["rh_summary_price_sensivity.csv"]}


def find(name):
    for n in [name] + ALIAS.get(name, []):
        for d in DIRS:
            f = os.path.join(d, n)
            if os.path.exists(f):
                return f
            stem = f[:-4]
            c = [g for g in glob.glob(glob.escape(stem) + "*.csv")
                 if g[len(stem):-4].strip(" _()0123456789") == ""]
            if c:
                return max(c, key=os.path.getmtime)
    MISSING.append(name)
    return None


def summary(name):
    f = find(name)
    if f is None:
        return None
    d = pd.read_csv(f)
    d = d[d["out"] != "out"].copy()
    for c in d.columns:
        if c not in ("out", "SEQ", "QFORM", "INFO"):
            d[c] = pd.to_numeric(d[c], errors="coerce")
    return d.set_index("out")


def hourly(out):
    f = find(f"{out}_report.csv")
    if f is None:
        return None
    rows, on = [], False
    with open(f, newline="") as fh:
        for r in csv.reader(fh):
            if r and r[0].strip().strip('"') == "hour":
                on = True
                continue
            if on and len(r) >= 7:
                rows.append([float(x) for x in r[1:7]])
    d = pd.DataFrame(rows, columns=["Q", "u", "sUP", "sDOWN", "gas", "price"])
    d.index = pd.date_range("2024-01-01 00:00", periods=len(d), freq="h")
    return d


def month_axis(ax):
    ax.set_xticks(range(12))
    ax.set_xticklabels([m[0] for m in MONTHS])


OUTDIR = "."


def save(fig, name):
    name = os.path.join(OUTDIR, name)
    fig.savefig(name)
    plt.close(fig)
    print("written:", name)


# ------------------------------------------------------------- main text
def fig_prices():
    d = None
    for o in ("samsun_mono_F9", "unitA_mono_F9", "gebze_mono_F9"):
        d = hourly(o)
        if d is not None:
            break
    if d is None:
        return
    p = d["price"]
    day = p.resample("D").agg(["min", "mean", "max"])
    prof = p.groupby([p.index.month, p.index.hour]).mean().unstack()
    fig, ax = plt.subplots(1, 2, figsize=(FULL, 2.7), constrained_layout=True,
                           gridspec_kw={"width_ratios": [1.35, 1]})
    a = ax[0]
    a.fill_between(day.index, day["min"], day["max"], color="#c9d9ea", lw=0,
                   label="Daily range")
    a.plot(day.index, day["mean"], color="#1f4e79", lw=0.8, label="Daily mean")
    a.set_ylabel("Price (USD/MWh)")
    a.set_xticks(pd.date_range("2024-01-01", periods=12, freq="MS"))
    a.set_xticklabels([m[0] for m in MONTHS])
    a.set_xlim(day.index[0], day.index[-1])
    a.set_ylim(0, 100)
    a.legend(loc="upper center", bbox_to_anchor=(0.5, -0.09), ncol=2, frameon=False)
    a.set_title("(a) Daily minimum, mean and maximum price", loc="left")
    a = ax[1]
    im = a.imshow(prof.values, aspect="auto", cmap="viridis", origin="upper")
    a.set_yticks(range(12))
    a.set_yticklabels(MONTHS)
    a.set_xticks([0, 6, 12, 18, 23])
    a.set_xlabel("Hour of day")
    a.set_title("(b) Mean price by month and hour", loc="left")
    cb = fig.colorbar(im, ax=a, shrink=0.9, pad=0.02)
    cb.set_label("USD/MWh")
    save(fig, "fig_prices.png")


def fig_heatmaps():
    cases = [("samsun_mono_F8", "(a) Samsun, F = 8"),
             ("samsun_mono_F9", "(b) Samsun, F = 9"),
             ("unitA_mono_F9", "(c) Unit A, F = 9")]
    ds = [hourly(o) for o, _ in cases]
    if any(d is None for d in ds):
        return
    fig, ax = plt.subplots(1, 3, figsize=(FULL, 3.3), sharey=True,
                           constrained_layout=True)
    starts = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
    for a, d, (_, t) in zip(ax, ds, cases):
        a.imshow(d["u"].values.reshape(-1, 24), aspect="auto", cmap="Greys",
                 vmin=0, vmax=1.25, interpolation="nearest")
        a.set_xticks([0, 6, 12, 18, 23])
        a.set_xlabel("Hour of day")
        a.set_title(f"{t} ({d['u'].mean() * 100:.1f}% online)", loc="left")
    ax[0].set_yticks(starts)
    ax[0].set_yticklabels(MONTHS)
    fig.legend(handles=[Patch(color="0.2", label="Online"),
                        Patch(facecolor="white", edgecolor="0.6", label="Offline")],
               loc="outside lower center", ncol=2, frameon=False)
    save(fig, "fig_heatmaps.png")


def fig_monthly_gas():
    data, rows = {}, []
    for F in (8, 9):
        for u in ("samsun", "unitA", "gebze"):
            d = hourly(f"{u}_mono_F{F}")
            if d is None:
                return
            mg = d["gas"].resample("MS").sum() / 1e6
            data[(F, u)] = mg.values
            rows += [dict(F=F, unit=NAME[u], month=m.month, gas_1e6MMBtu=round(v, 4))
                     for m, v in mg.items()]
    pd.DataFrame(rows).to_csv(os.path.join(OUTDIR, "monthly_gas.csv"), index=False)
    fig, ax = plt.subplots(1, 2, figsize=(FULL, 2.6), sharey=True,
                           constrained_layout=True)
    w = 0.27
    for a, F in zip(ax, (8, 9)):
        for k, u in enumerate(("samsun", "unitA", "gebze")):
            a.bar(np.arange(12) + (k - 1) * w, data[(F, u)], w, color=COL[u],
                  label=NAME[u])
        month_axis(a)
        a.set_title(f"({'ab'[F - 8]}) F = {F} USD/MMBtu", loc="left")
        a.grid(axis="y", alpha=0.3, lw=0.4)
        a.set_axisbelow(True)
    ax[0].set_ylabel("Gas consumption (10$^6$ MMBtu)")
    ax[1].legend(frameon=False, loc="upper left")
    save(fig, "fig_monthly_gas.png")


def fig_gas_price():
    s = summary("rh_summary_price_sensitivity.csv")
    if s is None:
        return
    fig, ax = plt.subplots(1, 2, figsize=(FULL, 2.5), constrained_layout=True)
    for u in ("samsun", "unitA", "gebze"):
        d = s[s.index.str.startswith(u + "_mono_F")].sort_values("F")
        ax[0].plot(d["F"], d["gasTotal"] / 1e6, "o-", ms=2.5, color=COL[u], label=NAME[u])
        ax[1].plot(d["F"], d["hoursOn"] / 8784 * 100, "o-", ms=2.5, color=COL[u])
    ax[0].set_ylabel("Annual gas consumption (10$^6$ MMBtu)")
    ax[1].set_ylabel("Hours online (% of year)")
    for a, t in zip(ax, ("(a)", "(b)")):
        a.set_xlabel("Gas price (USD/MMBtu)")
        a.set_title(t, loc="left")
        a.grid(alpha=0.3, lw=0.4)
    ax[0].legend(frameon=False, loc="upper right")
    save(fig, "fig_gas_price.png")


def fig_rh_myopic():
    d8, d9 = summary("rh_summary_Fi8.csv"), summary("rh_summary_Fi9.csv")
    if d8 is None or d9 is None:
        return
    cases = [("samsun", d8, "Samsun, F = 8"), ("samsun", d9, "Samsun, F = 9"),
             ("unitA", d8, "Unit A, F = 8"), ("unitA", d9, "Unit A, F = 9"),
             ("gebze", d8, "Gebze, F = 8")]
    blocks = (24, 168, 720)
    fig, ax = plt.subplots(1, 2, figsize=(FULL, 2.7), constrained_layout=True)
    w = 0.15
    for k, (u, d, name) in enumerate(cases):
        ref = d.loc[f"{u}_mono"]
        dp = [(ref.profitExact - d.loc[f"{u}_c{c}_l0", "profitExact"]) / ref.profitExact * 100
              for c in blocks]
        dg = [(d.loc[f"{u}_c{c}_l0", "gasTotal"] - ref.gasTotal) / ref.gasTotal * 100
              for c in blocks]
        x = np.arange(3) + (k - 2) * w
        kw = dict(color=COL[u], edgecolor="white", lw=0.3,
                  hatch="////" if "F = 9" in name else None)
        ax[0].bar(x, dp, w, label=name, **kw)
        ax[1].bar(x, dg, w, **kw)
    for a, t, y in zip(ax, ("(a)", "(b)"), (r"$\Delta\pi$ (%)", r"$\Delta G$ (%)")):
        a.set_xticks(range(3))
        a.set_xticklabels(["Daily", "Weekly", "Monthly"])
        a.set_xlabel("Block length (no look-ahead)")
        a.set_ylabel(y)
        a.set_title(t, loc="left")
        a.axhline(0, color="k", lw=0.5)
        a.grid(axis="y", alpha=0.3, lw=0.4)
        a.set_axisbelow(True)
    fig.legend(loc="outside lower center", ncol=5, frameon=False)
    save(fig, "fig_rh_myopic.png")


def fig_rh_monthly():
    cases = [("samsun_mono_F9", "Full year"),
             ("samsun_F9_c168_l0", "Weekly blocks, no look-ahead"),
             ("samsun_F9_c24_l0", "Daily blocks, no look-ahead")]
    ds = [hourly(o) for o, _ in cases]
    if any(d is None for d in ds):
        return
    rows = []
    fig, ax = plt.subplots(figsize=(HALF * 1.4, 2.5), constrained_layout=True)
    w = 0.27
    for k, (d, (o, lab)) in enumerate(zip(ds, cases)):
        mg = d["gas"].resample("MS").sum() / 1e6
        ax.bar(np.arange(12) + (k - 1) * w, mg.values, w, label=lab,
               color=["#1f4e79", "#6f9bc8", "#c9d9ea"][k], edgecolor="0.4", lw=0.2)
        rows += [dict(run=o, month=m.month, gas_1e6MMBtu=round(v, 4)) for m, v in mg.items()]
    pd.DataFrame(rows).to_csv(os.path.join(OUTDIR, "rh_monthly_gas.csv"), index=False)
    month_axis(ax)
    ax.set_ylabel("Gas consumption (10$^6$ MMBtu)")
    ax.legend(frameon=False, loc="upper left")
    ax.grid(axis="y", alpha=0.3, lw=0.4)
    ax.set_axisbelow(True)
    save(fig, "fig_rh_monthly.png")


def fig_outage_gas():
    m, f, s = summary("rh_outage_summary.csv"), summary("for_sensitivity_summary.csv"), \
        summary("rh_summary_price_sensitivity.csv")
    if m is None or f is None or s is None:
        return
    fig, ax = plt.subplots(1, 2, figsize=(FULL, 2.8), constrained_layout=True)
    for a, u, t in zip(ax, ("samsun", "unitA"), ("(a) Samsun", "(b) Unit A")):
        data = [[f.at[f"{u}_FOR0.02_full_mono_s{k}", "gasTotal"] / 1e6 for k in range(1, 21)],
                [m.at[f"{u}_full_mono_s{k}", "gasTotal"] / 1e6 for k in range(1, 21)],
                [f.at[f"{u}_FOR0.10_full_mono_s{k}", "gasTotal"] / 1e6 for k in range(1, 21)]]
        a.boxplot(data, widths=0.45, medianprops={"color": COL[u]},
                  flierprops={"ms": 2.5})
        a.set_xticks([1, 2, 3])
        a.set_xticklabels(["FOR = 0.02", "FOR = 0.05", "FOR = 0.10"])
        a.axhline(m.at[f"{u}_pm_mono", "gasTotal"] / 1e6, color="0.3", lw=0.8,
                  label="Maintenance only, F = 9")
        a.axhline(s.at[f"{u}_mono_F8.5", "gasTotal"] / 1e6, color="0.5", ls="--", lw=0.8,
                  label="No maintenance or outages, F = 8.5")
        a.axhline(s.at[f"{u}_mono_F9.5", "gasTotal"] / 1e6, color="0.5", ls=":", lw=0.8,
                  label="No maintenance or outages, F = 9.5")
        a.set_ylabel("Annual gas consumption (10$^6$ MMBtu)")
        a.set_title(t, loc="left")
        a.grid(axis="y", alpha=0.3, lw=0.4)
    h, l = ax[0].get_legend_handles_labels()
    fig.legend(h, l, loc="outside lower center", ncol=3, frameon=False)
    save(fig, "fig_outage_gas.png")


# -------------------------------------------------------------- appendix
def fig_app_unitA():
    d = hourly("unitA_mono_F9")
    if d is None:
        return
    m = d.loc["2024-01"]
    dp = None
    f = find("dp_unitA_F9.csv")
    if f:
        r = pd.read_csv(f)
        dp = pd.Series(r["q_t"].values[:len(d)], index=d.index[:len(r)]).loc["2024-01"]
    else:
        MISSING.pop()                      # the DP file is optional
    fig, ax = plt.subplots(2, 1, figsize=(FULL, 3.6), sharex=True, constrained_layout=True)
    ax[0].step(m.index, m["Q"], where="post", color=COL["unitA"], label="Output (optimal schedule)")
    if dp is not None:
        ax[0].step(dp.index, dp.values, where="post", color="k", ls="--", lw=0.7,
                   label="Output (DP, $\\Delta q$ = 10 MW)")
    ax[1].step(m.index, m["gas"], where="post", color=COL["unitA"], label="Gas consumption")
    ax[0].set_ylabel("Output (MW)")
    ax[1].set_ylabel("Gas (MMBtu/h)")
    for a, t in zip(ax, ("(a)", "(b)")):
        b = a.twinx()
        b.plot(m.index, m["price"], color="0.55", lw=0.6, label="Price")
        b.set_ylabel("Price (USD/MWh)")
        b.set_ylim(0, 100)
        a.set_title(t, loc="left")
    h1, l1 = ax[0].get_legend_handles_labels()
    h2, l2 = ax[1].get_legend_handles_labels()
    fig.legend(h1 + h2 + [plt.Line2D([], [], color="0.55", lw=0.6)], l1 + l2 + ["Price"],
               loc="outside lower center", ncol=4, frameon=False)
    ax[1].set_xlim(m.index[0], m.index[-1])
    ax[1].xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%d %b"))
    save(fig, "fig_app_unitA.png")


def fig_app_units_F8():
    ds = {u: hourly(f"{u}_mono_F8") for u in ("samsun", "unitA", "gebze")}
    if any(d is None for d in ds.values()):
        return
    win = slice("2024-07-01", "2024-07-31")
    fig, ax = plt.subplots(2, 1, figsize=(FULL, 3.8), sharex=True, constrained_layout=True)
    for u, d in ds.items():
        m = d.loc[win]
        ax[0].step(m.index, m["Q"], where="post", color=COL[u], label=NAME[u])
        ax[1].step(m.index, m["gas"], where="post", color=COL[u], label=NAME[u])
    ax[0].set_ylabel("Output (MW)")
    ax[1].set_ylabel("Gas (MMBtu/h)")
    p = ds["samsun"].loc[win, "price"]
    for a, t in zip(ax, ("(a)", "(b)")):
        b = a.twinx()
        b.plot(p.index, p.values, color="0.6", lw=0.6, label="Price")
        b.set_ylabel("Price (USD/MWh)")
        b.set_ylim(0, 100)
        a.set_title(t, loc="left")
    h1, l1 = ax[0].get_legend_handles_labels()
    fig.legend(h1 + [plt.Line2D([], [], color="0.6", lw=0.6)], l1 + ["Price"],
               loc="outside lower center", ncol=4, frameon=False)
    ax[1].set_xlim(p.index[0], p.index[-1])
    ax[1].xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%d %b"))
    save(fig, "fig_app_units_F8.png")


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Figures of the paper")
    ap.add_argument("--dirs", nargs="+", default=["."],
                    help="folders searched for the input files")
    ap.add_argument("--out", default="figures", help="output folder")
    a = ap.parse_args()
    DIRS[:] = a.dirs
    OUTDIR = a.out
    os.makedirs(OUTDIR, exist_ok=True)
    for fn in (fig_prices, fig_heatmaps, fig_monthly_gas, fig_gas_price,
               fig_rh_myopic, fig_rh_monthly, fig_outage_gas,
               fig_app_unitA, fig_app_units_F8):
        fn()
    if MISSING:
        print("Files not found; the corresponding figures were skipped:")
        for x in sorted(set(MISSING)):
            print("  ", x)
