version 17
set more off
set varabbrev off

if "$project" == "" {
    global project "`c(pwd)'"
    global data "$project/data"
    global raw "$data/raw"
    global intermediate "$data/intermediate"
    global final "$data/final"
}

capture program drop rename_if_exists
program define rename_if_exists
    args old new
    capture confirm variable `old'
    if !_rc rename `old' `new'
end

capture mkdir "$intermediate"
capture mkdir "$final"

local raw_maker "$raw/做市股票列表.xls"
local raw_company "$raw/公司文件215054172(仅供华中师范大学使用)/TRD_Co.xlsx"
local raw_stock "$raw/日个股回报率文件222242170(仅供华中师范大学使用)/TRDNEW_Dalyr.xlsx"
local raw_value "$raw/个股日交易衍生指标223325927(仅供华中师范大学使用)/STK_MKT_DALYR.xlsx"
local raw_index "$raw/国内指数日行情文件112146454(仅供华中师范大学使用)/IDX_Idxtrd.xlsx"
local raw_suspend "$raw/个股停牌标识表(日)113537899(仅供华中师范大学使用)/LIQ_SUSPENSION.xlsx"
local raw_bs "$raw/资产负债表222702584(仅供华中师范大学使用) (1)/FS_Combas.xlsx"
local raw_is "$raw/利润表222930855(仅供华中师范大学使用)/FS_Comins.xlsx"
local raw_roa "$raw/盈利能力223923490(仅供华中师范大学使用)/FI_T5.xlsx"
local raw_solv "$raw/偿债能力223959803(仅供华中师范大学使用)/FI_T1.xlsx"
local raw_holder "$raw/机构持股分类统计表223634372(仅供华中师范大学使用)/INI_HolderSystematics.xlsx"

foreach f in "`raw_maker'" "`raw_company'" "`raw_stock'" "`raw_value'" ///
    "`raw_index'" "`raw_suspend'" "`raw_bs'" "`raw_is'" "`raw_roa'" ///
    "`raw_solv'" "`raw_holder'" {
    capture confirm file `"`f'"'
    if _rc {
        di as error "Missing raw file: `f'"
        exit 601
    }
}

tempfile maker company stock value index suspend bs is roa solv holder dailybase fullr2 contopr2 monthly_ctrl annual_ctrl panel

* ----------------------------------------------------------------------
* 1. Treatment list: first market-making date by firm
* ----------------------------------------------------------------------
import excel using "`raw_maker'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' stknme
rename `v3' maker_name
rename `v4' maker_date
gen double maker_dt = daily(maker_date, "YMD")
format maker_dt %td
gen int first_maker_month = mofd(maker_dt)
format first_maker_month %tm
collapse (min) maker_dt first_maker_month, by(stkcd)
save `maker', replace

* ----------------------------------------------------------------------
* 2. Firm master: keep 科创板 only
* ----------------------------------------------------------------------
import excel using "`raw_company'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
local v5 : word 5 of `vlist'
local v6 : word 6 of `vlist'
rename `v1' stkcd
rename `v2' stknme
rename `v3' listdt
rename `v4' nnindcd
rename `v5' nnindnme
rename `v6' markettype
destring markettype, replace force
gen double list_dt = daily(listdt, "YMD")
format list_dt %td
gen int list_month = mofd(list_dt)
format list_month %tm
keep if markettype == 32
keep stkcd stknme listdt list_dt list_month nnindcd nnindnme markettype
duplicates drop stkcd, force
save `company', replace

* ----------------------------------------------------------------------
* 3. Daily stock return file
* ----------------------------------------------------------------------
import excel using "`raw_stock'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
local v5 : word 5 of `vlist'
local v6 : word 6 of `vlist'
local v7 : word 7 of `vlist'
local v8 : word 8 of `vlist'
local v9 : word 9 of `vlist'
local v10 : word 10 of `vlist'
local v11 : word 11 of `vlist'
rename `v1' stkcd
rename `v2' trddt
rename `v3' opnprc
rename `v4' clsprc
rename `v5' dsmvosd
rename `v6' dsmvtll
rename `v7' dretwd
rename `v8' dretnd
rename `v9' ahshrtrd_d
rename `v10' ahvaltrd_d
rename `v11' precloseprice
destring opnprc clsprc dsmvosd dsmvtll dretwd dretnd ahshrtrd_d ///
    ahvaltrd_d precloseprice, replace force ignore(",%")
gen double trade_dt = daily(trddt, "YMD")
format trade_dt %td
gen int month = mofd(trade_dt)
format month %tm
gen double stock_ret = dretwd / 100
duplicates drop stkcd trade_dt, force
keep stkcd trade_dt month opnprc clsprc dsmvosd dsmvtll stock_ret ///
    dretwd dretnd ahshrtrd_d ahvaltrd_d precloseprice
save `stock', replace

* ----------------------------------------------------------------------
* 4. Daily valuation controls: PB and turnover
* ----------------------------------------------------------------------
import excel using "`raw_value'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
local v5 : word 5 of `vlist'
rename `v1' tradingdate
rename `v2' stkcd
rename `v3' shortname
rename `v4' pb
rename `v5' turnover
destring pb turnover, replace force ignore(",%")
gen double trade_dt = daily(tradingdate, "YMD")
format trade_dt %td
duplicates drop stkcd trade_dt, force
keep stkcd trade_dt pb turnover
save `value', replace

* ----------------------------------------------------------------------
* 5. Index returns: 科创板综指 preferred
* ----------------------------------------------------------------------
import excel using "`raw_index'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
local v5 : word 5 of `vlist'
local v6 : word 6 of `vlist'
rename `v1' indexcd
rename `v2' idxtrd01
rename `v3' idxtrd05
rename `v4' idxtrd06
rename `v5' idxtrd08
rename `v6' idxtrd09
destring idxtrd05 idxtrd06 idxtrd08, replace force ignore(",%")
gen double trade_dt = daily(idxtrd01, "YMD")
format trade_dt %td
keep if strpos(idxtrd09, "科创板综指") | indexcd == "000680"
sort trade_dt
gen double mkt_ret = idxtrd08 / 100
forvalues l = 1/4 {
    gen double mkt_ret_l`l' = mkt_ret[_n-`l']
}
duplicates drop trade_dt, force
keep trade_dt mkt_ret mkt_ret_l1 mkt_ret_l2 mkt_ret_l3 mkt_ret_l4
save `index', replace

* ----------------------------------------------------------------------
* 6. Suspension / ST daily flag
* ----------------------------------------------------------------------
import excel using "`raw_suspend'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' suspdate
rename `v3' markettype
rename `v4' st
destring markettype, replace force
gen double susp_dt = daily(suspdate, "YMD")
format susp_dt %td
gen byte st_day = (upper(st) == "Y")
keep if markettype == 32
rename susp_dt trade_dt
duplicates drop stkcd trade_dt, force
keep stkcd trade_dt st_day
save `suspend', replace

* ----------------------------------------------------------------------
* 7. Annual accounting controls
* ----------------------------------------------------------------------
* Balance sheet
import excel using "`raw_bs'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' shortname
rename `v3' accper
rename `v4' typrep
rename_if_exists A001000000 total_assets
rename_if_exists a001000000 total_assets
rename_if_exists A002000000 total_liab
rename_if_exists a002000000 total_liab
destring total_assets total_liab, replace force ignore(",%")
gen double acc_dt = daily(accper, "YMD")
format acc_dt %td
gen int year = year(acc_dt)
keep if substr(accper, 6, 5) == "12-31"
keep stkcd year total_assets total_liab
duplicates drop stkcd year, force
save `bs', replace

* Income statement
import excel using "`raw_is'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' shortname
rename `v3' accper
rename `v4' typrep
rename_if_exists B001101000 revenue
rename_if_exists b001101000 revenue
rename_if_exists B001216000 rd_expense
rename_if_exists b001216000 rd_expense
rename_if_exists B002000000 net_profit
rename_if_exists b002000000 net_profit
destring revenue rd_expense net_profit, replace force ignore(",%")
gen double acc_dt = daily(accper, "YMD")
format acc_dt %td
gen int year = year(acc_dt)
keep if substr(accper, 6, 5) == "12-31"
keep stkcd year revenue rd_expense net_profit
duplicates drop stkcd year, force
save `is', replace

* Profitability / ROA
import excel using "`raw_roa'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' shortname
rename `v3' accper
rename `v4' typrep
rename_if_exists F050203B roa_raw
rename_if_exists f050203b roa_raw
destring roa_raw, replace force ignore(",%")
gen double acc_dt = daily(accper, "YMD")
format acc_dt %td
gen int year = year(acc_dt)
keep if substr(accper, 6, 5) == "12-31"
keep stkcd year roa_raw
duplicates drop stkcd year, force
save `roa', replace

* Solvency
import excel using "`raw_solv'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' shortname
rename `v3' accper
rename `v4' typrep
rename_if_exists F011201A debt_ratio_raw
rename_if_exists f011201a debt_ratio_raw
rename_if_exists F011401A tang_debt_ratio_raw
rename_if_exists f011401a tang_debt_ratio_raw
destring debt_ratio_raw tang_debt_ratio_raw, replace force ignore(",%")
gen double acc_dt = daily(accper, "YMD")
format acc_dt %td
gen int year = year(acc_dt)
keep if substr(accper, 6, 5) == "12-31"
keep stkcd year debt_ratio_raw tang_debt_ratio_raw
duplicates drop stkcd year, force
save `solv', replace

* Institutional holdings
import excel using "`raw_holder'", firstrow allstring clear
ds
local vlist `r(varlist)'
local v1 : word 1 of `vlist'
local v2 : word 2 of `vlist'
local v3 : word 3 of `vlist'
local v4 : word 4 of `vlist'
rename `v1' stkcd
rename `v2' enddate
rename `v3' inst_prop_raw
rename `v4' inst_prop_float_raw
destring inst_prop_raw inst_prop_float_raw, replace force ignore(",%")
gen double end_dt = daily(enddate, "YMD")
format end_dt %td
gen int year = year(end_dt)
keep if substr(enddate, 6, 5) == "12-31"
keep stkcd year inst_prop_raw inst_prop_float_raw
duplicates drop stkcd year, force
save `holder', replace

* ----------------------------------------------------------------------
* 8. Daily merge and monthly collapse
* ----------------------------------------------------------------------
use `stock', clear
merge m:1 stkcd using `company', keep(master match) nogen
merge m:1 stkcd using `maker', keep(master match) nogen
merge m:1 stkcd trade_dt using `value', keep(master match) nogen
merge m:1 trade_dt using `index', keep(master match) nogen
merge m:1 stkcd trade_dt using `suspend', keep(master match) nogen

* Align suspension flag to the trading date and fill missing with zero.
gen byte st_flag = st_day
replace st_flag = 0 if missing(st_flag)
drop st_day

gen int year = year(dofm(month))

* Trading-month treatment timing.
replace first_maker_month = . if first_maker_month == .
gen byte treated = !missing(first_maker_month)
gen byte post = (month >= first_maker_month) if treated
replace post = 0 if missing(post)
gen int rel_month = month - first_maker_month if treated

* Drop months with any ST trading day.
bysort stkcd month: egen st_month = max(st_flag)
replace st_month = 0 if missing(st_month)
keep if st_month == 0

* Need enough trading days to estimate the delay measure.
bysort stkcd month: egen n_days = count(stock_ret)
keep if n_days >= 15

save `dailybase', replace

* Full market-lag regression.
preserve
keep stkcd month stock_ret mkt_ret mkt_ret_l1 mkt_ret_l2 mkt_ret_l3 mkt_ret_l4
drop if missing(stock_ret, mkt_ret, mkt_ret_l1, mkt_ret_l2, mkt_ret_l3, mkt_ret_l4)
statsby r2_full = e(r2) rmse_full = e(rmse) N_full = e(N), ///
    by(stkcd month) clear: ///
    regress stock_ret mkt_ret mkt_ret_l1 mkt_ret_l2 mkt_ret_l3 mkt_ret_l4
save `fullr2', replace
restore

* Contemporaneous-only regression.
preserve
keep stkcd month stock_ret mkt_ret
drop if missing(stock_ret, mkt_ret)
statsby r2_contemp = e(r2) N_contemp = e(N), ///
    by(stkcd month) clear: ///
    regress stock_ret mkt_ret
save `contopr2', replace
restore

use `fullr2', clear
merge 1:1 stkcd month using `contopr2', nogen
gen double price_delay = .
replace price_delay = 1 - (r2_contemp / r2_full) if r2_full > 0 & r2_contemp >= 0
gen double synch = log(r2_full / (1 - r2_full)) if r2_full > 0 & r2_full < 1
gen double resid_vol = rmse_full
keep stkcd month price_delay synch resid_vol r2_full r2_contemp rmse_full N_full N_contemp
save `panel', replace

* Monthly controls from the merged daily panel.
use `dailybase', clear
collapse (mean) pb turnover dsmvosd dsmvtll stock_ret mkt_ret ///
    (sd) month_vol = stock_ret ///
    (max) treated post first_maker_month rel_month markettype n_days ///
    list_dt, by(stkcd month year)

gen double ln_cir_mktcap = ln(dsmvosd) if dsmvosd > 0
gen double ln_tot_mktcap = ln(dsmvtll) if dsmvtll > 0
gen double firm_age = year - year(list_dt) + 1 if !missing(list_dt)

* Merge annual controls by fiscal year.
merge m:1 stkcd year using `bs', keep(master match) nogen
merge m:1 stkcd year using `is', keep(master match) nogen
merge m:1 stkcd year using `roa', keep(master match) nogen
merge m:1 stkcd year using `solv', keep(master match) nogen
merge m:1 stkcd year using `holder', keep(master match) nogen

gen double leverage = total_liab / total_assets if total_assets > 0
gen double rd_intensity = rd_expense / revenue if revenue > 0
gen double roa = roa_raw
gen double inst_hold = inst_prop_raw
gen double inst_hold_alt = inst_prop_float_raw
egen long stk_id = group(stkcd)

drop if missing(month)
merge 1:1 stkcd month using `panel', keep(master match) nogen

order stkcd stk_id month price_delay synch resid_vol treated post rel_month ///
    first_maker_month ln_cir_mktcap ln_tot_mktcap pb turnover ///
    leverage roa rd_intensity firm_age inst_hold inst_hold_alt ///
    month_vol n_days markettype

compress
save "$final/monthly_panel.dta", replace

di as result "Saved analysis-ready panel to $final/monthly_panel.dta"
