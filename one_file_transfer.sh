#!/bin/bash

PORT=9
MODE=""
FILENAME=""
IP_ADDR=""

function check_nc() {
    if ! command -v nc &> /dev/null; then
        echo "installing : netcat-openbsd"
        sudo apt install  -y netcat-openbsd
    fi
}

function receiver_mode() {
    echo "RECEIVER MODE"
    echo "Enter filename to save (default: received_file):"
    read -t 4 FILENAME
    
    if [ -z "$FILENAME" ]; then
        FILENAME="received_file"
    fi
    
    if [ -e "$FILENAME" ]; then
        echo "Warning: File $FILENAME already exists. Enter new name or press enter to overwrite:"
        read -r FILENAME_NEW
        if [ ! -z "$FILENAME_NEW" ]; then
            FILENAME="$FILENAME_NEW"
        fi
    fi
    
    echo "Waiting for connection on port $PORT..."
    nc -l -p $PORT > "$FILENAME"
    
    if [ -f "$FILENAME" ]; then
        echo "File received as: $FILENAME"
    else
        echo "Error: File transfer failed"
        exit 1
    fi
}

function sender_mode() {
    echo "SENDER MODE"
    echo "Enter the filename to send:"
    read -r FILENAME
    
    while [ ! -f "$FILENAME" ]; do
        echo "Error: File not found. Enter valid filename:"
        read -r FILENAME
    done
    
    echo "Enter destination IP or domain:"
    read -r IP_ADDR
    
    while [ -z "$IP_ADDR" ]; do
        echo "Error: IP/domain required. Please enter:"
        read -r IP_ADDR
    done
    
    echo "Sending file $FILENAME to $IP_ADDR:$PORT..."
    nc -q 1 "$IP_ADDR" $PORT < "$FILENAME"
    
    if [ $? -eq 0 ]; then
        echo "File transfer completed"
    else
        echo "Error: File transfer failed"
        exit 1
    fi
}

# Main script
check_nc

while [ -z "$MODE" ]; do
    echo "Select mode:"
    echo "1) Receiver"
    echo "2) Sender"
    read -r choice
    
    read -t 4 choice
    case $choice in
        1|"") MODE="receiver";;
        *) MODE="sender";;
    esac
done

if [ "$MODE" = "receiver" ]; then
	echo ""
    receiver_mode
else
	echo ""
    sender_mode
fi
