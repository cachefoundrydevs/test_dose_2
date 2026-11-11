source $::env(SCRIPTS_DIR)/load.tcl
set res $::env(RESULTS_DIR)
set odb ""
foreach f {6_final.odb 5_3_fillcell.odb 5_2_route.odb 5_1_grt.odb 4_1_cts.odb 3_place.odb} {
    if {[file exists $res/$f]} { set odb $f; break }
}
set sdc ""
foreach f {6_final.sdc 5_route.sdc 4_cts.sdc 3_place.sdc 2_floorplan.sdc 1_synth.sdc} {
    if {[file exists $res/$f]} { set sdc $f; break }
}
puts "paths.tcl: database $odb, constraints $sdc"
if {[catch {load_design $odb $sdc}]} {
    load_design $odb
}
if {[catch {estimate_parasitics -global_routing}]} {
    catch {estimate_parasitics -placement}
}
set rpt $::env(REPORTS_DIR)
report_worst_slack -max > $rpt/paths_worst.rpt
report_checks -path_delay max -group_path_count 40 -endpoint_path_count 1 \
    -format end > $rpt/paths_endpoints.rpt
foreach blk {u_stride.g_entry u_stride u_stream.g_card u_stream u_sms_core u_sms_expand u_rank} {
    set cells [get_cells -quiet "u_prefetch.${blk}*"]
    if {[llength $cells] == 0} { continue }
    set tag [string map {. _} $blk]
    report_checks -path_delay max -to $cells -group_path_count 15 \
        -endpoint_path_count 1 -format end > $rpt/paths_end_$tag.rpt
    report_checks -path_delay max -to $cells -fields {fanout cap slew} \
        -digits 1 > $rpt/paths_full_$tag.rpt
}
report_checks -path_delay min -group_path_count 10 -endpoint_path_count 1 \
    -format end > $rpt/paths_hold.rpt
