# Input data

Sample input files for the three models. All files describe the **literature
benchmark unit (Unit A)**, which appears as generator `G1` in the GAMS
workbooks, together with the 2024 hourly market clearing prices of the Turkish
day-ahead market.

| File | Used by | Format |
| --- | --- | --- |
| `2024_Price.csv` | `python/DPmodel.py` | CSV, 8,808 hourly records |
| `generator_params1.xlsx` | `python/DPmodel.py` | one sheet, name/value pairs |
| `basic_model_parametre_sample.xlsx` | `gams/basic_model.gms` | GDXXRW workbook |
| `basic_linearization_sampledata.xlsx` | `gams/basic_linearization.gms` | GDXXRW workbook |

---

## `2024_Price.csv`

Hourly market clearing price (MCP, in Turkish *Piyasa Takas Fiyatı*, PTF)
published by Energy Exchange Istanbul (EPİAŞ).

| Column | Meaning |
| --- | --- |
| `Tarih` | date, `d.mm.yyyy` |
| `Saat` | hour of the day, `HH:MM` |
| `PTF (USD/MWh)` | market clearing price in USD/MWh |

The file holds 8,808 records: the 8,784 hours of 2024 (a leap year) followed by
the 24 hours of 1 January 2025. `DPmodel.py` reads the first `x` rows of the
last column, with `x = 8784` for the annual runs, so the extra day is unused.

---

## `generator_params1.xlsx`

A single sheet with the parameter name in column A and its value in column B.
`DPmodel.py` reads it into a dictionary, so the row order does not matter, but
every name below must be present.

| Name | Meaning | Unit | Sample value |
| --- | --- | --- | --- |
| `A` | quadratic heat-rate coefficient | $/MW² | −0.0014444 |
| `B` | linear heat-rate coefficient | $/MWh | 7.463333 |
| `C` | no-load heat-rate coefficient | $/h | 248.222222 |
| `F` | natural gas price | $/MMBtu | 9 |
| `startup_cost` | start-up cost | $ | 12,000 |
| `idle_cost` | cost charged per offline hour | $ | 0 |
| `L_up` | minimum up time | h | 4 |
| `L_down` | minimum down time | h | 6 |
| `q_min` | minimum output when online | MW | 100 |
| `q_max` | maximum output when online | MW | 300 |
| `ramp_up` | ramp-up limit, online → online | MW/h | 100 |
| `ramp_down` | ramp-down limit, online → online | MW/h | 100 |
| `startup_ramp` | start-up ramp limit, offline → online | MW/h | 100 |
| `shutdown_ramp` | shut-down ramp limit, online → offline | MW/h | 100 |
| `q_step` | dispatch discretisation step Δq | MW | 10 |

`q_step` controls the size of the DP state space. The paper reports runs with
Δq = 10 MW and Δq = 1 MW; the finer step increases run time substantially.

---

## GDXXRW workbooks

Both GAMS workbooks share the same layout. GDXXRW is told to read the sheet
named `index`, which lists one entry per symbol: its type (`par` or `set`), its
name, the cell range holding the values, and the row/column dimensions.
Changing the planning horizon therefore means editing the row ranges in the
`index` sheet only.

### Sheet `hour`

Timestamp of every hour in column A and its label (`H1` … `H8784`) in column B.
Column B provides the set `t`.

### Sheet `HourlyParameters`

Blocks of two columns, each block repeating the hour label so that GDXXRW can
read it as a one-dimensional parameter.

| Columns | Symbol | Meaning |
| --- | --- | --- |
| `A:B` | `e_price(t)` | market clearing price, USD/MWh |
| `D:E` | `reserve(t)` | reserve term of the output bound |
| `G:H` | `Q_D(t)` | market term of the output bound |
| `J:N` | `M(t,i)` | maintenance indicator, 1 = unit unavailable |
| `P:T` | `Qmin(t,i)` | minimum output when online, MW |
| `V:Z` | `Qmax(t,i)` | maximum output when online, MW |

The unit blocks contain columns for `G1`–`G4`, but the `index` sheet reads the
`G1` column only, so only the benchmark unit enters the model. In the sample
data `G1` has `M = 0`, `Qmin = 100` MW and `Qmax = 300` MW in every hour.

### Sheet `GeneratorParameters`

Row 3 holds the values for `G1`, again in blocks of two columns:

| Columns | Symbol | Meaning |
| --- | --- | --- |
| `A:B` | `F(i)` | natural gas price, $/MMBtu (8 in the shipped files) |
| `D:E` | `A(i)` | quadratic heat-rate coefficient |
| `G:H` | `B(i)` | linear heat-rate coefficient |
| `J:K` | `C(i)` | no-load heat-rate coefficient |
| `M:N` | `SC(i)` | start-up cost, $ |
| `P:Q` | `RampUp(i)` | ramp-up limit, online → online |
| `S:T` | `StartRampUp(i)` | start-up ramp limit |
| `V:W` | `RampDown(i)` | ramp-down limit, online → online |
| `Y:Z` | `CloseRampDown(i)` | shut-down ramp limit |
| `AB:AC` | `Lup(i)` | minimum up time, h |
| `AE:AF` | `Ldown(i)` | minimum down time, h |

### Sheet `Linearization` (PWL workbook only)

Builds the marginal slope of each piecewise linear segment. Columns `B:G` hold
the heat-rate coefficients, the number of segments `L`, and the capacity limits;
column `I` gives the segment breakpoints, column `J` the slope between two
consecutive breakpoints, and columns `K:L` present the same slopes as the
parameter `f_il(l,i)` that GAMS reads.

The shipped file is configured for `L = 3` (`l1`–`l3`), which matches the set
`l /l1*l3/` in `basic_linearization.gms`. For `L = 10`, extend the set in the
model, extend the slope table, and update the `f_il` range in the `index` sheet
so that all three describe ten segments.

### Alternative index sheets (PWL workbook only)

The sheets named for two-week, one-month, four-month and six-month horizons hold
the same entries as `index` with shorter row ranges. To use one of them, copy
its contents into the `index` sheet, since the models always read the sheet
named `index`.

---

## Source and terms

The price series is public information published by EPİAŞ
(<https://www.epias.com.tr>) and is redistributed here only as a sample input;
please refer to EPİAŞ for their terms of use. The benchmark unit parameters are
derived from the thermal-generator data of Djurovic, Milacic and Krsulja (2012),
"A simplified model of quadratic cost function for thermal generators",
Proceedings of the 23rd International DAAAM Symposium.
