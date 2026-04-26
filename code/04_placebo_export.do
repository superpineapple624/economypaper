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

* 1. Re-export the actual DID estimates in Chinese.
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

eststo clear
foreach y in price_delay synch resid_vol {
    quietly reghdfe `y' did `controls', absorb(stk_id month) vce(cluster stk_id)
    eststo actual_`y'
}

esttab actual_price_delay actual_synch actual_resid_vol using "$tables/placebo_results.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("安慰剂检验中的真实DID估计结果") ///
    mtitles("价格延迟" "股价同步性" "残差波动率") ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

* 2. Re-export the placebo summary table in Chinese.
use "$tables/placebo_results.dta", clear
replace depvar = "价格延迟" if depvar == "price_delay"
replace depvar = "股价同步性" if depvar == "synch"
replace depvar = "残差波动率" if depvar == "resid_vol"

rename depvar 被解释变量
rename actual_beta 真实DID系数
rename actual_se 真实DID标准误
rename actual_p 真实DIDp值
rename placebo_mean 安慰剂均值
rename placebo_sd 安慰剂标准差
rename placebo_abs_p 随机化p值

export delimited using "$tables/placebo_results.csv", replace
save "$tables/placebo_results.dta", replace

di as result "Saved placebo tables to $tables"
