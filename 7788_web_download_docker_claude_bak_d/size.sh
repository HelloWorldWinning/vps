#!/bin/bash

# Function to get site-packages path
get_site_packages() {
    python3 -c "import site; print(site.getsitepackages()[0])"
}

# Function to format size
format_size() {
    numfmt --to=iec-i --suffix=B $1
}

# Get site-packages directory
SITE_PACKAGES=$(get_site_packages)

# Array of packages to check
packages=("fastapi" "uvicorn")

echo -e "\nPackage sizes in $SITE_PACKAGES:\n"
echo "PACKAGE               SIZE     LOCATION"
echo "------------------------------------------------"

for pkg in "${packages[@]}"; do
    # Find exact package directory (case insensitive)
    pkg_dir=$(find "$SITE_PACKAGES" -maxdepth 1 -iname "$pkg*" -type d 2>/dev/null)
    
    if [ -d "$pkg_dir" ]; then
        # Get size in bytes
        size=$(du -sb "$pkg_dir" 2>/dev/null | cut -f1)
        # Format size
        formatted_size=$(format_size $size)
        # Print result
        printf "%-20s %-8s %s\n" "$pkg" "$formatted_size" "$pkg_dir"
        
        # Get size of dist-info or egg-info
        info_dir=$(find "$SITE_PACKAGES" -maxdepth 1 -iname "${pkg}*.dist-info" -o -iname "${pkg}*.egg-info" 2>/dev/null)
        if [ ! -z "$info_dir" ]; then
            size=$(du -sb "$info_dir" 2>/dev/null | cut -f1)
            formatted_size=$(format_size $size)
            printf "%-20s %-8s %s\n" "└── metadata" "$formatted_size" "$info_dir"
        fi
    else
        echo "$pkg not found in site-packages"
    fi
done

# Get total size of all checked packages
echo -e "\nTotal sizes (including dependencies):"
echo "------------------------------------------------"
for pkg in "${packages[@]}"; do
    # Use pip show to get required packages
    echo "* $pkg dependencies:"
    pip show "$pkg" | grep "Requires:" | cut -d ":" -f2 | tr ',' '\n' | while read -r dep; do
        if [ ! -z "$dep" ]; then
            dep_dir=$(find "$SITE_PACKAGES" -maxdepth 1 -iname "$(echo $dep | tr -d ' ')*" -type d 2>/dev/null)
            if [ ! -z "$dep_dir" ]; then
                size=$(du -sb "$dep_dir" 2>/dev/null | cut -f1)
                formatted_size=$(format_size $size)
                printf "  %-20s %-8s %s\n" "$(basename "$dep_dir")" "$formatted_size" "$dep_dir"
            fi
        fi
    done
    echo ""
done

# Calculate and show grand total
echo "Grand total of all packages and dependencies:"
total_size=0
for pkg in "${packages[@]}"; do
    # Main package
    pkg_dir=$(find "$SITE_PACKAGES" -maxdepth 1 -iname "$pkg*" -type d 2>/dev/null)
    if [ -d "$pkg_dir" ]; then
        size=$(du -sb "$pkg_dir" 2>/dev/null | cut -f1)
        total_size=$((total_size + size))
    fi
    
    # Dependencies
    pip show "$pkg" | grep "Requires:" | cut -d ":" -f2 | tr ',' '\n' | while read -r dep; do
        if [ ! -z "$dep" ]; then
            dep_dir=$(find "$SITE_PACKAGES" -maxdepth 1 -iname "$(echo $dep | tr -d ' ')*" -type d 2>/dev/null)
            if [ ! -z "$dep_dir" ]; then
                size=$(du -sb "$dep_dir" 2>/dev/null | cut -f1)
                total_size=$((total_size + size))
            fi
        fi
    done
done

formatted_total=$(format_size $total_size)
echo "------------------------------------------------"
echo "Total: $formatted_total"
