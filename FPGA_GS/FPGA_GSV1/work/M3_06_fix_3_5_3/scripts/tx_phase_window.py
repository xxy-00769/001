"""Intersect TXC phase bounds from every production post-route TX timing path.

delta is an additional TXC phase shift, positive = later clock at PHY.
setup: delta >= -slack. hold: delta <= slack. No paths are discarded.
Removing uncertainty is a labelled sensitivity calculation, not signoff.
"""
import argparse
import json
from pathlib import Path
from tx_path_table import paths


def calculate(records, credit=0):
    setup = [r for r in records if r['type'].startswith('max')]
    hold = [r for r in records if r['type'].startswith('min')]
    lo = max(setup, key=lambda r: -r['slack_ns'])
    hi = min(hold, key=lambda r: r['slack_ns'])
    lower = round(-lo['slack_ns']-credit, 3)
    upper = round(hi['slack_ns']+credit, 3)
    return dict(lower_ns=lower, upper_ns=upper,
                width_ns=round(upper-lower, 3), feasible=lower <= upper,
                lower_path=lo, upper_path=hi)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('input'); p.add_argument('prefix')
    p.add_argument('--sensitivity-credit', type=float, default=0.3)
    p.add_argument('--duty-already-covered', action='store_true')
    a = p.parse_args()
    records = [r for r in paths(a.input) if r['endpoint'] != 'rgmii2_txc'
               and r['capture_edge'] in ('rising edge', 'falling edge')
               and r['type'].startswith(('max', 'min'))]
    pins = sorted({r['endpoint'] for r in records})
    assert len(pins) == 5, pins
    result = dict(source=str(Path(a.input).resolve()), path_count=len(records),
                  formula='setup delta >= -slack; hold delta <= slack',
                  common=calculate(records), windows=[])
    lines = ['|Pin|Corner|Capture edge|Lower delta ns|Upper delta ns|Width ns|Setup line|Hold line|',
             '|---|---|---|---:|---:|---:|---:|---:|']
    for pin in pins:
        for corner in ('slow', 'fast'):
            for edge in ('rising edge', 'falling edge'):
                selected = [r for r in records if r['endpoint'] == pin and
                            corner in r['type'] and r['capture_edge'] == edge]
                w = dict(pin=pin, corner=corner, edge=edge, **calculate(selected))
                result['windows'].append(w)
                lines.append(f"|{pin}|{corner}|{edge}|{w['lower_ns']}|{w['upper_ns']}|"
                             f"{w['width_ns']}|{w['lower_path']['line']}|{w['upper_path']['line']}|")
    result['sensitivity_only'] = dict(removed_uncertainty_ns=a.sensitivity_credit,
                                    signoff=False, **calculate(records, a.sensitivity_credit))
    # PHY table65 Duty_G=45..55%. For an 8ns DDR root clock, either next
    # data edge can occur 0.4ns sooner. Same-edge setup is unchanged.
    # This is a sensitivity calculation on existing routed path delays,
    # not a newly executed STA or a measurement of this board's duty.
    duty_extra = 0 if a.duty_already_covered else 0.4
    duty_records = [dict(r, slack_ns=round(r['slack_ns']-(duty_extra if
                    r['type'].startswith('min') else 0), 3)) for r in records]
    result['datasheet_duty_sensitivity'] = dict(
        duty_percent=[45, 55], already_covered_in_input=a.duty_already_covered,
        additional_half_cycle_shortening_ns=duty_extra,
        new_sta_run=False, signoff=False,
        original_budget=calculate(duty_records),
        arbitrary_budget_removed=calculate(duty_records,a.sensitivity_credit))
    Path(a.prefix+'.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    Path(a.prefix+'.md').write_text('\n'.join(lines)+'\n\n'+
        'Common: '+json.dumps(result['common'])+'\n\nSensitivity only: '+
        json.dumps(result['sensitivity_only'])+'\n\nDatasheet duty sensitivity: '+
        json.dumps(result['datasheet_duty_sensitivity'])+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('path_count', 'common', 'sensitivity_only')}, indent=2))
