version 17
set more off
set varabbrev off

if "$project" == "" {
    global project "`c(pwd)'"
    global data "$project/data"
    global final "$data/final"
    global output "$project/output"
    global tables "$output/tables"
    global figures "$output/figures"
    global ado "$project/ado"
    global ado_plus "$ado/plus"
    global ado_personal "$ado/personal"
}

capture mkdir "$figures"
capture mkdir "$ado"
capture mkdir "$ado_plus"
capture mkdir "$ado_personal"

sysdir set PLUS "$ado_plus"
sysdir set PERSONAL "$ado_personal"

capture which reghdfe
if _rc {
    ssc install reghdfe, replace
}

* ----------------------------------------------------------------------
* Figure 5-1. Event-analysis plot for parallel-trend assessment
* ----------------------------------------------------------------------
use "$final/monthly_panel.dta", clear
keep if inrange(month, tm(2020m1), tm(2025m12))

capture confirm variable stk_id
if _rc {
    egen long stk_id = group(stkcd)
}

xtset stk_id month

local controls ln_cir_mktcap pb turnover leverage roa rd_intensity ///
    inst_hold

capture drop evt_pre12 evt_m11 evt_m10 evt_m9 evt_m8 evt_m7 evt_m6 ///
    evt_m5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2

gen byte evt_pre12 = treated == 1 & rel_month <= -12 if !missing(treated, rel_month)
forvalues k = 11(-1)2 {
    gen byte evt_m`k' = treated == 1 & rel_month == -`k' if !missing(treated, rel_month)
}
gen byte evt_0  = treated == 1 & rel_month == 0 if !missing(treated, rel_month)
gen byte evt_p1 = treated == 1 & rel_month == 1 if !missing(treated, rel_month)
gen byte evt_p2 = treated == 1 & rel_month >= 2 if !missing(treated, rel_month)

local event_terms evt_pre12 evt_m11 evt_m10 evt_m9 evt_m8 evt_m7 evt_m6 ///
    evt_m5 evt_m4 evt_m3 evt_m2 evt_0 evt_p1 evt_p2

tempfile event_plot
postfile event_handle str20 depvar int event_time str8 event_label ///
    double beta se lb ub using `event_plot', replace

foreach spec in ///
    "price_delay PriceDelay" ///
    "synch SYNCH" ///
    "resid_vol ResidVol" {
    tokenize `"`spec'"'
    local y `1'
    local dep `2'

    quietly reghdfe `y' `event_terms' `controls', absorb(stk_id month) vce(cluster stk_id)

    foreach pair in ///
        "evt_pre12 -12 <=-12" ///
        "evt_m11   -11 -11" ///
        "evt_m10   -10 -10" ///
        "evt_m9     -9  -9" ///
        "evt_m8     -8  -8" ///
        "evt_m7     -7  -7" ///
        "evt_m6     -6  -6" ///
        "evt_m5     -5  -5" ///
        "evt_m4     -4  -4" ///
        "evt_m3     -3  -3" ///
        "evt_m2     -2  -2" ///
        "evt_0       0   0" {
        tokenize `"`pair'"'
        local var `1'
        local etime `2'
        local elabel `3'
        local beta = _b[`var']
        local se = _se[`var']
        local lb = `beta' - 1.96 * `se'
        local ub = `beta' + 1.96 * `se'
        post event_handle ("`dep'") (`etime') ("`elabel'") (`beta') (`se') (`lb') (`ub')
    }
}
postclose event_handle

use `event_plot', clear

twoway ///
    (rcap ub lb event_time if depvar == "PriceDelay", lcolor(navy)) ///
    (connected beta event_time if depvar == "PriceDelay", sort msymbol(circle) ///
        mcolor(navy) lcolor(navy) lwidth(medthick)), ///
    xline(-1, lpattern(dash) lcolor(cranberry)) ///
    yline(0, lpattern(shortdash) lcolor(gs8)) ///
    xlabel(-12(2)0, angle(45) labsize(small)) ///
    ylabel(, angle(0) labsize(small)) ///
    xtitle("事件时间（月）") ytitle("估计系数") ///
    title("价格延迟") legend(off) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(g_event_pd, replace) nodraw

twoway ///
    (rcap ub lb event_time if depvar == "SYNCH", lcolor(forest_green)) ///
    (connected beta event_time if depvar == "SYNCH", sort msymbol(circle) ///
        mcolor(forest_green) lcolor(forest_green) lwidth(medthick)), ///
    xline(-1, lpattern(dash) lcolor(cranberry)) ///
    yline(0, lpattern(shortdash) lcolor(gs8)) ///
    xlabel(-12(2)0, angle(45) labsize(small)) ///
    ylabel(, angle(0) labsize(small)) ///
    xtitle("事件时间（月）") ytitle("估计系数") ///
    title("股价同步性") legend(off) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(g_event_syn, replace) nodraw

twoway ///
    (rcap ub lb event_time if depvar == "ResidVol", lcolor(maroon)) ///
    (connected beta event_time if depvar == "ResidVol", sort msymbol(circle) ///
        mcolor(maroon) lcolor(maroon) lwidth(medthick)), ///
    xline(-1, lpattern(dash) lcolor(cranberry)) ///
    yline(0, lpattern(shortdash) lcolor(gs8)) ///
    xlabel(-12(2)0, angle(45) labsize(small)) ///
    ylabel(, angle(0) labsize(small)) ///
    xtitle("事件时间（月）") ytitle("估计系数") ///
    title("残差波动率") legend(off) ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(g_event_rv, replace) nodraw

graph combine g_event_pd g_event_syn g_event_rv, ///
    cols(1) xcommon ///
    title("图5-1 做市商制度对定价效率的平行趋势检验型事件分析图") ///
    note("注：以做市前1个月为基期，主要用于直观检验做市前是否存在系统性趋势差异。") ///
    imargin(small) xsize(8) ysize(12) iscale(1) ///
    graphregion(color(white)) name(fig_event_study, replace)

graph export "$figures/figure_5_1_event_study.png", width(3000) replace
graph export "$figures/figure_5_1_event_study.pdf", replace
graph save "$figures/figure_5_1_event_study.gph", replace

* ----------------------------------------------------------------------
* Figure 5-2. Randomization placebo distributions
* ----------------------------------------------------------------------
use "$tables/placebo_draws.dta", clear

quietly summarize actual_beta if depvar == "price_delay", meanonly
local actual_pd = r(mean)
quietly summarize actual_beta if depvar == "synch", meanonly
local actual_syn = r(mean)
quietly summarize actual_beta if depvar == "resid_vol", meanonly
local actual_rv = r(mean)

histogram beta if depvar == "price_delay", ///
    frequency color(navy%50) lcolor(navy) ///
    xline(`actual_pd', lcolor(cranberry) lwidth(medthick)) ///
    ylabel(, angle(0) labsize(small)) ///
    xtitle("安慰剂 DID 系数") ytitle("频数") ///
    title("价格延迟") legend(off) ///
    note("红线表示真实 DID 估计系数") ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(g_placebo_pd, replace) nodraw

histogram beta if depvar == "synch", ///
    frequency color(forest_green%50) lcolor(forest_green) ///
    xline(`actual_syn', lcolor(cranberry) lwidth(medthick)) ///
    ylabel(, angle(0) labsize(small)) ///
    xtitle("安慰剂 DID 系数") ytitle("频数") ///
    title("股价同步性") legend(off) ///
    note("红线表示真实 DID 估计系数") ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(g_placebo_syn, replace) nodraw

histogram beta if depvar == "resid_vol", ///
    frequency color(maroon%45) lcolor(maroon) ///
    xline(`actual_rv', lcolor(cranberry) lwidth(medthick)) ///
    ylabel(, angle(0) labsize(small)) ///
    xtitle("安慰剂 DID 系数") ytitle("频数") ///
    title("残差波动率") legend(off) ///
    note("红线表示真实 DID 估计系数") ///
    graphregion(color(white)) plotregion(color(white)) ///
    name(g_placebo_rv, replace) nodraw

graph combine g_placebo_pd g_placebo_syn g_placebo_rv, ///
    cols(1) ///
    title("图5-2 安慰剂检验结果") ///
    imargin(small) xsize(8) ysize(12) iscale(1) ///
    graphregion(color(white)) name(fig_placebo, replace)

graph export "$figures/figure_5_2_placebo.png", width(3000) replace
graph export "$figures/figure_5_2_placebo.pdf", replace
graph save "$figures/figure_5_2_placebo.gph", replace

di as result "Saved figures to $figures"
