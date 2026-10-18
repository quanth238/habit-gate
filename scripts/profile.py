#!/usr/bin/env python3
"""Sample the installed native processes; no credentials or habit data are read."""
import argparse, json, statistics, subprocess, time

def seconds(text):
    day, _, rest = text.rpartition('-')
    total = 0
    for part in (rest if day else text).split(':'):
        total = total * 60 + float(part)
    # ps normally emits minutes:seconds on macOS, without a day component.
    return total + (float(day) * 86400 if day else 0)

def sample():
    found = subprocess.run(['pgrep', '-x', 'HabitGate|HabitGateBridge'], capture_output=True, text=True)
    ids = found.stdout.split()
    if not ids:
        return {}
    lines = subprocess.check_output(['ps', '-p', ','.join(ids), '-o', 'pid=,rss=,time='], text=True).splitlines()
    return {p: {'rss': int(rss) * 1024, 'cpu': seconds(cpu)} for p, rss, cpu in (line.split() for line in lines)}

parser = argparse.ArgumentParser(); parser.add_argument('--seconds', type=int, default=60)
args = parser.parse_args()
started = time.monotonic(); previous = sample(); samples = []; cpu = 0
if not previous:
    raise SystemExit('Habit Gate is not running; no idle measurement was taken.')
while time.monotonic() - started < args.seconds:
    time.sleep(1)
    current = sample()
    if not current:
        raise SystemExit('Habit Gate stopped during sampling; measurement is incomplete.')
    for pid, value in current.items():
        cpu += max(0, value['cpu'] - previous.get(pid, {'cpu': 0})['cpu'])
    samples.append(sum(v['rss'] for v in current.values()))
    previous = current
elapsed = time.monotonic() - started
print(json.dumps({'seconds': round(elapsed, 2), 'nativeAverageCPUPercentOfOneCore': round(cpu / elapsed * 100, 3),
                  'meanRSS_MB': round(statistics.mean(samples) / 1_000_000, 2),
                  'maxRSS_MB': round(max(samples) / 1_000_000, 2), 'sampleCount': len(samples)}, indent=2))
