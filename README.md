# Full-year profit-based unit commitment of natural gas-fired power plants

Models, data and analysis scripts for the paper

> Ş. Kaya, A. D. Yücekaya, M. G. Özel, E. Çelebi, P. G. Canbolat.
> *Full-year profit-based unit commitment of natural gas-fired power plants: Annual gas requirement and the cost of horizon decomposition.*
> Submitted to *Gas Science and Engineering*, 2026.

The repository contains the models of the paper, the input data of the three case units, and the scripts that compute the reported measures and figures from the model outputs. All experiments of the paper can be repeated with the commands in [Reproducing the experiments](#reproducing-the-experiments).

## How to cite

If you use the models, data or scripts of this repository, please cite the paper:

> Kaya, Ş., Yücekaya, A. D., Özel, M. G., Çelebi, E., Canbolat, P. G. Full-year profit-based unit commitment of natural gas-fired power plants: Annual gas requirement and the cost of horizon decomposition. *Gas Science and Engineering* (submitted, 2026).

and the archived version of this repository:

> Kaya, Ş., Yücekaya, A. D., Özel, M. G., Çelebi, E., Canbolat, P. G. (2026). Full-year profit-based unit commitment of natural gas-fired power plants: models and data (Version 1.0). Zenodo. https://doi.org/10.5281/zenodo.XXXXXXX

```bibtex
@article{kaya2026fullyear,
  author  = {Kaya, {\c{S}}eyma and Y{\"u}cekaya, Ahmet Deniz and {\"O}zel, Muzaffer G{\"o}rkem and {\c{C}}elebi, Emre and Canbolat, Pelin G{\"u}l{\c{s}}ah},
  title   = {Full-year profit-based unit commitment of natural gas-fired power plants: Annual gas requirement and the cost of horizon decomposition},
  journal = {Gas Science and Engineering},
  year    = {2026},
  note    = {Submitted}
}

@software{kaya2026pbuc_code,
  author    = {Kaya, {\c{S}}eyma and Y{\"u}cekaya, Ahmet Deniz and {\"O}zel, Muzaffer G{\"o}rkem and {\c{C}}elebi, Emre and Canbolat, Pelin G{\"u}l{\c{s}}ah},
  title     = {Full-year profit-based unit commitment of natural gas-fired power plants: models and data},
  version   = {1.0},
  year      = {2026},
  publisher = {Zenodo},
  doi       = {10.5281/zenodo.XXXXXXX},
  url       = {https://github.com/Seyma-Kaya-phd/natural-gas-price-based-unit-commitment}
}
```

The file [CITATION.cff](CITATION.cff) provides the same information for the "Cite this repository" button on GitHub.

## Contents

```
models/
  pbuc_miqp.gms          MIQP with the exact quadratic heat-rate function
  pbuc_pwl.gms           MILP with a piecewise linear (PWL) heat-rate function
  pbuc_pwl_outages.gms   PWL model with planned maintenance and forced outages
  pbuc_dp.py             dynamic programming (DP) formulation
data/
  prices_2024.csv        hourly day-ahead prices of 2024 (USD/MWh)
  units.csv              parameters of the three units
  params_unitA.xlsx      parameter files read by the GAMS models
  params_samsun.xlsx
  params_gebze.xlsx
  make_parameter_files.py  builds the params_*.xlsx files from the two csv files
analysis/
  compute_metrics.py     relative profit loss and gas deviation of the experiments
  make_figures.py        figures of the paper
```

## Requirements

* GAMS (the results were obtained with GAMS 52.5) with a Gurobi license (Gurobi 13.0). The GAMS models read the parameter files with `gdxxrw`, which requires Windows and Microsoft Excel.
* Python 3.10 or later with `numpy`, `pandas`, `matplotlib` and `openpyxl` (`pip install -r requirements.txt`).

## Model

All models implement the formulation of Section 2 of the paper for one price-taking unit:

* objective: revenue at the hourly day-ahead price minus fuel cost (gas price × quadratic heat-rate function) minus start-up cost;
* minimum and maximum output, ramp-up and ramp-down limits, start-up and shut-down ramp limits;
* minimum up and down times, `s_up(t) + sum(h = t, ..., t+L_up-1) s_down(h) <= 1` and analogously for the down time;
* unit availability `u(t) <= 1 - M(t)`;
* the unit is offline before the first hour.

The GAMS models solve the year either as one model (`--COMMIT=8784 --LOOK=0`) or with a rolling horizon: the year is divided into commitment blocks of `COMMIT` hours, each block is optimized together with a look-ahead of `LOOK` hours, and only the decisions of the block are fixed. The state at the start of each window (status, time in status, previous output) is carried over exactly. Profits and gas volumes are always reported for the schedule assembled over the whole year and evaluated with the exact heat-rate function.

In `pbuc_miqp.gms`, `--QFORM` selects how the fuel cost is written. With `--QFORM=eq` (default), the total fuel cost is defined by one quadratic equality; this form is required for units with a concave heat-rate function (Unit A, A < 0). With `--QFORM=ineq`, the hourly fuel cost of units with A ≥ 0 is defined by the convex inequality `c(t) >= F (A Q(t)^2 + B Q(t) + C u(t))`, which holds with equality at an optimum and is solved much faster.

## Data

`data/prices_2024.csv` contains the hourly market clearing prices (PTF) of the Turkish day-ahead market for 1 January to 31 December 2024 (8,784 hours) in USD/MWh, published by Energy Exchange Istanbul (EPİAŞ, https://seffaflik.epias.com.tr).

`data/units.csv` contains the parameters of the three units. The heat-rate coefficients are given in MMBtu: A in MMBtu/MW²h, B in MMBtu/MWh and C in MMBtu/h, so that the hourly gas consumption is `A Q^2 + B Q + C` for an output Q in MW.

| Unit | Q min–max (MW) | Start-up cost (USD) | Ramp up / down (MW/h) | Min. up / down time (h) | Source |
|---|---|---|---|---|---|
| `unitA` | 100–300 | 12,000 | 100 / 100 | 4 / 6 | Živić Djurović et al. (2012) |
| `samsun` | 367–890 | 50,000 | 100 / 150 | 4 / 6 | Samsun CCGT environmental impact assessment report (2009) |
| `gebze` | 76–253 | 10,000 | 50 / 75 | 4 / 4 | Information document, Ministry of Treasury and Finance of Türkiye (2021) |

The files `params_<unit>.xlsx` are generated from these two files with

```
cd data
python make_parameter_files.py
```

Each file has three sheets: `index` (read instructions for `gdxxrw`), `hourly` (prices, unavailability and output limits) and `generator` (gas price and unit parameters). The gas price stored in the files (9 USD/MMBtu) is overridden with `--FPRICE` in all commands below.

## Running a model

GAMS writes its output to the current folder, so it is convenient to run the models from a separate folder, for example `runs/` next to `models/`:

```
mkdir runs
cd runs
gams ../models/pbuc_pwl.gms  --XLS=../data/params_samsun.xlsx --FPRICE=9 --COMMIT=8784 --LOOK=0 --OUT=samsun_mono
gams ../models/pbuc_pwl.gms  --XLS=../data/params_samsun.xlsx --FPRICE=9 --COMMIT=168 --LOOK=48 --OUT=samsun_c168_l48
gams ../models/pbuc_miqp.gms --XLS=../data/params_samsun.xlsx --FPRICE=8 --QFORM=ineq --COMMIT=8784 --LOOK=0 --WRESLIM=36000 --OUT=samsun_miqp_F8_mono_ineq
```

### Options

| Option | Models | Meaning [default] |
|---|---|---|
| `--XLS` | all | parameter file [`../data/params_unitA.xlsx`] |
| `--FPRICE` | all | gas price in USD/MMBtu [value in the parameter file] |
| `--COMMIT` | all | length of the commitment block in hours; 8784 = full year [168] |
| `--LOOK` | all | look-ahead in hours; 0 = myopic planning [48] |
| `--WRESLIM` | all | time limit per window in seconds [3600] |
| `--OPTCR` | all | relative optimality gap [0] |
| `--OUT` | all | prefix of the output files |
| `--SUM` | all | summary file; each run appends one line [`rh_summary.csv`, `rh_miqp_summary.csv`, `rh_outage_summary.csv`] |
| `--QFORM` | MIQP | `eq` or `ineq` [eq] |
| `--NSEG` | PWL | number of PWL segments [10] |
| `--FIL` | PWL | `calc`: segment slopes computed from the coefficients; `excel`: read from the symbol `f_il` of the parameter file [calc] |
| `--SEQ` | PWL | sequencing binaries for all units (`all`) or only for units with A < 0 (`auto`) [all] |
| `--PM` | outages | planned maintenance: `none`, `auto` (the interval with the lowest mean price) or a start hour [none] |
| `--PMDUR` | outages | length of the maintenance period in hours [336] |
| `--NOTICE` | outages | a maintenance period starting within this many hours after a block is included in the window [168] |
| `--FOR`, `--MTTR`, `--SEED` | outages | forced outage rate [0], mean time to repair in hours [48], seed of the outage sample [1] |
| `--INFO` | outages | `full`: outages known in advance; `reveal`: an outage becomes known in its first hour [full] |
| `--OFFSET` | outages | hour of the first block boundary [0] |
| `--ALIGN` | outages | `yes`: after an outage, the block ends at the next regular boundary [no] |

### Output

Each run writes

* `<OUT>_report.csv`: settings, annual results, the windows (status, objective, gap, solver time) and the hourly schedule (`hour, Q, u, sUP, sDOWN, gas_MMBtu, price`);
* `<OUT>_out.gdx`: the solution;
* one line in the summary file with the annual profit (`profitExact` for the PWL models, `profit` for the MIQP), the value of the PWL objective (`profitPWL`), the number of start-ups and hours online, the annual and peak hourly gas consumption (`gasTotal`, `gasPeak`, MMBtu), the solver time and the number of windows solved to optimality or stopped at the time limit. The outage model also reports the number and hours of forced outages and the start of the maintenance period.

### DP

```
cd models
python pbuc_dp.py --unit unitA --F 9 --qstep 10
```

writes the hourly schedule to `dp_unitA_F9.csv` and prints the annual profit. The output step `--qstep` was 10 MW and 1 MW in the paper; with 1 MW, the run for Samsun takes about 16 days.

## Reproducing the experiments

The analysis scripts identify runs by the names given with `--OUT` and `--SUM`. The commands below use the names expected by the scripts; `<u>` is `samsun`, `unitA` or `gebze`, and `params_<u>.xlsx` the corresponding parameter file. Runs whose hourly reports are used for figures at different gas prices should be carried out in separate folders, because the report files of runs with the same `--OUT` overwrite each other.

**1. Gas-price analysis** (PWL, full year). For F = 7, 7.5, ..., 11:
```
gams ../models/pbuc_pwl.gms --XLS=../data/params_<u>.xlsx --FPRICE=<F> --COMMIT=8784 --LOOK=0 --SUM=rh_summary_price_sensitivity.csv --OUT=<u>_mono_F<F>
```

**2. Rolling horizon with the PWL model.** For F = 8 and 9, each in its own folder, the full-year run and all combinations of COMMIT = 24, 168, 720 and LOOK = 0, 24, 48, 168:
```
gams ../models/pbuc_pwl.gms --XLS=../data/params_<u>.xlsx --FPRICE=<F> --COMMIT=8784 --LOOK=0 --SUM=rh_summary_Fi<F>.csv --OUT=<u>_mono
gams ../models/pbuc_pwl.gms --XLS=../data/params_<u>.xlsx --FPRICE=<F> --COMMIT=<C> --LOOK=<L> --SUM=rh_summary_Fi<F>.csv --OUT=<u>_c<C>_l<L>
```
The monthly comparison of the paper uses, in addition, the runs `--FPRICE=9 --COMMIT=24 --LOOK=0 --OUT=samsun_F9_c24_l0` and `--FPRICE=9 --COMMIT=168 --LOOK=0 --OUT=samsun_F9_c168_l0` for Samsun.

**3. Comparison of the solution approaches** (F = 9). PWL with 3 and 10 segments (`--NSEG=3 --OUT=<u>_mono_L3_F9`; the runs with 10 segments are those of step 2), the full-year MIQP of each unit (step 4) and the DP (`pbuc_dp.py --F 9 --qstep 10` and `--qstep 1`).

**4. MIQP.** With `--SUM=rh_miqp_summary.csv`:
* rolling horizon at F = 8 for all combinations of COMMIT and LOOK, `--OUT=<u>_miqp_F8_c<C>_l<L>`;
* full year at F = 8 and 9 for Unit A and Gebze, `--COMMIT=8784 --LOOK=0 --OUT=<u>_miqp_F<F>_mono`;
* Samsun, full year, `--QFORM=ineq --WRESLIM=36000` at F = 8 and 9 (`--OUT=samsun_miqp_F<F>_mono_ineq`) and `--QFORM=eq --WRESLIM=36000` at F = 8 (`--OUT=samsun_miqp_F8_mono_eq`);
* Samsun at F = 9 with weekly blocks, `--COMMIT=168 --LOOK=48` and `--LOOK=168` (`--OUT=samsun_miqp_F9_c168_l<L>`).

**5. Planned maintenance and forced outages** (Samsun and Unit A, F = 9). All runs use `../models/pbuc_pwl_outages.gms --XLS=../data/params_<u>.xlsx --FPRICE=9 --PM=auto --PMDUR=336 --SUM=rh_outage_summary.csv`, and
* maintenance only: `--FOR=0 --INFO=full` with `--COMMIT=8784 --LOOK=0 --OUT=<u>_pm_mono` and all combinations of COMMIT and LOOK (`--OUT=<u>_pm_c<C>_l<L>`);
* forced outages, for seeds S = 1, ..., 20, with `--FOR=0.05 --MTTR=48 --SEED=<S>`:

| Configuration | Options | `--OUT` |
|---|---|---|
| reference, outages known | `--INFO=full --COMMIT=8784 --LOOK=0` | `<u>_full_mono_s<S>` |
| weekly, known | `--INFO=full --COMMIT=168 --LOOK=0` and `--LOOK=48` | `<u>_full_c168_l<L>_s<S>` |
| full-year re-planning | `--INFO=reveal --COMMIT=8784 --LOOK=8784` | `<u>_rev_fy_s<S>` |
| weekly, revealed | `--INFO=reveal --COMMIT=168 --LOOK=0` and `--LOOK=48` | `<u>_rev_c168_l<L>_s<S>` |
| daily, revealed | `--INFO=reveal --COMMIT=24 --LOOK=0` | `<u>_rev_c24_l0_s<S>` |

**6. Position of the block boundaries.** Same base options as step 5 with `--SUM=offset_summary.csv`:
* without forced outages (`--FOR=0 --INFO=full --LOOK=0`): `--COMMIT=24 --OFFSET=<O>` for O = 0, 6, 12, 18 (`--OUT=<u>_offA_c24_o<O>`) and `--COMMIT=168 --OFFSET=<O>` for O = 0, 12, 84 (`--OUT=<u>_offA_c168_o<O>`);
* aligned blocks with forced outages: `--FOR=0.05 --MTTR=48 --SEED=<S> --INFO=reveal --LOOK=0 --ALIGN=yes` with `--COMMIT=24` and `168` (`--OUT=<u>_offB_c<C>_s<S>`).

**7. Forced outage rate.** The forced-outage runs of step 5 with `--FOR=0.02` and `--FOR=0.10`, `--SUM=for_sensitivity_summary.csv` and the prefix `<u>_FOR<rate>_` in `--OUT` (for example `samsun_FOR0.10_rev_fy_s3`).

The full experiment set requires several days of computation, mostly for the MIQP runs with a time limit of 10 h and for the DP with a 1 MW grid. All other runs take seconds to minutes each.

A loop in the Windows command prompt, for example for step 1, can be written as
```
for %u in (samsun unitA gebze) do for %F in (7 7.5 8 8.5 9 9.5 10 10.5 11) do gams ../models/pbuc_pwl.gms --XLS=../data/params_%u.xlsx --FPRICE=%F --COMMIT=8784 --LOOK=0 --SUM=rh_summary_price_sensitivity.csv --OUT=%u_mono_F%F
```

## Measures and figures

```
python ../analysis/compute_metrics.py --dirs <folders with the summary files>
python ../analysis/make_figures.py   --dirs <folders with the summary and report files>
```

`compute_metrics.py` computes, for each rolling-horizon run, the relative profit loss Δπ = (π_ref − π)/π_ref × 100 and the relative deviation of the annual gas consumption ΔG = (G − G_ref)/G_ref × 100 from the full-year reference. For the outage experiments, the reference is the full-year solution with known outages of the same sample or full-year re-planning. The results are written to `metrics/metrics_*.csv`. `make_figures.py` writes the figures of the paper to `figures/`; figures whose input files are missing are skipped and the missing files are listed.

## Notes

* All GAMS runs use relative and absolute optimality gaps of zero. Because the solver satisfies the constraints within its feasibility tolerance of 10⁻⁶, profits that differ by less than about 10⁻⁶ in relative terms should be treated as equal.
* For Samsun at F = 9, the full-year MIQP reaches the time limit of 10 h with a gap of 0.0035%. The best known solution at this price is obtained by the MIQP rolling horizon with `--COMMIT=168 --LOOK=168`.
* Gebze is not committed at gas prices of 9 USD/MMBtu or more, so its relative losses are not defined at these prices.
* A small `maxGap` can be reported for windows whose objective value is close to zero although they are solved to optimality; the column `windowsOptimal` shows the number of windows solved to optimality.

## License

The code is released under the MIT License ([LICENSE](LICENSE)). The price data are published by EPİAŞ; the unit parameters are derived from the public sources cited in the paper.
