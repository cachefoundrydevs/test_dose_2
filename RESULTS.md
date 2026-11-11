# ASAP7 synthesis + place and route

Ideal-wire assumptions removed: placement, clock tree and routing are done. SRAM macros are ESTIMATES
(no ASAP7 memory compiler). I/O delay 0, clock uncertainty 5 %. Fmax = 1000 / (period - worst setup slack).

| top | corner | period ps | synth | pnr | last stage | setup WS ps | TNS ps | hold WS ps | area um2 | Fmax GHz |
|---|---|---|---|---|---|---|---|---|---|---|
| l1d_bank | BC | 250 | 0 | 2 | 4_1_cts.json | -958.455 | -7595490.0 | -379.75 | 46268.7 | 0.828 |
| l1d_bank | BC | 350 | 0 | 2 | 4_1_cts.json | -854.113 | -5453100.0 | -386.925 | 45721.6 | 0.83 |
| l1d_bank | TC | 250 | 0 | 2 | 5_1_grt.json | -1199.6 | -10616500.0 | -466.669 | 48482.9 | 0.69 |
| l1d_bank | TC | 350 | 0 | 2 | 5_1_grt.json | -1107.68 | -8519460.0 | -460.32 | 47844.1 | 0.686 |

Exit code 0 = stage finished; na = not started. Per-stage slacks:

- l1d_bank BC 250 ps: 2_1_floorplan [-582.3], 3_3_place_gp [-601.1], 3_4_place_resized [-601.1], 3_5_place_dp [-596.9], 4_1_cts [-958.5]
- l1d_bank BC 350 ps: 2_1_floorplan [-487.3], 3_3_place_gp [-527.3], 3_4_place_resized [-527.3], 3_5_place_dp [-515.0], 4_1_cts [-854.1]
- l1d_bank TC 250 ps: 2_1_floorplan [-874.9], 3_3_place_gp [-866.4], 3_4_place_resized [-866.4], 3_5_place_dp [-858.2], 4_1_cts [-1282.3], 5_1_grt [-1199.6]
- l1d_bank TC 350 ps: 2_1_floorplan [-779.9], 3_3_place_gp [-767.8], 3_4_place_resized [-767.8], 3_5_place_dp [-768.5], 4_1_cts [-1190.8], 5_1_grt [-1107.7]
