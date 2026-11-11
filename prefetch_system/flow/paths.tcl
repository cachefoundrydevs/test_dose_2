source $::env(SCRIPTS_DIR)/load.tcl
load_design 6_final.odb 6_final.sdc
set rpt $::env(REPORTS_DIR)
report_worst_slack -max > $rpt/paths_worst.rpt
report_checks -path_delay max -group_path_count 60 -endpoint_path_count 1 \
    -format end > $rpt/paths_endpoints.rpt
report_checks -path_delay max -group_path_count 12 -endpoint_path_count 1 \
    -fields {fanout cap slew input_pins} -digits 1 > $rpt/paths_full.rpt
report_checks -path_delay min -group_path_count 10 -endpoint_path_count 1 \
    -format end > $rpt/paths_hold.rpt
