# Annual Profit-Based Unit Commitment for Price-Taking Natural Gas-Fired Power Plants

Models and sample data for the profit-based unit commitment (PBUC) problem of a
price-taking natural gas-fired generating unit solved over a **full annual
horizon of 8,784 hours** (2024, a leap year).

The repository contains the three solution approaches compared in the
accompanying paper:

| Approach | File | Type | Notes |
| --- | --- | --- | --- |
| Exact MIQP | [`gams/basic_model.gms`](gams/basic_model.gms) | GAMS / MIQCP | Exact quadratic heat-rate function, Eqs. (1)–(11) |
| Piecewise linear MILP | [`gams/basic_linearization.gms`](gams/basic_linearization.gms) | GAMS / MIP | Sequentially filled PWL reformulation, Eqs. (12)–(16) |
| Dynamic programming | [`python/DPmodel.py`](python/DPmodel.py) | Python | Two-dimensional state (operating duration, previous-hour output), Eq. (17) |

Because the generating company is modelled as a price taker without
portfolio-wide coupling constraints, the annual profit-maximisation problem
decomposes into one independent subproblem per generating unit. All three models
therefore solve a single unit at a time, and each hourly dispatch decision maps
directly onto physical natural gas consumption through the quadratic heat-rate
function.

## Repository structure

```
.
├── data/                                    input data (see data/README.md)
│   ├── 2024_Price.csv                       hourly market clearing prices, 2024
│   ├── generator_params1.xlsx               unit parameters for the DP model
│   ├── basic_model_parametre_sample.xlsx    workbook for the exact MIQP model
│   └── basic_linearization_sampledata.xlsx  workbook for the PWL MILP model
├── docs/
│   └── model_to_code_map.md                 paper notation ↔ code identifiers
├── gams/
│   ├── basic_model.gms                      exact MIQP formulation
│   └── basic_linearization.gms              piecewise linear MILP formulation
├── python/
│   └── DPmodel.py                           state-dependent dynamic program
├── results/                                 created output files land here
├── requirements.txt
├── CITATION.cff
└── LICENSE
```

## Requirements

**Dynamic programming model (Python)**

* Python 3.9 or newer
* `pandas` and `openpyxl` (`pip install -r requirements.txt`)

**MIQP and PWL models (GAMS)**

* GAMS with a solver that handles MIQCP and MIP problems. The reported results
  were produced with Gurobi; the solver is selected in the option block of each
  model file.
* GDXXRW to read the Excel parameter workbooks. GDXXRW requires Microsoft
  Excel, so the GAMS models run on Windows. On other platforms the workbooks
  have to be converted to GDX or to GAMS include files beforehand.

The experiments reported in the paper were run on a workstation with an Intel
Core i9-14900K processor and 96 GB of RAM.

## Quick start

### Dynamic programming (Python)

```bash
pip install -r requirements.txt
python python/DPmodel.py
```

The script reads `data/2024_Price.csv` and `data/generator_params1.xlsx`,
solves the DP over the horizon set by the variable `x` in the script
(`x = 8784` for the full year, `x = 2184` for the first three months) and writes
`results/results1.csv`.

Paths are resolved relative to the script file, so the command above works from
any working directory. The per-stage policies are written to
`results/policy_store/` during the backward recursion and read back during the
forward reconstruction, which keeps peak memory use bounded over the annual
horizon. Run time grows quickly as the dispatch step `q_step` is refined: the
full-year run of the benchmark unit takes hours at `q_step = 10` MW and days at
`q_step = 1` MW.

### Exact MIQP and PWL MILP (GAMS)

```bash
cd gams
gams basic_model.gms          # exact MIQP
gams basic_linearization.gms  # piecewise linear MILP
```

Both files start with a short configuration block that holds every file path:

```gams
$setglobal XLS_FILE ..\data\basic_model_parametre_sample.xlsx
$setglobal GDX_IN   basic_model_parametre_sample.gdx
$setglobal GDX_OUT  ..\results\2024_parametersOUT.gdx
$setglobal CSV_OUT  ..\results\outputs1_model1.csv
$setglobal XLS_OUT  ..\results\2024_OUTPUT.xlsx
```

The paths are relative to the directory from which GAMS is started, which is
why the commands above change into `gams/` first. Adjust the block if your
folder layout differs.

## Input data

`data/README.md` documents every sheet and column. In short:

* **Hourly data** – the 2024 hourly market clearing price series (`PTF`,
  USD/MWh) published by Energy Exchange Istanbul (EPİAŞ), plus the maintenance
  indicator and the hourly output limits of each unit.
* **Generator data** – the quadratic heat-rate coefficients, fuel price,
  start-up cost, minimum up/down times, ramp limits and capacity limits of the
  unit.
* **Planning horizon** – in the GAMS workbooks the horizon is defined by the
  cell ranges listed in the `index` sheet, so a shorter horizon is obtained by
  editing that sheet only. The workbook of the PWL model also ships ready-made
  index sheets for two-week, one-month, four-month and six-month horizons.

The sample workbooks describe the **literature benchmark unit (Unit A)** as
generator `G1`. The technical data of the two Turkish case plants studied in the
paper (Samsun CCGT and Gebze-Dilovası) are not included here; they can be
reconstructed from the public sources cited in the paper.

## Outputs

The `results/` folder is empty in this repository: solution files are not
distributed and are regenerated by running the models. The paper reports
several configurations per unit (three fuel prices, two piecewise linear segment
counts and two dispatch discretisation steps), and the corresponding objective
values and run times are given in the paper itself. Running a model writes the
files below; they are excluded from version control by `.gitignore`.

| File | Written by | Content |
| --- | --- | --- |
| `results/results1.csv` | Python DP | One row per hour: stage `t`, state `(s, q_prev)`, chosen action, dispatch `q_t`, hourly profit, and the total profit of the schedule |
| `results/policy_store/policy_t_*.pkl` | Python DP | Optimal policy of each backward stage (intermediate files) |
| `results/outputs1_model1.csv`, `results/outputs_linearization.csv` | GAMS | Model and solver status, revenue, fuel cost, start-up cost, net profit and the hourly `Q`, `u`, `sUP`, `sDOWN` series |
| `results/2024_parametersOUT.gdx` | GAMS | Solution in GDX format |
| `results/2024_OUTPUT.xlsx` | GAMS | Same solution written back to Excel by GDXXRW |

When several configurations are run one after another, the output paths in the
`$setglobal` block of the GAMS files (and `RESULT_FILE` in the Python script)
should be changed between runs, otherwise each run overwrites the previous one.

Hourly natural gas consumption follows from the dispatch series through the
quadratic heat-rate function `A*Q² + B*Q + C`, which is why the exact
coefficients are kept in the MIQP and DP formulations.

## Configurations reported in the paper

| Setting | Values used |
| --- | --- |
| Planning horizon | 720 hours up to the full 8,784 hours of 2024 |
| Fuel price `F` | 8, 9 (baseline, BOTAŞ tariff for electricity generation) and 10 USD/MMBtu |
| DP dispatch step `q_step` | 10 MW and 1 MW |
| PWL segments `L` | 3 and 10 |
| MIQP solver time limit | 198,000 s (55 hours), set through `reslim` |

Note that neither the PWL reformulation nor the DP framework returns an
optimality certificate for the original quadratic problem. Their objective
values are compared with the exact MIQP formulation rather than presented as
optimal.

## Notes on the shipped sample data

* The fuel price differs between the two sample sets: the GAMS workbooks carry
  `f_i = 8` USD/MMBtu (low fuel-price scenario) and
  `generator_params1.xlsx` carries `F = 9` USD/MMBtu (baseline scenario). Change
  the fuel price in cell `B3` of the `GeneratorParameters` sheet, or in the `F`
  row of `generator_params1.xlsx`, to switch scenarios.
* `data/2024_Price.csv` contains 8,808 hourly records: the 8,784 hours of 2024
  followed by the 24 hours of 1 January 2025. The DP script reads the first `x`
  rows, so the extra day is not used for the annual runs.
* In `basic_linearization.gms` the number of PWL segments is set by the set `l`
  (`/l1*l3/` for `L = 3`). The slope table `f_il` in the `Linearization` sheet,
  and the cell range it is read from in the `index` sheet, must describe the
  same number of segments.
* The `Demand` equation of the GAMS models bounds the hourly output by
  `Q_D + reserve`. It is not part of the price-taker formulation of the paper;
  with the sample data (`Q_D = 1000`, `reserve = 10000`) it is not binding for
  the case units.

## Reproducibility note

The model statements are the ones used to produce the published results. The
only changes made when preparing this repository were:

* comments, declaration texts and docstrings written in English;
* absolute Windows paths replaced by the `$setglobal` configuration block in the
  GAMS files, and by paths resolved relative to the script file in the Python
  file;
* the GDXXRW control file renamed from `seyma.txt` to `gdxxrw_index.txt`.

No set, parameter, variable, equation, option, solver setting or algorithmic
step was modified. Running `python/DPmodel.py` on an identical input produces
the same schedule and the same total profit as the original script.

## Citation

If you use this code, please cite the paper. A machine-readable entry is
provided in [`CITATION.cff`](CITATION.cff):

> Ş. Kaya, A. D. Yücekaya, M. G. Özel, E. Çelebi, P. G. Canbolat, "Solving
> Large-Scale Annual Profit-Based Unit Commitment Problems for Price-Taking
> Natural Gas Power Plants".

## License

Released under the MIT License; see [`LICENSE`](LICENSE). The electricity market
data are published by Energy Exchange Istanbul (EPİAŞ) and are redistributed
here only as a sample input; please refer to EPİAŞ for their terms of use.

## Acknowledgments

This research was supported by TÜBİTAK under Grant No. 224M197 through the
1001 – Scientific and Technological Research Projects Funding Program.
