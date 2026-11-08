"""
Computes the relative profit loss (Delta pi) and the relative deviation of the
annual gas consumption (Delta G) defined in Eq. (rh_metrics) of the paper from
the summary files written by the GAMS runs.

    Delta pi = (pi_ref - pi) / pi_ref * 100
    Delta G  = (G - G_ref) / G_ref * 100

Usage (in the folder with the summary files, or give it with --dirs):
    python compute_metrics.py [--dirs <folders>] [--out metrics]
Each section is skipped if its input file is missing. Results are written to
metrics_*.csv.
"""
import glob
import os
import pandas as pd


DIRS = ["."]          # set in __main__


def find(name):
    """Return the file for `name` in DIRS, accepting copies such as
    'name (2).csv' or 'name__2_.csv'; the most recent copy is used."""
    for d in DIRS:
        f = os.path.join(d, name)
        if os.path.exists(f):
            return f
        stem = f[:-4]
        cands = [g for g in glob.glob(glob.escape(stem) + "*.csv")
                 if g[len(stem):-4].strip(" _()0123456789") == ""]
        if cands:
            return max(cands, key=os.path.getmtime)
    return None


def load(path):
    """Read a summary file and drop repeated header rows."""
    df = pd.read_csv(path)
    df = df[df["out"] != "out"].copy()
    for c in df.columns:
        if c not in ("out", "SEQ", "QFORM", "INFO"):
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df.set_index("out")


def metrics(df, run, ref, pcol, gcol="gasTotal"):
    p, g = df.at[run, pcol], df.at[run, gcol]
    pr, gr = df.at[ref, pcol], df.at[ref, gcol]
    return (pr - p) / pr * 100, (g - gr) / gr * 100


def pwl_grid(path, units=("samsun", "unitA", "gebze")):
    """PWL rolling horizon: reference = <unit>_mono, exact profit."""
    df, rows = load(path), []
    for u in units:
        ref = f"{u}_mono"
        if ref not in df.index:
            print(f"  note: {ref} not found in {path}; {u} skipped")
            continue
        if abs(df.at[ref, "profitExact"]) < 1e-6:
            print(f"  note: {u} is not committed in {path} (reference profit 0); {u} skipped")
            continue
        for run in df.index:
            if run.startswith(u + "_c"):
                dp, dg = metrics(df, run, ref, "profitExact")
                rows.append(dict(file=path, run=run, ref=ref, dpi=dp, dG=dg,
                                 time_s=df.at[run, "solverTime_s"]))
    return rows


def miqp_grid(paths, refs):
    """MIQP rolling horizon. refs: unit -> reference run name."""
    df = pd.concat([load(p) for p in paths if os.path.exists(p)])
    df = df[~df.index.duplicated(keep="last")]
    rows = []
    for u, ref in refs.items():
        if ref not in df.index:
            print(f"  note: reference run {ref} not found; {u} skipped "
                  f"(is the file that contains it in this folder?)")
            continue
        for run in df.index:
            if run.startswith(f"{u}_miqp_F8_c"):
                dp, dg = metrics(df, run, ref, "profit")
                rows.append(dict(run=run, ref=ref, dpi=dp, dG=dg,
                                 time_s=df.at[run, "solverTime_s"]))
    return rows


def per_seed(df, units, configs, ref_cfg, other=None, seeds=range(1, 21)):
    """Outage experiments: reference is the same sample (seed) of ref_cfg."""
    rows = []
    for u in units:
        for c in configs:
            for s in seeds:
                run, ref = f"{u}_{c}_s{s}", f"{u}_{ref_cfg}_s{s}"
                d = df if other is None or run in df.index else other
                if run not in d.index and other is not None:
                    d = other
                if run not in d.index or ref not in df.index:
                    continue
                p, g = d.at[run, "profitExact"], d.at[run, "gasTotal"]
                pr, gr = df.at[ref, "profitExact"], df.at[ref, "gasTotal"]
                rows.append(dict(unit=u, config=c, seed=s, ref=ref_cfg,
                                 dpi=(pr - p) / pr * 100, dG=(g - gr) / gr * 100))
    return rows


def summarize(rows, keys):
    df = pd.DataFrame(rows)
    return df.groupby(keys)[["dpi", "dG"]].agg(["mean", "min", "max"]).round(3)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description="Delta pi and Delta G of all experiments")
    ap.add_argument("--dirs", nargs="+", default=["."])
    ap.add_argument("--out", default="metrics")
    a = ap.parse_args()
    DIRS[:] = [os.path.abspath(d) for d in a.dirs]
    os.makedirs(a.out, exist_ok=True)
    os.chdir(a.out)          # metrics_*.csv are written to this folder
    expected = ["rh_summary_Fi8.csv", "rh_summary_Fi9.csv", "rh_miqp_summary.csv",
                "rh_outage_summary.csv", "offset_summary.csv", "for_sensitivity_summary.csv"]
    missing = [f for f in expected if find(f) is None]
    for f in expected:
        if find(f) not in (None, f):
            print(f"  using '{find(f)}' for {f}")
    if missing:
        print("Files not found (the corresponding results are not computed):")
        for f in missing:
            print("  ", f)
    for f in ("rh_summary_Fi8.csv", "rh_summary_Fi9.csv"):
        if find(f):
            out = pd.DataFrame(pwl_grid(find(f))).round(3)
            out.to_csv(f"metrics_pwl_{f[11:14]}.csv", index=False)
            print(f"\n== PWL rolling horizon, {f}\n", out.to_string(index=False))

    mq = ["rh_miqp_summary.csv"]
    refs = {"unitA": "unitA_miqp_F8_mono", "gebze": "gebze_miqp_F8_mono",
            "samsun": "samsun_miqp_F8_mono_ineq"}
    rows = miqp_grid([find(f) for f in mq if find(f)], refs)
    if rows:
        out = pd.DataFrame(rows).round(3)
        out.to_csv("metrics_miqp_F8.csv", index=False)
        print("\n== MIQP rolling horizon, F = 8\n", out.to_string(index=False))

    if find("rh_outage_summary.csv"):
        m = load(find("rh_outage_summary.csv"))
        cfg = ["full_c168_l0", "full_c168_l48", "rev_fy", "rev_c168_l0",
               "rev_c168_l48", "rev_c24_l0"]
        r1 = per_seed(m, ("samsun", "unitA"), cfg, "full_mono")
        r2 = per_seed(m, ("samsun", "unitA"), ["rev_c168_l0", "rev_c168_l48", "rev_c24_l0"], "rev_fy")
        pd.DataFrame(r1 + r2).round(4).to_csv("metrics_outages.csv", index=False)
        print("\n== Outages vs known-outage reference (FOR = 0.05)\n", summarize(r1, ["unit", "config"]))
        print("\n== Outages vs full-year re-planning (FOR = 0.05)\n", summarize(r2, ["unit", "config"]))
        if find("offset_summary.csv"):
            o = load(find("offset_summary.csv"))
            ro = []
            for u in ("samsun", "unitA"):
                for c in (24, 168):
                    for s in range(1, 21):
                        run, ref = f"{u}_offB_c{c}_s{s}", f"{u}_full_mono_s{s}"
                        if run in o.index and ref in m.index:
                            pr, gr = m.at[ref, "profitExact"], m.at[ref, "gasTotal"]
                            ro.append(dict(unit=u, config=f"aligned_c{c}_l0", seed=s,
                                           dpi=(pr - o.at[run, "profitExact"]) / pr * 100,
                                           dG=(o.at[run, "gasTotal"] - gr) / gr * 100))
            if ro:
                pd.DataFrame(ro).round(4).to_csv("metrics_offset_aligned.csv", index=False)
                print("\n== Aligned blocks vs known-outage reference\n", summarize(ro, ["unit", "config"]))
            ra = []
            for u in ("samsun", "unitA"):
                ref = f"{u}_pm_mono"
                for run in o.index:
                    if run.startswith(f"{u}_offA") and ref in m.index:
                        pr, gr = m.at[ref, "profitExact"], m.at[ref, "gasTotal"]
                        ra.append(dict(run=run, dpi=(pr - o.at[run, "profitExact"]) / pr * 100,
                                       dG=(o.at[run, "gasTotal"] - gr) / gr * 100))
            if ra:
                pd.DataFrame(ra).round(3).to_csv("metrics_offset_boundary.csv", index=False)
                print("\n== Block offset, no forced outages\n", pd.DataFrame(ra).round(3).to_string(index=False))

    if find("for_sensitivity_summary.csv"):
        f = load(find("for_sensitivity_summary.csv"))
        rows = []
        for R in ("0.02", "0.10"):
            for u in ("samsun", "unitA"):
                rows += [dict(r, FOR=R) for r in per_seed(
                    f, (f"{u}_FOR{R}",), ["rev_fy"], "full_mono")]
                rows += [dict(r, FOR=R) for r in per_seed(
                    f, (f"{u}_FOR{R}",), ["rev_c168_l0", "rev_c168_l48", "rev_c24_l0"], "rev_fy")]
        if rows:
            pd.DataFrame(rows).round(4).to_csv("metrics_for_sensitivity.csv", index=False)
            print("\n== FOR sensitivity\n", summarize(rows, ["unit", "config", "ref"]))
