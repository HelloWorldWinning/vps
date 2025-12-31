ee() {
	# Define usage function
	usage() {
		echo "Usage: eee [-t|-T|-s|-S] <search_term> [additional_terms...]"
		echo "  -t : sort by time, latest at bottom (default)"
		echo "  -T : sort by time, latest at top"
		echo "  -s : sort by size, largest at bottom"
		echo "  -S : sort by size, largest at top"
		return 1
	}

	# Parse options
	local sort_type="-t" # default sort
	if [[ "$1" == -[tTsS] ]]; then
		sort_type="$1"
		shift
	fi

	# Check for search term
	if [ "$#" -lt 1 ]; then
		usage
		return 1
	fi

	local search_term="$1"
	shift
	local additional_terms=("$@")

	# Create temporary file
	local tmp_file=$(mktemp)
	trap 'rm -f "$tmp_file"' EXIT

	# Step 1: Collect all matches using the original ee function's core
	# /usr/lib/cargo/bin/fd --list-details --strip-cwd-prefix --color=never "$search_term" "${additional_terms[@]}" | \
	/usr/lib/cargo/bin/fd --list-details --color=never "$search_term" "${additional_terms[@]}" |
		rg --color=never --regexp "[^/]*${search_term}[^/]*" >"$tmp_file"

	# Step 2: Process and sort the results
	while IFS= read -r line; do
		# Extract components (permissions, links, owner, group, size, date, time, path)
		local perms=$(echo "$line" | awk '{print $1}')
		local links=$(echo "$line" | awk '{print $2}')
		local owner=$(echo "$line" | awk '{print $3}')
		local group=$(echo "$line" | awk '{print $4}')
		local size_raw=$(echo "$line" | awk '{print $5}')
		local month=$(echo "$line" | awk '{print $6}')
		local day=$(echo "$line" | awk '{print $7}')
		local time=$(echo "$line" | awk '{print $8}')
		local path=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=$7=$8=""; print substr($0,9)}')

		# Convert size to bytes using awk for decimal support
		local size_in_bytes
		if [[ $size_raw =~ ^[0-9.]+[KMG]?$ ]]; then
			size_in_bytes=$(echo "$size_raw" | awk '
                function convert(size) {
                    if (size ~ /K$/) return substr(size, 1, length(size)-1) * 1024
                    if (size ~ /M$/) return substr(size, 1, length(size)-1) * 1024 * 1024
                    if (size ~ /G$/) return substr(size, 1, length(size)-1) * 1024 * 1024 * 1024
                    return size
                }
                { printf "%.0f", convert($1) }
            ')
		else
			size_in_bytes=0
		fi

		# Convert date to timestamp (handling current year)
		local year=$(date +%Y)
		local month_num=$(date -d "$month 1" +%m 2>/dev/null || echo "01")
		local timestamp=$(date -d "$year-$month_num-$day $time" +%s 2>/dev/null || echo "0")

		# Print with sort key based on sort type
		case "$sort_type" in
		-t | -T) echo "$timestamp|$line" ;;
		-s | -S) echo "$size_in_bytes|$line" ;;
		esac
	done <"$tmp_file" | {
		case "$sort_type" in
		-t) sort -n ;;
		-T) sort -nr ;;
		-s) sort -n ;;
		-S) sort -nr ;;
		esac
	} | cut -d'|' -f2- |
		rg --color=always \
			--colors 'match:fg:yellow' \
			--colors 'line:none' \
			--regexp "[^/]*${search_term}[^/]*"
}
