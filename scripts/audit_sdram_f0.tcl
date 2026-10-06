# Production audit adapted from the Gundam/Guardians paired-edge experiment.
# OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
package require ::quartus::project
package require ::quartus::sta
project_open GundamEX
create_timing_netlist
read_sdc
update_timing_netlist
foreach pattern {
    *graphics_sdram*sdram_input_samples*|ddio_ina*
    *graphics_sdram*sdram_input_samples*|dataout_l*
} {
    set count [get_collection_size [get_registers -nowarn $pattern]]
    puts "F0 AUDIT: $pattern = $count fitted registers"
    if {$count != 16} { error "Expected sixteen falling-edge captures and low-data retimers" }
}
# Quartus can retain the unused high register inside the paired I/O primitive.
# The RTL leaves dataout_h open; verify its lack of timed fanout, not pruning.
set rising [get_registers -nowarn {*graphics_sdram*sdram_input_samples*|dataout_h*}]
puts "F0 AUDIT: retained high-half registers = [get_collection_size $rising]"
set rising_file output_files/sdram-f0-unused-high-paths.rpt
report_timing -setup -from $rising -npaths 3 -detail full_path -file $rising_file
set handle [open $rising_file r]
set rising_report [read $handle]
close $handle
if {![regexp {Nothing to report\.|Found 0 setup paths} $rising_report]} {
    error "Unused rising output still has timed register fanout"
}
set clocks [get_clocks -nowarn {*emu|pll*PLL_OUTPUT_COUNTER*|divclk}]
if {[get_collection_size $clocks] != 1} { error "Expected unchanged core PLL counter" }
foreach_in_collection clock $clocks {
    set period [get_clock_info -period $clock]
    puts "F0 AUDIT: core clock period $period ns"
    if {abs($period - 16.0) > 0.002} { error "Memory frequency differs from 62.5 MHz" }
}
report_clocks -file output_files/sdram-f0-clocks.rpt
set path_file output_files/sdram-f0-client-paths.rpt
report_timing -setup -from [get_registers {*graphics_sdram*sdram_input_samples*|dataout_l*}] -npaths 3 -detail full_path -file $path_file
set handle [open $path_file r]
set report [read $handle]
close $handle
if {![regexp {Found 3 setup paths \(0 violated\)} $report]} {
    error "Fitted F0 capture-to-client paths absent or violating"
}
puts "PASS: sixteen fixed F0 input captures, unchanged 62.5 MHz clock, timed client paths"
puts "NOTE: external SDRAM I/O remains unconstrained; internal audit only"
delete_timing_netlist
project_close
