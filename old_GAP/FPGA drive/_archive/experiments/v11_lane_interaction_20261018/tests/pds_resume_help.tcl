# Read-only command discovery; no design flow or board operations.
foreach pattern {*project* *pnr* *adif* *load* *open* *read*} {
    puts "$pattern: [lsort [info commands $pattern]]"
}
pnr -help
report_timing -help
gen_bit_stream -help
