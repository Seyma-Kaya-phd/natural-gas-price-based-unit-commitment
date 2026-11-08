"""
Builds the parameter files read by the GAMS models (params_<unit>.xlsx) from
units.csv and prices_2024.csv.

    python make_parameter_files.py              # all units
    python make_parameter_files.py --unit samsun

Each file contains three sheets:
  index      read instructions for gdxxrw (symbol, range, dimensions)
  hourly     columns A-B: hour and electricity price (USD/MWh); D-E: unavailability M;
             G-H: minimum output; J-K: maximum output (MW)
  generator  gas price and unit parameters (one row per parameter)
The unit is labelled G1 in all files. The gas price written to the file
(--F, default 9 USD/MMBtu) can be overridden in GAMS with --FPRICE.
"""
import argparse
import os

import pandas as pd
from openpyxl import Workbook

HERE = os.path.dirname(os.path.abspath(__file__))


def build(u, prices, F, path):
    n = len(prices)
    wb = Workbook()
    hs = wb.active
    hs.title = "hourly"
    # row 1: column labels of the two-dimensional ranges (corner cells stay empty)
    hs.append(["hour", "price", None, None, "G1", None, None, "G1", None, None, "G1"])
    for k, (h, pr) in enumerate(zip(prices["hour"], prices["price_usd_mwh"])):
        hs.append([h, float(pr), None, h, 0, None, h, float(u.Qmin_MW), None, h, float(u.Qmax_MW)])
    gen = [("F", F), ("A", u.A_MMBtu_per_MW2h), ("B", u.B_MMBtu_per_MWh), ("C", u.C_MMBtu_per_h),
           ("SC", u.startup_cost_USD), ("RampUp", u.ramp_up_MW), ("StartRampUp", u.startup_ramp_MW),
           ("RampDown", u.ramp_down_MW), ("CloseRampDown", u.shutdown_ramp_MW),
           ("Lup", u.min_up_h), ("Ldown", u.min_down_h)]
    gs = wb.create_sheet("generator")
    gs.append(["unit", "value", "parameter"])
    for name, v in gen:
        gs.append(["G1", float(v), name])
    ix = wb.create_sheet("index", 0)
    ix.append([None, None, None, "Cdim", "Rdim"])
    last = n + 1
    ix.append(["par", "e_price", f"hourly!A2:B{last}", None, 1])
    ix.append(["par", "M", f"hourly!D1:E{last}", 1, 1])
    ix.append(["par", "Qmin", f"hourly!G1:H{last}", 1, 1])
    ix.append(["par", "Qmax", f"hourly!J1:K{last}", 1, 1])
    for k, (name, _) in enumerate(gen, start=2):
        ix.append(["par", name, f"generator!A{k}:B{k}", None, 1])
    ix.append(["set", "t", f"hourly!A2:A{last}", None, 1])
    wb.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", default=None)
    ap.add_argument("--F", type=float, default=9.0)
    a = ap.parse_args()
    units = pd.read_csv(os.path.join(HERE, "units.csv"))
    prices = pd.read_csv(os.path.join(HERE, "prices_2024.csv"))
    for _, u in units.iterrows():
        if a.unit and u.unit != a.unit:
            continue
        path = os.path.join(HERE, f"params_{u.unit}.xlsx")
        build(u, prices, a.F, path)
        print("written:", path)


if __name__ == "__main__":
    main()
