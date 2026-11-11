# Prefetch system: ASAP7 synthesis + place and route

Placement, clock tree and routing are done. Harness flops on every pin, pin paths are false paths:
only flop-to-flop paths are timed. Clock uncertainty 5 %. Synthesis (ABC) at 200 ps.
Fmax = 1000 / (period - worst setup slack). GR-1: every stage under 240 ps after place and route.

| top | vt | corner | period ps | synth | pnr | last stage | setup WS ps | TNS ps | hold WS ps | area um2 | Fmax GHz |
|---|---|---|---|---|---|---|---|---|---|---|---|
| pf3_timing_top | RVT | BC | 240 | 0 | 2 | 5_1_grt.json | -367.536 | -3020330.0 | 10.7969 | 21336.7 | 1.646 |
| pf3_timing_top | RVT | TC | 240 | 0 | 2 | 5_1_grt.json | -624.538 | -6170030.0 | 25.8367 | 21523.3 | 1.157 |
| pf3_timing_top | RVT LVT SLVT | BC | 240 | 0 | 2 | 5_1_grt.json | -240.184 | -1937360.0 | 2.05502 | 21185.6 | 2.083 |
| pf3_timing_top | RVT LVT SLVT | TC | 240 | 0 | 2 | 5_1_grt.json | -369.997 | -3916880.0 | 3.01859 | 21307.4 | 1.639 |

Exit code 0 = stage finished; na = not started. Per-stage slacks:

- pf3_timing_top BC 240 ps: 2_1_floorplan [-524.9], 3_3_place_gp [-402.0], 3_4_place_resized [-402.0], 3_5_place_dp [-400.7], 4_1_cts [-372.6], 5_1_grt [-367.5]
- pf3_timing_top TC 240 ps: 2_1_floorplan [-791.0], 3_3_place_gp [-668.7], 3_4_place_resized [-668.7], 3_5_place_dp [-668.0], 4_1_cts [-641.4], 5_1_grt [-624.5]
- pf3_timing_top BC 240 ps: 2_1_floorplan [-337.3], 3_3_place_gp [-286.1], 3_4_place_resized [-286.1], 3_5_place_dp [-286.4], 4_1_cts [-261.7], 5_1_grt [-240.2]
- pf3_timing_top TC 240 ps: 2_1_floorplan [-498.4], 3_3_place_gp [-452.9], 3_4_place_resized [-452.9], 3_5_place_dp [-453.0], 4_1_cts [-401.2], 5_1_grt [-370.0]
