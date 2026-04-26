version 17
clear all
macro drop _all
set more off
set varabbrev off
capture log close _all

* Project root defaults to the current working directory.
global project "`c(pwd)'"
global data "$project/data"
global raw "$data/raw"
global intermediate "$data/intermediate"
global final "$data/final"
global code "$project/code"
global output "$project/output"
global tables "$output/tables"
global figures "$output/figures"
global logs "$output/logs"
global ado "$project/ado"
global ado_plus "$ado/plus"
global ado_personal "$ado/personal"

foreach dir in "$intermediate" "$final" "$output" "$tables" "$figures" "$logs" ///
    "$ado" "$ado_plus" "$ado_personal" {
    capture mkdir "`dir'"
}

sysdir set PLUS "$ado_plus"
sysdir set PERSONAL "$ado_personal"

* Required packages for the regression stage.
local packages require ftools reghdfe estout winsor2
foreach pkg of local packages {
    capture which `pkg'
    if _rc {
        di as txt "Installing `pkg'..."
        ssc install `pkg', replace
    }
}

local today : display %tdCCYY-NN-DD date("`c(current_date)'", "DMY")
local now = subinstr("`c(current_time)'", ":", "-", .)
log using "$logs/master_`today'_`now'.log", replace text name(master)

do "$code/01_clean_construct.do"
do "$code/02_regressions.do"
do "$code/03_event_study.do"
do "$code/04_robustness.do"
do "$code/05_heterogeneity.do"
do "$code/06_figures.do"

log close master
