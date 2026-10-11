#!/bin/bash
# deploy_agent.sh
# Deploys, runs and archives the logs of the attendance tracker

# the fokder being built right now (the trap uses this)
project=""

# runs when the user presses Ctrl+C or Ctrl+Z during deployment
cleanup() {
    echo ""
    echo "Deployment was interrupted!"
    if [ -n "$project" ] && [ -d "$project" ]; then
        echo "Zipping the incomplete project..."
        if zip -r "${project}_archive.zip" "$project" > /dev/null; then
            rm -rf "$project"
            echo "Saved ${project}_archive.zip and deleted $project"
        else
            echo "zip failed, so I left $project alone"
        fi
    else
        echo "Nothing was created yet."
    fi
    echo "Closing the session."
    exit 1
}

# returns success only if the text is a whole number
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

#-Feature 1: deploy-
deploy() {
    # step 1: pre-flight checks
    for tool in python3 zip; do
        if ! command -v "$tool" > /dev/null; then
            echo "Error: $tool is not installed."
            return
        fi
    done
    python3 --version

    if [ ! -d templates ]; then
        echo "Error: templates/ folder not found. Run this from the root, repo folder."
        return
    fi

    # step 2: name the project
    read -p "Enter a name for the project: " name
    if [ -z "$name" ]; then
        echo "Error: the name cannot be empty."
        return
    fi
    dir="attendance_tracker_$name"

    # catch Ctrl+C and Ctrl+Z from here on
    trap cleanup SIGINT SIGTSTP

    if [ -d "$dir" ]; then
        read -p "$dir already exists. Overwrite it? (y/n): " answer
        if [ "$answer" = "y" ]; then
            rm -rf "$dir" || { echo "Error: could not delete $dir"; trap - SIGINT SIGTSTP; return; }
        else
            echo "Aborted. Nothing was changed."
            trap - SIGINT SIGTSTP
            return
        fi
    fi

    mkdir -p "$dir/Helpers" "$dir/reports" || { echo "Error: could not create $dir (permission denied?)"; trap - SIGINT SIGTSTP; return; }
    project="$dir"
    echo "Created $dir with Helpers/ and reports/"

    # step 3: copy the files
    cp templates/attendance_checker.py "$dir/" || { echo "Error: could not copy attendance_checker.py"; rm -rf "$dir"; project=""; trap - SIGINT SIGTSTP; return; }
    cp templates/config.json "$dir/Helpers/" || { echo "Error: could not copy config.json"; rm -rf "$dir"; project=""; trap - SIGINT SIGTSTP; return; }

    echo "How do you want to build the roster?"
    echo "A) copy from templates/assets.csv"
    echo "B) generate a fresh roster"
    read -p "Choose A or B: " choice
    while [ "$choice" != "A" ] && [ "$choice" != "B" ]; do
        read -p "Please type A or B: " choice
    done

    read -p "How many students? " count
    while ! is_number "$count" || [ "$count" -lt 1 ]; do
        read -p "Please enter a number greater than 0: " count
    done

    if [ "$choice" = "A" ]; then
        # header line + the number of students asked for
        head -n $((count + 1)) templates/assets.csv > "$dir/Helpers/assets.csv"
        rows=$(( $(grep -c "" "$dir/Helpers/assets.csv") - 1 ))
        echo "Copied $rows students from the template (4 sessions already recorded)."
        echo "total_sessions stays at 5."
    else
        names=(Alice Bob Charlie Diana Edward Fiona George Hannah Ian Julia)
        echo "Email,Names,Attendance Count,Absence Count" > "$dir/Helpers/assets.csv"
        for ((i = 0; i < count; i++)); do
            student=${names[$((i % 10))]}
            if [ "$i" -ge 10 ]; then
                student="$student$((i / 10 + 1))"
            fi
            email="${student,,}@example.com"
            echo "$email,$student,0,0" >> "$dir/Helpers/assets.csv"
        done
        # fresh roster means this is session number 1
        sed -i 's/"total_sessions": 5/"total_sessions": 1/' "$dir/Helpers/config.json"
        echo "Generated $count students. total_sessions set to 1."
    fi

    # step 4: permissions
    chmod +x "$dir/attendance_checker.py"
    chmod 600 "$dir/Helpers/config.json"
    echo "Permissions set:"
    ls -l "$dir/attendance_checker.py" "$dir/Helpers/config.json"

    # step 5: thresholds
    read -p "Do you want to change the alert thresholds? (y/n): " change
    if [ "$change" = "y" ]; then
        for level in warning failure; do
            read -p "New $level threshold (0-100): " value
            while ! is_number "$value" || [ "$value" -gt 100 ]; do
                read -p "Enter a number between 0 and 100: " value
            done
            sed -i "s/\(\"$level\": \)[0-9]*/\1$value/" "$dir/Helpers/config.json"
        done
        echo "Updated config.json:"
        grep -E '"warning"|"failure"' "$dir/Helpers/config.json"
    fi

    # deployment is done, so stop catching the signals
    trap - SIGINT SIGTSTP
    project=""

    # step 6: verify by running the app
    echo "Deployment finished. Running the app to verify..."
    cd "$dir" && python3 attendance_checker.py
    cd ..
}

#-Feature 2: run-
run_app() {
    read -p "Project name: " name
    dir="attendance_tracker_$name"
    if [ ! -d "$dir" ]; then
        echo "Error: $dir does not exist. Deploy it first."
        return
    fi
    cd "$dir" && python3 attendance_checker.py
    cd ..
}

# Feature 3: arcive logs-
archive_logs() {
    read -p "Project name: " name
    dir="attendance_tracker_$name"
    if [ ! -d "$dir" ]; then
        echo "Error: $dir does not exist."
        return
    fi

    stamp=$(date +%Y%m%d_%H%M%S)

    for log in attendance absent; do
        if [ -f "$dir/reports/$log.log" ]; then
            mkdir -p "$dir/archives/$log"
            mv "$dir/reports/$log.log" "$dir/archives/$log/${log}_$stamp.log"
            echo "Archived $log.log -> $dir/archives/$log/${log}_$stamp.log"
        else
            echo "$log.log does not exist, nothing to archive."
        fi
    done
}

#-main menu-
while true; do
    echo ""
    echo "===== Deploy Agent ====="
    echo "1) Deploy the application"
    echo "2) Run the application"
    echo "3) Archive the logs"
    echo "4) Exit"
    read -p "Choose an option: " option
    case "$option" in
        1) deploy ;;
        2) run_app ;;
        3) archive_logs ;;
        4) echo "SEE YOU, G!"; exit 0 ;;
        *) echo "Invalid option, try again." ;;
    esac
done
