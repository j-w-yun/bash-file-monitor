#!/bin/bash

ROOT_DIR=".monitor"
MONITOR_FILE="$ROOT_DIR/monitors.txt"
FILES_HISTORY="$ROOT_DIR/files_history.txt"
COMMANDS_HISTORY="$ROOT_DIR/commands_history.txt"

function echo_color() {
    : '
    Function to print a message in color.
    Usage:
        echo_color "This is a message"  # Normal text on normal background
        echo_color ",red" "This is a message"  # Normal text on red background
        echo_color "red" "This is a message"  # Red text on normal background
        echo_color "red,white" "This is a message"  # Red text on white background
    '
    # Define the color codes
    declare -A FG=(
        [black]="\e[30m"
        [red]="\e[31m"
        [green]="\e[32m"
        [yellow]="\e[33m"
        [blue]="\e[34m"
        [magenta]="\e[35m"
        [cyan]="\e[36m"
        [lightgray]="\e[37m"
        [gray]="\e[90m"
        [lightred]="\e[91m"
        [lightgreen]="\e[92m"
        [lightyellow]="\e[93m"
        [lightblue]="\e[94m"
        [lightmagenta]="\e[95m"
        [lightcyan]="\e[96m"
        [white]="\e[97m"
    )
    declare -A BG=(
        [black]="\e[40m"
        [red]="\e[41m"
        [green]="\e[42m"
        [yellow]="\e[43m"
        [blue]="\e[44m"
        [magenta]="\e[45m"
        [cyan]="\e[46m"
        [lightgray]="\e[47m"
        [gray]="\e[100m"
        [lightred]="\e[101m"
        [lightgreen]="\e[102m"
        [lightyellow]="\e[103m"
        [lightblue]="\e[104m"
        [lightmagenta]="\e[105m"
        [lightcyan]="\e[106m"
        [white]="\e[107m"
    )
    local RESET="\e[0m"

    # This can be a message or a foreground color or a combination of foreground and background colors separated by a comma
    local color="${1}"
    # This is the message to print or empty if no color is provided (in which case the message is the color)
    local message="${2}"

    # Check if the color is a message or a color
    local color_code=""
    if [[ -z "$message" ]]; then
        # If no message is provided, the color is the message
        message="$color"
    else
        # Split the color into foreground and background colors
        IFS=',' read -r -a colors <<< "$color"
        local fg_color="${colors[0]}"
        local bg_color="${colors[1]}"
        if [[ -z "$fg_color" ]]; then
            # If no foreground color is provided
            color_code="${BG[$bg_color]}"
        elif [[ -z "$bg_color" ]]; then
            # If no background color is provided
            color_code="${FG[$fg_color]}"
        else
            # If both foreground and background colors are provided
            color_code="${FG[$fg_color]}${BG[$bg_color]}"
        fi
    fi

    # Print the message in color
    echo -ne "${color_code}${message}${RESET}"
}

function print_help() {
    # Print usage instructions
    echo_color "white" "This script monitors files for changes via inotifywait and executes a command when a change is detected.\n\n"
    echo_color "lightgreen" "Usage:\n"
    echo_color "white" "  $0 [OPTION]\n\n"
    echo_color "lightgreen" "Options:\n"
    echo_color "white" "  -l, --list\t\tlist active monitors\n"
    echo_color "white" "  -r, --reload\t\treload all monitors\n"
    echo_color "white" "  -k, --kill\t\tkill and delete all monitors\n"
    echo_color "white" "  -h, --help\t\tdisplay this help and exit\n"
}

function check_dependencies() {
    # Check if inotifywait is installed
    if ! command -v inotifywait &> /dev/null; then
        echo_color "lightred" "inotifywait is not installed\n"
        echo_color "lightred" "install inotify-tools to use this script\n"
        exit 1
    fi
}

function ensure_root() {
    # Ensure the script is run as root
    if [[ $EUID -ne 0 ]]; then
        echo_color "lightred" "this script must be run as root\n"
        echo_color "lightred" "see usage: $0 -h\n"
        exit 1
    fi
}

function initialize() {
    # Create the root directory and files if they don't exist
    # ensure_root
    check_dependencies
    mkdir -p "$ROOT_DIR"
    touch "$MONITOR_FILE"
    touch "$FILES_HISTORY"
    touch "$COMMANDS_HISTORY"
}

function num_monitors() {
    wc -l < "$MONITOR_FILE"
}

function read_input_with_history() {
    : '
    Read input with history support
        $1: prompt message
        $2: history file
        $3: output variable to store result
    '

    local prompt=$1
    local history_file=$2
    local -n result=$3
    local history=()
    local index=-1

    # Load history from file
    if [ -f "$history_file" ]; then
        mapfile -t history < "$history_file"
        index=${#history[@]}
    fi

    # Setup input field
    local input=""
    local key char

    echo -ne "$prompt"
    # Input loop
    while IFS= read -rsn1 key; do
        case $key in
            $'\x1B')  # Handle escape sequences for arrow keys
                read -rsn2 key
                case $key in
                    '[A')  # Up arrow
                        if [ $index -gt 0 ]; then
                            ((index--))
                            input="${history[index]}"
                            echo -ne "\r\033[K$prompt$input"
                        fi
                        ;;
                    '[B')  # Down arrow
                        if [ $index -lt ${#history[@]} ]; then
                            ((index++))
                            input="${history[index]:-}"
                            echo -ne "\r\033[K$prompt$input"
                        fi
                        ;;
                esac
                ;;
            '')  # Enter key
                echo
                break
                ;;
            $'\x7f')  # Handle backspace
                if [ "${#input}" -gt 0 ]; then
                    input="${input%?}"
                    echo -ne "\r\033[K$prompt$input"
                fi
                ;;
            *)  # Regular characters
                input+="$key"
                echo -n "$key"
                ;;
        esac
    done

    # Save new entry to history if it's not empty and different from the last entry
    if [[ -n "$input" ]]; then
        # Check if history is non-empty
        if [ ${#history[@]} -gt 0 ]; then
            # Check if the new entry is different from the last entry
            if [ "${history[-1]}" != "$input" ]; then
                echo "$input" >> "$history_file"
            fi
        else
            echo "$input" >> "$history_file"
        fi
    fi

    result="$input"
}

function kill_all() {
    pkill -9 -f "inotifywait"
}

function list_monitors() {
    echo

    local n_monitors=$(num_monitors)
    if [ $n_monitors -eq 0 ]; then
        echo_color "lightyellow" "no active monitors\n"
        return
    fi

    local i=1
    while IFS= read -r line; do
        local file="${line%%,*}"  # Everything before the first comma
        local command="${line#*, }"  # Everything after the first comma
        echo_color "lightblue" "$i. file=\"$file\" command=\"$command\"\n"
        ((i++))
    done < "$MONITOR_FILE"
}

function add_monitor() {
    local file command
    echo
    read_input_with_history "> file to monitor: " "$FILES_HISTORY" file

    # Check if the file exists
    if [ ! -f "$file" ]; then
        echo_color "lightred" "\nfile does not exist\n"
        return
    fi

    # Check if the file is already being monitored
    if grep -q "$file" "$MONITOR_FILE"; then
        echo_color "lightred" "\nfile is already being monitored\n"
        return
    fi

    read_input_with_history "> trigger command: " "$COMMANDS_HISTORY" command

    # Check if the command is not empty
    if [ -z "$command" ]; then
        echo_color "lightred" "\ncommand cannot be empty\n"
        return
    fi

    monitor_file "$file" "$command" &
    echo "$file, $command" >> "$MONITOR_FILE"
    echo_color "lightyellow" "> monitoring:\n    file=\"$file\"\n    command=\"$command\"\n"
}

function reload_all() {
    local n_monitors=$(num_monitors)
    if [ $n_monitors -eq 0 ]; then
        echo_color "lightyellow" "\nno active monitors\n"
        return
    fi

    # Kill all existing monitors
    kill_all

    # Load existing monitors and start monitoring them
    echo
    while IFS= read -r line; do
        local file="${line%%,*}"  # Everything before the first comma
        local command="${line#*, }"  # Everything after the first comma
        monitor_file "$file" "$command" &
        echo_color "lightyellow" "> loaded: file=\"$file\" command=\"$command\"\n"
    done < "$MONITOR_FILE"
}

function delete_monitor() {
    local n_monitors=$(num_monitors)
    if [ $n_monitors -eq 0 ]; then
        echo_color "lightyellow" "\nno active monitors\n"
        return
    fi

    list_monitors
    echo -ne "\n> select a monitor to delete: "
    read -r choice

    # Check if the choice is a valid number
    if ! [[ $choice =~ ^[0-9]+$ ]] || [ $choice -lt 1 ] || [ $choice -gt $n_monitors ]; then
        echo_color "lightred" "\ninvalid choice\n"
        return
    fi

    local line=$(sed -n "${choice}p" "$MONITOR_FILE")
    local file="${line%%,*}"  # Everything before the first comma
    local command="${line#*, }"  # Everything after the first comma
    pkill -9 -f "inotifywait.*${file}"
    sed -i "${choice}d" "$MONITOR_FILE"
    echo_color "lightyellow" "\n> deleted:\n    file=\"$file\"\n    command=\"$command\"\n"
}

function delete_all() {
    list_monitors
    echo -ne "\n> delete all monitors? [y/n]: "
    read -r choice
    if [[ $choice == "y" ]]; then
        kill_all
        > "$MONITOR_FILE"
        echo_color "lightyellow" "\n> deleted all monitors\n"
    fi
}

function monitor_file() {
    local file="$1"
    local command="$2"
    # Use nohup to ensure the process is immune to hangups and runs in the background
    nohup bash -c "inotifywait -m -e close_write --format '%w%f' '$file' | while read -r filename; do eval '$command'; done" >/dev/null 2>&1 &
}

function interactive_menu() {
    # Interactive menu navigation using raw input and ANSI escape codes
    local options=("list active monitors" "add a monitor" "reload all monitors" "delete a monitor" "delete all monitors" "exit")
    local current=0
    local input key

    # Hide cursor and clear screen
    tput civis
    clear

    # Menu control
    while true; do
        # Display menu
        for i in "${!options[@]}"; do
            if [[ $i == $current ]]; then
                # echo -e "\e[7m${options[$i]}\e[0m"
                echo_color "lightgreen" "> ${options[$i]}\n"
            else
                echo_color "lightgray" "  ${options[$i]}\n"
            fi
        done

        # Read a single character without pressing Enter
        IFS= read -rsn1 input

        # Determine action
        case $input in
            $'\x1B')  # Handle ESC sequence.
                # Read two more chars to get the full sequence.
                read -rsn2 -t 0.1 input
                if [[ $input == "[A" ]]; then
                    ((current = (current > 0 ? current - 1 : ${#options[@]} - 1)))
                elif [[ $input == "[B" ]]; then
                    ((current = (current + 1) % ${#options[@]}))
                fi
                ;;
            "")  # Handle Enter Key
                case $current in
                    0) list_monitors ;;
                    1) add_monitor ;;
                    2) reload_all ;;
                    3) delete_monitor ;;
                    4) delete_all ;;
                    5) pkill -P $$; break ;;
                esac
                echo_color "gray" "\npress any key to continue..."
                read -rsn1
                clear
                ;;
        esac
        # Position the cursor at the beginning of the list
        tput cuu $((${#options[@]} + 1))
    done

    # Show cursor and clear screen on exit
    tput cnorm
    clear
}

function start_interactive() {
    initialize
    clear
    interactive_menu
}

function main() {
    if [ $# -eq 0 ]; then
        # Start the interactive menu if no arguments are provided
        start_interactive
    else
        # If arguments are provided, execute the corresponding command
        case $1 in
            -l | --list) initialize; list_monitors ;;
            -r | --reload) initialize; reload_all ;;
            -k | --kill) initialize; delete_all ;;
            -h | --help) print_help ;;
            *) print_help ;;
        esac
    fi
}

main "$@"
