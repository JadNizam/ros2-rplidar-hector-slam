#!/bin/bash
# Hard-reset RPLIDAR C1 serial state (fixes error 80008002).
# Always sends STOP + RESET — do not skip RESET when STOP responds.
PORT="${1:-/dev/ttyUSB0}"
BAUD=460800

python3 - "$PORT" "$BAUD" <<'PYEOF'
import serial
import sys
import time

port, baud = sys.argv[1], int(sys.argv[2])


def get_info(s):
    s.reset_input_buffer()
    s.write(b'\xa5\x50')  # GET_INFO
    s.flush()
    resp = s.read(20)
    return len(resp) >= 7 and resp[0:2] == b'\xa5\x5a'


def stop_motor(s):
    s.reset_input_buffer()
    s.write(b'\xa5\x25')  # STOP
    s.flush()
    time.sleep(1.5)


def reset_device(s):
    s.reset_input_buffer()
    s.write(b'\xa5\x40')  # RESET
    s.flush()
    time.sleep(7.0)


s = serial.Serial(port, baud, timeout=2)

print('Stopping LiDAR motor...')
stop_motor(s)

print('Sending hardware RESET...')
reset_device(s)

print('Stopping LiDAR after reset...')
stop_motor(s)

if get_info(s):
    print('LiDAR ready.')
    s.reset_input_buffer()
    s.close()
    sys.exit(0)

print('Waiting extra 4s for LiDAR...')
time.sleep(4)
stop_motor(s)
ok = get_info(s)
s.reset_input_buffer()
s.close()
if ok:
    print('LiDAR ready.')
    sys.exit(0)

print('WARNING: LiDAR did not respond after reset — launch may retry.')
sys.exit(0)
PYEOF
