from pathlib import Path
import re
p=Path('build/M3_06_3_5_2_20261022_143446_308/place_route/route_constraint_ite_1/fpga_gsv1_top.rtr');s=p.read_text()
print(s[s.index('Setup Summary'):s.index('Hold Summary')])
print(s[s.index('Startpoint'):s.index('Startpoint')+1400])
