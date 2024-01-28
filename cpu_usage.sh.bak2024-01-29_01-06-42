#!/bin/bash
top -bn1 | grep "Cpu(s)" | awk '{usage=$2+$4; printf "%.0f%%\n", usage}'
