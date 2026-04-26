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
keep if inrange(month, tm(2020m1), tm(2025m12))

capture confirm variable stk_id
if _rc {
    egen long stk_id = group(stkcd)
}

xtset stk_id month

label variable price_delay "价格延迟"
label variable synch "股价同步性"
label variable resid_vol "残差波动率"
label variable ln_cir_mktcap "流通市值对数"
label variable pb "PB"
label variable turnover "换手率"
label variable leverage "杠杆率"
label variable roa "ROA"
label variable rd_intensity "研发强度"
label variable firm_age "上市年龄"
label variable inst_hold "机构持股比例"

* Baseline controls match the main DID specification.
local controls ln_cir_mktcap pb turnover leverage roa rd_intensity ///
    inst_hold

* Event-time bins: omit t = -1 as the reference period.
capture drop evt_pre12 evt_m11 evt_m10 evt_m9 evt_m8 evt_m7 evt_m6 ///
    evt_m5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2

gen byte evt_pre12 = treated == 1 & rel_month <= -12 if !missing(treated, rel_month)
forvalues k = 11(-1)2 {
    gen byte evt_m`k' = treated == 1 & rel_month == -`k' if !missing(treated, rel_month)
}
gen byte evt_0  = treated == 1 & rel_month == 0 if !missing(treated, rel_month)
gen byte evt_p1 = treated == 1 & rel_month == 1 if !missing(treated, rel_month)
gen byte evt_p2 = treated == 1 & rel_month >= 2 if !missing(treated, rel_month)

label variable evt_pre12 "事件时间<=-12期"
forvalues k = 11(-1)2 {
    label variable evt_m`k' "事件时间=-`k'期"
}
label variable evt_0  "事件当期"
label variable evt_p1 "事件后第1期"
label variable evt_p2 "事件后第2期及以后"

local event_terms evt_pre12 evt_m11 evt_m10 evt_m9 evt_m8 evt_m7 evt_m6 ///
    evt_m5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2
local pre_terms evt_pre12 evt_m11 evt_m10 evt_m9 evt_m8 evt_m7 evt_m6 ///
    evt_m5 evt_m4 evt_m3 evt_m2

eststo clear
foreach y in price_delay synch resid_vol {
    quietly reghdfe `y' `event_terms' `controls', absorb(stk_id month) vce(cluster stk_id)
    capture testparm `pre_terms'
    if _rc == 0 {
        estadd scalar pretrend_p = r(p)
        estadd scalar pretrend_F = r(F)
    }
    else {
        estadd scalar pretrend_p = .
        estadd scalar pretrend_F = .
    }
    eststo `y'_event
}

esttab price_delay_event synch_event resid_vol_event using "$tables/event_study_results.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("做市商制度对企业定价效率影响的事件研究结果") ///
    mtitles("价格延迟" "股价同步性" "残差波动率") ///
    keep(`event_terms') ///
    stats(N r2_a pretrend_p, labels("观测值" "调整后R方" "平行趋势检验p值")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

esttab price_delay_event synch_event resid_vol_event using "$tables/event_study_results.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(`event_terms') ///
    stats(N r2_a pretrend_p, labels("观测值" "调整后R方" "平行趋势检验p值"))

di as result "Saved event-study tables to $tables"
