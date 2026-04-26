version 17
set more off
set varabbrev off

if "$project" == "" {
    global project "`c(pwd)'"
    global data "$project/data"
    global final "$data/final"
    global output "$project/output"
    global tables "$output/tables"
    global ado "$project/ado"
    global ado_plus "$ado/plus"
    global ado_personal "$ado/personal"
}

capture mkdir "$tables"
capture mkdir "$ado"
capture mkdir "$ado_plus"
capture mkdir "$ado_personal"

sysdir set PLUS "$ado_plus"
sysdir set PERSONAL "$ado_personal"

capture which reghdfe
if _rc {
    ssc install reghdfe, replace
}
capture which esttab
if _rc {
    ssc install estout, replace
}

use "$final/monthly_panel.dta", clear

* Keep the core sample window from the project memory.
keep if inrange(month, tm(2020m1), tm(2025m12))

* Main DID regressor.
gen byte did = treated * post
label variable did "DID"
label variable price_delay "价格延迟"
label variable synch "股价同步性"
label variable resid_vol "残差波动率"
label variable ln_cir_mktcap "流通市值对数"
label variable ln_tot_mktcap "总市值对数"
label variable pb "PB"
label variable turnover "换手率"
label variable leverage "杠杆率"
label variable roa "ROA"
label variable rd_intensity "研发强度"
label variable firm_age "上市年龄"
label variable inst_hold "机构持股比例"

capture confirm variable stk_id
if _rc {
    egen long stk_id = group(stkcd)
}

xtset stk_id month

* Baseline controls.
local controls ln_cir_mktcap pb turnover leverage roa rd_intensity ///
    inst_hold

eststo clear
foreach y in price_delay synch resid_vol {
    quietly reghdfe `y' did `controls', absorb(stk_id month) vce(cluster stk_id)
    eststo `y'
}

esttab price_delay synch resid_vol using "$tables/main_results.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("做市商制度对企业定价效率影响的基准回归结果") ///
    mtitles("价格延迟" "股价同步性" "残差波动率") ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

* A compact CSV-style export for quick inspection.
esttab price_delay synch resid_vol using "$tables/main_results.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方"))

di as result "Saved regression tables to $tables"
