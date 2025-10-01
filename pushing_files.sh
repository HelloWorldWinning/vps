#!/bin/bash

# A robust, interactive script to upload files/folders to a specified API endpoint.
# It collects all paths first, then processes them concurrently.

# --- Configuration ---
API_PORT="7778"
API_PASSWD="kkb"

# --- Colors for better output ---
with_len=92
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD_RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Function to upload a single file ---
upload_file() {
	local file_path="$1"
	local api_host="$2"

	if [ ! -f "$file_path" ]; then
		echo -e "${YELLOW}Warning: Skipping non-file item found by find: $file_path${NC}"
		return
	fi

	echo " queuing : ${file_path}"
	response=$(curl -s -X POST "http://${api_host}:${API_PORT}/?api_passwd=${API_PASSWD}" -F "file=@${file_path}")

	if [ $? -ne 0 ]; then
		echo -e "${RED} FAILED: ${file_path} (Curl Error - Could not connect to server)${NC}"
		return
	fi

	if [ -z "$response" ]; then
		echo -e "${RED} FAILED: ${file_path} (Empty reply from server)${NC}"
		return
	fi

	if echo "${response}" | jq -e '.saved_success == true' >/dev/null; then
		saved_path=$(echo "${response}" | jq -r '.path')
#	echo -e "${GREEN}SUCCESS: ${file_path} -> ${saved_path}${NC}"
#
		echo -e "${BOLD_RED}SUCCESS: ${file_path} -> ${saved_path}${NC}\n$(printf '%*s' $(($(tput cols) * ${with_len} / 100)) '' | tr ' ' -)"
               # echo -e "-------------------------------------------------------------------------------------------------------------"
	#       echo "$(printf '%*s' $(($(tput cols) * ${with_len} / 100)) '' | tr ' ' -)"

	else
		echo -e "${RED} FAILED: ${file_path} -> Server Response: ${response}${NC}"
	fi
}

# --- Main Script Logic ---

# 1. Check for dependencies
command -v curl >/dev/null 2>&1 || {
	echo >&2 -e "${RED}Error: 'curl' is not installed.${NC}"
	exit 1
}
command -v jq >/dev/null 2>&1 || {
	echo >&2 -e "${RED}Error: 'jq' is not installed.${NC}"
	exit 1
}
command -v nc >/dev/null 2>&1 || {
	echo >&2 -e "${RED}Error: 'nc' (netcat) is not installed. It is required for the server health check.${NC}"
	exit 1
}

# === Step 1: Get Target Server and Check Connectivity ===
echo -e "${CYAN}Step 1: Target Server${NC}"
#read -p "Please enter the destination domain or IP address: " API_HOST
read -p "destination domain or IP:  " API_HOST
if [ -z "${API_HOST}" ]; then
	echo -e "${RED}Error: Domain or IP is a mandatory requirement.${NC}"
	exit 1
fi

echo "Checking server connectivity..."
if ! nc -z -w 5 "$API_HOST" "$API_PORT"; then
	echo -e "${RED}Error: Server '${API_HOST}' is not reachable on port '${API_PORT}'. Please check the address and ensure the service is running.${NC}"
	exit 1
fi
#echo -e "${GREEN}Server is online.${NC}"
echo "---------------------------------"
echo -e "${BOLD_RED}Server is online.${NC}"
echo "---------------------------------"

# === Step 2: Collect All File/Folder Paths ===
echo -e "${CYAN}Step 2: Files and Folders to Upload${NC}"
#echo "Enter one file/folder path per line. Press ENTER on an empty line when you are done."
echo -e  "Enter one file/folder path per line. \nPress ENTER on an empty line when you are done."
echo "---------------------------------"

declare -a all_items=()
while IFS= read -r item; do
	[ -z "$item" ] && break
	all_items+=("$item")
done

if [ ${#all_items[@]} -eq 0 ]; then
	echo -e "${RED}Error: No paths were entered.${NC}"
	exit 1
fi
echo "---"

# === Step 3: Process and Upload All Collected Paths ===
echo -e "${CYAN}Processing ${#all_items[@]} item(s)...${NC}"
process_count=0
for item in "${all_items[@]}"; do
	eval item_expanded="$item"

	if [ -f "${item_expanded}" ]; then
		upload_file "${item_expanded}" "${API_HOST}" &
		process_count=$((process_count + 1))
	elif [ -d "${item_expanded}" ]; then
		echo "Searching for files in directory: ${item_expanded}"
		# Use a subshell and find to count files to upload
		file_list=()
		while IFS= read -r -d $'\0' file; do
			file_list+=("$file")
		done < <(find "${item_expanded}" -type f -print0)

		for file in "${file_list[@]}"; do
			upload_file "${file}" "${API_HOST}" &
			process_count=$((process_count + 1))
		done
	else
		echo -e "${YELLOW}Warning: '${item}' is not a valid file or directory. Skipping.${NC}"
	fi
done

if [ "$process_count" -eq 0 ]; then
	echo -e "${RED}Error: No valid files were found in the provided paths.${NC}"
	exit 1
fi


# === Step 4: Wait for Completion ===
echo "---"
echo "Waiting for all ${process_count} uploads to complete..."
#echo -e "-------------------------------------------------------------------------------------------------------------"
echo "$(printf '%*s' $(($(tput cols) * ${with_len}/ 100)) '' | tr ' ' -)"
wait
#echo "---"
echo -e "${GREEN}All tasks finished.${NC}"
