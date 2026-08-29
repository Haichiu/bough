#!/usr/bin/env bash
# U5: large-map UI latency is intentionally not measured by this AX harness.
# Synthetic Return/focus delivery is unreliable, and AX polling noise exceeds
# the signal. Performance coverage belongs in the headless Checks benchmark.
echo "SKIP U5: UI latency not measured — synthetic keyboard/focus lane is unreliable; headless benchmark required"
exit 77
