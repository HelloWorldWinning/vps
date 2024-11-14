#!/bin/bash

# Step 1: Stop and kill processes
echo "Stopping all kdevtmpfsi processes..."
pkill -9 kdevtmpfsi
killall -9 kdevtmpfsi

# Double check and force kill
if [ -n "$(ps aux | grep kdevtmpfsi | grep -v grep)" ]; then
    ps aux | grep kdevtmpfsi | grep -v grep | awk '{print $2}' | xargs -r kill -9
fi

# Step 2: Remove existing file
echo "Removing malicious file..."
rm -f /tmp/kdevtmpfsi
rm -f /tmp/.kdevtmpfsi* 2>/dev/null

# Step 3: Create empty immutable file
echo "Creating immutable blocker file..."
# Create empty file
touch /tmp/kdevtmpfsi
# Remove all permissions (no read/write/execute for anyone)
chmod 000 /tmp/kdevtmpfsi
# Make it immutable - cannot be modified or deleted even by root
chattr +i /tmp/kdevtmpfsi

# Verify
echo "Verifying file attributes..."
ls -la /tmp/kdevtmpfsi
lsattr /tmp/kdevtmpfsi

echo "Setup complete. The file is now immutable."
echo "To verify, try to modify or delete it - it should be impossible."
echo "If you ever need to remove it, use: chattr -i /tmp/kdevtmpfsi"



 touch /tmp/kdevtmpfsi && touch /tmp/kinsing
 echo "kdevtmpfsi is fine now" > /tmp/kdevtmpfsi
 echo "kinsing is fine now" > /tmp/kinsing
 chmod 0444 /tmp/kdevtmpfsi
 chmod 0444 /tmp/kinsing



 touch /tmp/kdevtmpfsi && touch /var/tmp/kinsing

echo "everything is good here" > /tmp/kdevtmpfsi

echo "everything is good here" > /var/tmp/kinsing

touch /tmp/zzz

echo "everything is good here" > /tmp/zzz

chmod go-rwx /var/tmp

chmod 1777 /tmp





#!/bin/bash

# kinsing deleteing here
PID=$(pidof kinsing)
echo "$PID"
kill -9 $PID


# /tmp/kinsing deleteing here (Some times it will run /tmp path)
PID=$(pidof /tmp/kinsing)
echo "$PID"
kill -9 $PID


# kdevtmpfsi deleteing here
PID=$(pidof kdevtmpfsi)
echo "$PID"
kill -9 $PID


# /tmp/kdevtmpfsi deleteing here (Some times it will run /tmp path)
PID=$(pidof /tmp/kdevtmpfsi)
echo "$PID"
kill -9 $PID

# Delete malware files
find / -iname kdevtmpfsi -exec rm -fv {} \;

find / -iname kinsing -exec rm -fv {} \;
