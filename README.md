# deploy_agent_jansonhush

A shell script (`deploy_agent.sh`) that deploys, runs and archives the logs of a Student Attendance Tracker (a Python app). It also handles Ctrl+C and Ctrl+Z while a deployment is in progress.

The Python app (`attendance_checker.py`) is not modified. Everything here is shell scripting around it.

**Run-through video:** [https://youtube.com/jansonhush/myvideo]

## Repository contents

```
deploy_agent_jansonhush/
├── deploy_agent.sh          # the master script (all 3 features + signal handling)
├── README.md
└── templates/               # the 3 unmodified source files
    ├── attendance_checker.py
    ├── assets.csv
    └── config.json
```

## Requirements

- Linux with bash
- `python3`
- `zip`

The script checks for `python3` and `zip` before it deploys anything and stops with a clear message if one is missing.

## How to run the script and select a feature

Run it from the repo folder in deploy_agent_jansonhush/ exactly, because it looks for `templates/` there:

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

I used an **interactive menu**. After starting the script you pick a feature by typing its number:

```
===== Deploy Agent =====
1) Deploy the application
2) Run the application
3) Archive the logs
4) Exit
```

The menu comes back after each feature finishes, so you can deploy, run and archive in one session. Anything that is not 1-4 prints "Invalid option" and shows the menu again.

## Feature 1: Deploy

The script goes through these steps:

1. **Pre-flight checks.** It checks that `python3` and `zip` are installed, prints the Python version, and checks that `templates/` exists. If anything is missing it prints an error and returns to the menu.
2. **Project name.** It asks for a name (using `read`) and creates `attendance_tracker_<name>/`. An empty name is rejected. If the directory already exists, the script asks whether to overwrite it. Answering `y` deletes and rebuilds it. Anything else aborts and leaves the old directory untouched.
3. **Create the structure and copy the files.** It creates `Helpers/` and `reports/`, then copies `attendance_checker.py` and `config.json` from `templates/` without changing them. If `mkdir` or `cp` fails (for example, permission denied), it prints an error and removes what it created.
4. **Build the roster.** The script asks how to build `Helpers/assets.csv`:
   - **Option A: copy from the template.** It asks how many students and copies that many rows plus the header from `templates/assets.csv`. These students already have 4 recorded sessions, so `total_sessions` stays at `5`.
   - **Option B: generate a fresh roster.** It asks how many students and builds that many rows from a list of sample names. Attendance Count and Absence Count start at `0`. Since this is the first session, the script sets `total_sessions` to `1` in `config.json` with `sed`.
   - The student count must be a whole number of at least 1, otherwise it asks again.
5. **Permissions.** It runs `chmod +x` on `attendance_checker.py` and `chmod 600` on `Helpers/config.json` (owner read/write only), then prints the resulting permissions with `ls -l`.
6. **Alert thresholds.** It asks if you want to change them. If yes, it uses `read` to get new values for `warning` (default 75) and `failure` (default 50). Each value must be a number from 0 to 100, otherwise the script asks again. Then `sed` changes only the `"warning"` and `"failure"` lines in `Helpers/config.json`. The rest of the file is not reformatted or reordered.
7. **Verification.** The script finishes by running the app (Feature 2). If the app starts properly, the structure, roster and config all work together.

### Why total_sessions depends on the roster

`total_sessions` counts the sessions including today's, so it must always be one more than the prior sessions in the roster.

| Roster | Prior sessions per student | total_sessions |
|---|---|---|
| Option A (template copy) | 4 | 5 |
| Option B (fresh) | 0 | 1 |

## Feature 2: Run the application

Menu option 2 asks for the project name and runs:

```bash
cd attendance_tracker_<name>
python3 attendance_checker.py
```

If the project doesn't exist, it prints an error and tells you to deploy first. The app is interactive: it asks for each student `[P]resent or [A]bsent?`, updates the counts in `Helpers/assets.csv`, and writes `reports/attendance.log` and `reports/absent.log`.

## Feature 3: Archive the log files

Menu option 3 asks for the project name and archives the logs from `reports/`. Each log gets its own archive directory, and the filename has a timestamp (`YYYYMMDD_HHMMSS`) so every archived copy is unique:

```
attendance_tracker_<name>/
└── archives/
    ├── attendance/
    │   └── attendance_20261011_043012.log
    └── absent/
        └── absent_20261011_043012.log
```

How it works:

- For each log (`attendance` and `absent`) the script checks if `reports/<log>.log` exists.
- If it exists, the script creates `archives/<log>/` if needed, **moves** the file there with the timestamp in the name, and prints the final path. Because it is moved, `reports/` is empty afterwards.
- If it doesn't exist (for example nobody was absent, so `absent.log` was never created), the script prints that there is nothing to archive and continues without crashing.
- Both logs get the same timestamp from one run.

## Ctrl+C / Ctrl+Z handling

The script traps `SIGINT` (Ctrl+C) and `SIGTSTP` (Ctrl+Z) during deployment, from the moment the project name is entered until the deployment finishes. If you press either one, the script:

1. Prints that the deployment was interrupted.
2. Zips whatever exists of the project into `attendance_tracker_<name>_archive.zip` using the `zip` command.
3. Deletes the incomplete `attendance_tracker_<name>/` directory so no half-made folder is left behind.
4. Prints that the session is closing and exits.

If the zip fails, the directory is left in place so nothing is lost. If you interrupt before the directory was created, or while the script is asking about overwriting an existing one, nothing is zipped or deleted and the existing directory is untouched.

The trap is only for the shell script during deployment, not for `attendance_checker.py` while a marking session is running.

### How to test it

1. Run `./deploy_agent.sh`, choose 1, and enter a name such as `inttest`.
2. At a later prompt (for example "How many students?") press **Ctrl+C**.
3. Check the results:
   ```bash
   ls
   unzip -l attendance_tracker_inttest_archive.zip
   ```
   (If `unzip` is not installed, use `python3 -m zipfile -l attendance_tracker_inttest_archive.zip`.)
4. Repeat with **Ctrl+Z**.

What to expect: a message about the interruption, `attendance_tracker_inttest_archive.zip` in the repo folder, and no `attendance_tracker_inttest/` directory. The zip contains the partial project at the time of the interrupt, for example `attendance_checker.py`, `Helpers/config.json`, `Helpers/` and `reports/`. How much is inside depends on how far the deployment got.

## How I tested the deployed structure

After each deployment I checked:

```bash
ls -R attendance_tracker_<name>              # structure matches the required layout
ls -l attendance_tracker_<name>/attendance_checker.py     # should be -rwxr-xr-x
ls -l attendance_tracker_<name>/Helpers/config.json       # should be -rw-------
cat attendance_tracker_<name>/Helpers/assets.csv          # header + the right number of students
cat attendance_tracker_<name>/Helpers/config.json         # thresholds and total_sessions
```

Tests I ran:

- **Option A deployment:** the roster had the chosen number of students and `total_sessions` stayed at 5.
- **Option B deployment:** the roster counts were all 0 and `total_sessions` was set to 1.
- **Verification run and marking session:** the app started, marked the students, and created both logs in `reports/`.
- **Existing directory:** deploying the same name again asked about overwriting. `n` aborted, `y` rebuilt it.
- **Threshold input:** letters and numbers above 100 were rejected and asked again. Valid numbers updated only the two target lines in `config.json`.
- **Archiving:** both logs were moved into their own timestamped files. Running it again printed that the logs don't exist and did not crash.
- **Ctrl+C and Ctrl+Z during deployment:** a `.zip` was created and the incomplete directory was removed.
