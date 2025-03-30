#!/bin/bash

# Script to "delete" files/folders by moving them to /tmp

delete_to_tmp() {
    for item in "$@"; do
        if [ -e "$item" ]; then
            mv -v "$item" /tmp/
        else
            echo "Warning: $item does not exist"
        fi
    done
}

echo "Delete utility (moves items to /tmp/)"
echo "------------------------------------"
echo "1: Delete specific items (provide a list)"
echo "2: Delete everything in current directory"
echo

read -p "Choose an option (1/2): " option

case $option in
    1|"")  # Default to option 1
        echo "Enter items to delete (one item per line):"
        echo "When finished, enter an empty line."
        
        items=()
        while true; do
            read -p "> " item
            # Break on empty line
            [ -z "$item" ] && break
            items+=("$item")
        done
        
        # Check if any items were entered
        if [ ${#items[@]} -eq 0 ]; then
            echo "No items specified. Exiting."
            exit 0
        fi
        
        echo "The following items will be moved to /tmp/:"
        printf "  - %s\n" "${items[@]}"
        # No confirmation for option 1
        delete_to_tmp "${items[@]}"
        echo "Operation completed."
        ;;
        
    2)
        items=( * )
        
        # Check if directory is empty
        if [ "$(echo *)" = "*" ]; then
            echo "Current directory is empty. Nothing to delete."
            exit 0
        fi
        
        echo "The following items will be moved to /tmp/:"
        printf "  - %s\n" "${items[@]}"
        read -p "Are you sure you want to move ALL these items to /tmp? (y/n): " confirm
        
        if [[ $confirm == [Yy]* ]]; then
            delete_to_tmp "${items[@]}"
            echo "Operation completed."
        else
            echo "Operation cancelled."
        fi
        ;;
        
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac
