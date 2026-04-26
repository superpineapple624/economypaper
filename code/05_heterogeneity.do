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

* Use the sample median to keep the original split-sample tables as supplements.
quietly summarize ln_cir_mktcap if !missing(ln_cir_mktcap), detail
local size_median = r(p50)
gen byte large_size = (ln_cir_mktcap >= `size_median') if !missing(ln_cir_mktcap)
label variable large_size "大市值组"

quietly summarize inst_hold if !missing(inst_hold), detail
local info_median = r(p50)
gen byte high_info = (inst_hold >= `info_median') if !missing(inst_hold)
label variable high_info "高信息透明度组"

eststo clear
foreach g in 0 1 {
    quietly reghdfe price_delay did `controls' if large_size == `g', ///
        absorb(stk_id month) vce(cluster stk_id)
    eststo size_pd_`g'
}

esttab size_pd_0 size_pd_1 using "$tables/heterogeneity_size.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("按企业规模分组的异质性分析结果") ///
    mtitles("小市值组" "大市值组") ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

esttab size_pd_0 size_pd_1 using "$tables/heterogeneity_size.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方"))

eststo clear
foreach g in 0 1 {
    quietly reghdfe price_delay did `controls' if high_info == `g', ///
        absorb(stk_id month) vce(cluster stk_id)
    eststo info_pd_`g'
}

esttab info_pd_0 info_pd_1 using "$tables/heterogeneity_info.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("按信息透明度分组的异质性分析结果") ///
    mtitles("低信息透明度组" "高信息透明度组") ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方")) ///
    nonotes addnotes("括号内为标准误" "*、**、***分别表示在10%、5%和1%显著性水平上显著") ///
    compress

esttab info_pd_0 info_pd_1 using "$tables/heterogeneity_info.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did `controls') ///
    stats(N r2_a, labels("观测值" "调整后R方"))

* Main heterogeneity tests: pre-treatment firm characteristics and full-sample
* interactions. This avoids defining groups with post-treatment information.
egen first_treat_month = min(cond(did == 1, month, .)), by(stk_id)
gen byte pre_period = (month < first_treat_month) if !missing(first_treat_month)
replace pre_period = 1 if missing(first_treat_month)

egen pre_size_tmp = mean(ln_cir_mktcap) if pre_period == 1, by(stk_id)
egen firm_pre_size = max(pre_size_tmp), by(stk_id)
drop pre_size_tmp

egen pre_info_tmp = mean(inst_hold) if pre_period == 1, by(stk_id)
egen firm_pre_info = max(pre_info_tmp), by(stk_id)
drop pre_info_tmp

quietly summarize firm_pre_size if !missing(firm_pre_size), detail
local pre_size_median = r(p50)
gen byte large_size_pre = (firm_pre_size >= `pre_size_median') if !missing(firm_pre_size)
label variable large_size_pre "Pre-treatment large size group"

quietly summarize firm_pre_info if !missing(firm_pre_info), detail
local pre_info_median = r(p50)
gen byte high_info_pre = (firm_pre_info >= `pre_info_median') if !missing(firm_pre_info)
label variable high_info_pre "Pre-treatment high transparency group"

preserve
    keep stk_id large_size_pre high_info_pre
    duplicates drop
    di as text "Firm counts by pre-treatment size group:"
    tab large_size_pre, missing
    di as text "Firm counts by pre-treatment transparency group:"
    tab high_info_pre, missing
restore

eststo clear
quietly reghdfe price_delay c.did##ib0.large_size_pre `controls' ///
    if !missing(large_size_pre), absorb(stk_id month) vce(cluster stk_id)
eststo size_interaction

esttab size_interaction using "$tables/heterogeneity_interaction_size.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("Interaction test by pre-treatment firm size") ///
    keep(did 1.large_size_pre#c.did `controls') ///
    order(did 1.large_size_pre#c.did) ///
    coeflabels(did "DID (small size group)" ///
        1.large_size_pre#c.did "DID x pre-treatment large size group") ///
    stats(N r2_a, labels("Observations" "Adjusted R-squared")) ///
    nonotes addnotes("Clustered standard errors at the firm level in parentheses" ///
        "*, **, and *** denote significance at the 10%, 5%, and 1% levels") ///
    compress

esttab size_interaction using "$tables/heterogeneity_interaction_size.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did 1.large_size_pre#c.did `controls') ///
    order(did 1.large_size_pre#c.did) ///
    coeflabels(did "DID (small size group)" ///
        1.large_size_pre#c.did "DID x pre-treatment large size group") ///
    stats(N r2_a, labels("Observations" "Adjusted R-squared"))

eststo clear
quietly reghdfe price_delay c.did##ib0.high_info_pre `controls' ///
    if !missing(high_info_pre), absorb(stk_id month) vce(cluster stk_id)
eststo info_interaction

esttab info_interaction using "$tables/heterogeneity_interaction_info.rtf", ///
    replace label se star(* 0.10 ** 0.05 *** 0.01) ///
    title("Interaction test by pre-treatment information transparency") ///
    keep(did 1.high_info_pre#c.did `controls') ///
    order(did 1.high_info_pre#c.did) ///
    coeflabels(did "DID (low transparency group)" ///
        1.high_info_pre#c.did "DID x pre-treatment high transparency group") ///
    stats(N r2_a, labels("Observations" "Adjusted R-squared")) ///
    nonotes addnotes("Clustered standard errors at the firm level in parentheses" ///
        "*, **, and *** denote significance at the 10%, 5%, and 1% levels") ///
    compress

esttab info_interaction using "$tables/heterogeneity_interaction_info.csv", ///
    replace csv label se nogaps nonumber noobs ///
    keep(did 1.high_info_pre#c.did `controls') ///
    order(did 1.high_info_pre#c.did) ///
    coeflabels(did "DID (low transparency group)" ///
        1.high_info_pre#c.did "DID x pre-treatment high transparency group") ///
    stats(N r2_a, labels("Observations" "Adjusted R-squared"))

di as result "Saved heterogeneity tables to $tables"
