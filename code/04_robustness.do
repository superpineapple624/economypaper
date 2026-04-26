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
capture which winsor2
if _rc {
    ssc install winsor2, replace
}

capture program drop placebo_once
program define placebo_once, rclass
    syntax , depvar(name) controls(string) ntreated(integer) monthpool(string)

    tempvar u rank placebo_treated placebo_month placebo_post placebo_did
    preserve
        bysort stk_id: gen double `u' = runiform() if _n == 1
        bysort stk_id: replace `u' = `u'[1]
        egen long `rank' = rank(`u'), unique
        gen byte `placebo_treated' = (`rank' <= `ntreated')

        capture drop placebo_draw_id
        gen int placebo_draw_id = ceil(runiform() * `ntreated') if `placebo_treated'
        merge m:1 placebo_draw_id using "`monthpool'", keep(master match) nogen

        gen int `placebo_month' = first_maker_month_pool if `placebo_treated'
        format `placebo_month' %tm
        gen byte `placebo_post' = (month >= `placebo_month') if `placebo_treated'
        replace `placebo_post' = 0 if missing(`placebo_post')
        gen byte `placebo_did' = `placebo_treated' * `placebo_post'

        quietly reghdfe `depvar' `placebo_did' `controls', absorb(stk_id month) vce(cluster stk_id)
        return scalar beta = _b[`placebo_did']
        return scalar se = _se[`placebo_did']
        return scalar p = 2 * ttail(e(df_r), abs(_b[`placebo_did'] / _se[`placebo_did']))
    restore
end

use "$final/monthly_panel.dta", clear

keep if inrange(month, tm(2020m1), tm(2025m12))

capture confirm variable stk_id
if _rc {
    egen long stk_id = group(stkcd)
}

xtset stk_id month

gen byte did = treated * post
label variable did "DID"
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

local controls ln_cir_mktcap pb turnover leverage roa rd_intensity ///
    inst_hold
tempfile base_panel
save `base_panel', replace

* ----------------------------------------------------------------------
* 1. Alternative dependent variables
* ----------------------------------------------------------------------
eststo clear
foreach y in synch resid_vol {
    quietly reghdfe `y' did `controls', absorb(stk_id month) vce(cluster stk_id)
    eststo alt_`y'
}

esttab alt_synch alt_resid_vol using "$tables/robust_alt_depvars.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("替换被解释变量的稳健性检验结果") ///
    mtitles("股价同步性" "残差波动率") ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

esttab alt_synch alt_resid_vol using "$tables/robust_alt_depvars.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方"))

* ----------------------------------------------------------------------
* 2. Winsorize at the 1st/99th percentiles and rerun
* ----------------------------------------------------------------------
preserve
foreach v in price_delay synch resid_vol `controls' {
    capture drop `v'_w
    winsor2 `v', cuts(1 99) suffix(_w)
}

eststo clear
local controls_w ln_cir_mktcap_w pb_w turnover_w leverage_w roa_w ///
    rd_intensity_w inst_hold_w

foreach y in price_delay synch resid_vol {
    quietly reghdfe `y'_w did `controls_w', absorb(stk_id month) vce(cluster stk_id)
    eststo winsor_`y'
}

esttab winsor_price_delay winsor_synch winsor_resid_vol using "$tables/robust_winsor_results.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("缩尾处理后的稳健性检验结果") ///
    mtitles("价格延迟" "股价同步性" "残差波动率") ///
    keep(did `controls_w') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

esttab winsor_price_delay winsor_synch winsor_resid_vol using "$tables/robust_winsor_results.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did `controls_w') ///
    stats(N r2_a, labels("观测值" "调整后R方"))
restore

* ----------------------------------------------------------------------
* 3. Randomization placebo test
* ----------------------------------------------------------------------
local placebo_reps = 300
tempfile month_pool placebo_pd placebo_syn placebo_rv placebo_summary

preserve
    keep stk_id treated first_maker_month
    bysort stk_id: keep if _n == 1
    keep if treated
    keep first_maker_month
    gen long placebo_draw_id = _n
    rename first_maker_month first_maker_month_pool
    count
    local n_treated = r(N)
    save `month_pool', replace
restore

eststo clear
postfile placebo_handle str20 depvar double actual_beta actual_se actual_p ///
    placebo_mean placebo_sd placebo_abs_p using `placebo_summary', replace

foreach y in price_delay synch resid_vol {
    use `base_panel', clear
    xtset stk_id month
    quietly reghdfe `y' did `controls', absorb(stk_id month) vce(cluster stk_id)
    eststo actual_`y'
    local actual_beta = _b[did]
    local actual_se = _se[did]
    local actual_p = 2 * ttail(e(df_r), abs(_b[did] / _se[did]))

    simulate beta = r(beta) se = r(se) p = r(p), reps(`placebo_reps') seed(20260415) nodots: ///
        placebo_once, depvar(`y') controls("`controls'") ntreated(`n_treated') monthpool("`month_pool'")

    gen str20 depvar = "`y'"
    gen double actual_beta = `actual_beta'
    gen double actual_se = `actual_se'
    gen double actual_p = `actual_p'
    gen double abs_placebo_beta = abs(beta)
    gen double abs_actual_beta = abs(actual_beta)
    quietly summarize beta
    local placebo_mean = r(mean)
    local placebo_sd = r(sd)
    quietly count if abs_placebo_beta >= abs_actual_beta
    local placebo_abs_p = r(N) / _N

    post placebo_handle ("`y'") (`actual_beta') (`actual_se') (`actual_p') ///
        (`placebo_mean') (`placebo_sd') (`placebo_abs_p')

    keep depvar beta se p actual_beta actual_se actual_p
    order depvar beta se p actual_beta actual_se actual_p
    if "`y'" == "price_delay" {
        save `placebo_pd', replace
    }
    else if "`y'" == "synch" {
        save `placebo_syn', replace
    }
    else if "`y'" == "resid_vol" {
        save `placebo_rv', replace
    }
}
postclose placebo_handle

use `placebo_summary', clear
replace depvar = "价格延迟" if depvar == "price_delay"
replace depvar = "股价同步性" if depvar == "synch"
replace depvar = "残差波动率" if depvar == "resid_vol"
label variable depvar "被解释变量"
label variable actual_beta "真实DID系数"
label variable actual_se "真实DID标准误"
label variable actual_p "真实DID p值"
label variable placebo_mean "安慰剂均值"
label variable placebo_sd "安慰剂标准差"
label variable placebo_abs_p "随机化p值"
rename depvar 被解释变量
rename actual_beta 真实DID系数
rename actual_se 真实DID标准误
rename actual_p 真实DIDp值
rename placebo_mean 安慰剂均值
rename placebo_sd 安慰剂标准差
rename placebo_abs_p 随机化p值
export delimited using "$tables/placebo_results.csv", replace
save "$tables/placebo_results.dta", replace

esttab actual_price_delay actual_synch actual_resid_vol using "$tables/placebo_results.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("安慰剂检验中的真实DID估计结果") ///
    mtitles("价格延迟" "股价同步性" "残差波动率") ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

use `placebo_pd', clear
append using `placebo_syn'
append using `placebo_rv'
save "$tables/placebo_draws.dta", replace

di as result "Saved robustness tables to $tables"
