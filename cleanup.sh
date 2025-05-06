#!/bin/bash

CONFIG_FILE="./cleanup.config"

# Read configuration file
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: Configuration file $CONFIG_FILE not found!"
  echo "Please create a file cleanup.config with the following content:"
  echo "BUCKET=your_bucket"
  echo "ORG=your_organization"
  echo "TOKEN=your_token"
  echo "OLDER_THAN=30d"
  echo "URL=http://localhost:8086"
  exit 1
fi

# Load parameters from config file
source "$CONFIG_FILE"

# Check if all variables are set
if [[ -z "$BUCKET" || -z "$ORG" || -z "$TOKEN" || -z "$OLDER_THAN" || -z "$URL" ]]; then
  echo "Error: Not all parameters are set in cleanup.config!"
  exit 1
fi

# Introduction
echo ""
echo ""
echo "-----------------------------------------------"
echo "|      Welcome to the InfluxDB Cleanup Tool!   |"
echo "-----------------------------------------------"
echo ""
echo "This script helps you identify and delete inactive measurements in InfluxDB."
echo ""
echo "The following parameters have been loaded:"
echo "Bucket: $BUCKET"
echo "Organization: $ORG"
echo "Time period: No new data for $OLDER_THAN"
echo "URL: $URL"
echo ""

# Confirmation before connection test
read -p "Continue with these parameters and test connection? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "Aborted by user."
  exit 0
fi

# Test connection with retry option
while true; do
  echo "Testing connection to InfluxDB at $URL..."
  if curl --silent --connect-timeout 5 --max-time 10 --head "$URL" | grep "HTTP/1.1 200 OK" > /dev/null; then
    echo "Connection successful!"
    break
  else
    echo "Error: Connection to InfluxDB instance failed."
    read -p "Try again? (y/n): " RETRY
    if [[ "$RETRY" != "y" ]]; then
      echo "Script will exit."
      exit 1
    fi
  fi
done

# Status log function
function log_status {
  echo "[Status] $1"
}

# Error check function with optional exit
function check_error {
  local error_message="$1"
  local exit_on_error="${2:-true}"
  
  if [ $? -ne 0 ]; then
    echo "Error: $error_message"
    if [ "$exit_on_error" = true ]; then
      exit 1
    fi
    return 1
  fi
  return 0
}

# Get last value for each measurement
log_status "Last value for each measurement in bucket '$BUCKET':"
echo "-----------------------------------------------"
echo "Measurement; Timestamp; Value"

# Get measurements (names only) with debug output
echo "Fetching all measurements..."
RAW_MEASUREMENTS=$(influx query 'import "influxdata/influxdb/schema"
schema.measurements(bucket: "'"$BUCKET"'")' --org "$ORG" --token "$TOKEN" --host "$URL" --raw 2>&1)

ALL_MEASUREMENTS=$(echo "$RAW_MEASUREMENTS" | awk -F, 'NR>3 {print $4}' | tr -d '\r' | grep -v '^$')
echo "Filtered measurement names:"
echo "$ALL_MEASUREMENTS"
echo "-----------------------------------------------"
echo "Number of measurements: $(echo "$ALL_MEASUREMENTS" | wc -l)"
echo "-----------------------------------------------"

if [[ -z "$ALL_MEASUREMENTS" ]]; then
  echo "[Error] No measurements found! Check connection and bucket name."
  exit 1
fi

INACTIVE_MEASUREMENTS=()

IFS=$'\n'
for MEAS in $ALL_MEASUREMENTS; do
  [ -z "$MEAS" ] && continue
  LAST_LINE=$(influx query "from(bucket: \"$BUCKET\")
    |> range(start: 0)
    |> filter(fn: (r) => r._measurement == \"$MEAS\" and r._field == \"value\")
    |> sort(columns:[\"_time\"], desc:true)
    |> limit(n:1)" \
    --org "$ORG" --token "$TOKEN" --host "$URL" --raw 2>/dev/null \
    | awk -F, -v meas="$MEAS" '$0 ~ /^,,/ && NF >= 8 { n = NF; print meas ";" $(n-3) ";" $(n-2) ";" $(n-1) }')

  echo "$LAST_LINE"

  LAST_TS=$(echo "$LAST_LINE" | awk -F';' '{print $2}')
  LAST_TS_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null)
  OLDER_THAN_DAYS=$(echo "$OLDER_THAN" | grep -o '[0-9]\+')
  LIMIT_TS_EPOCH=$(date -d "$(date +%Y-%m-%d) -$OLDER_THAN_DAYS days" +%s)
  echo "$MEAS: LAST_TS=$LAST_TS, LAST_TS_EPOCH=$LAST_TS_EPOCH, LIMIT_TS_EPOCH=$LIMIT_TS_EPOCH"
  if [ -n "$LAST_TS_EPOCH" ] && [ -n "$LIMIT_TS_EPOCH" ]; then
    if [ "$LAST_TS_EPOCH" -lt "$LIMIT_TS_EPOCH" ]; then
      echo "$MEAS is recognized as inactive!"
      INACTIVE_MEASUREMENTS+=("$MEAS;;$LAST_TS")
    fi
  echo ""
  fi
done
unset IFS

echo "-----------------------------------------------"
echo "Inactive measurements (older than $OLDER_THAN):"
for INACTIVE in "${INACTIVE_MEASUREMENTS[@]}"; do
  MEAS_NAME=$(echo "$INACTIVE" | awk -F';;' '{print $1}')
  MEAS_TS=$(echo "$INACTIVE" | awk -F';;' '{print $2}')
  echo "$MEAS_NAME ($MEAS_TS)"
done
echo "-----------------------------------------------"

if [ "${#INACTIVE_MEASUREMENTS[@]}" -eq 0 ]; then
  echo "No inactive measurements found."
  echo "Done."
  exit 0
fi

# Lists for summary
DELETED_MEASUREMENTS=()
KEPT_MEASUREMENTS=()

# Selection menu with repeat on invalid input
while true; do
  echo "What do you want to do?"
  echo "1 = Delete all inactive measurements"
  echo "2 = Ask for each inactive measurement"
  echo "q = Do not delete any measurement"
  read -p "Choice: " ACTION

  if [[ "$ACTION" == "1" ]]; then
    read -p "Are you sure you want to DELETE ALL inactive measurements? (y/n): " CONFIRM_ALL
    if [[ "$CONFIRM_ALL" == "y" ]]; then
      for INACTIVE in "${INACTIVE_MEASUREMENTS[@]}"; do
        MEAS_NAME=$(echo "$INACTIVE" | awk -F';;' '{print $1}')
        MEAS_TS=$(echo "$INACTIVE" | awk -F';;' '{print $2}')
        echo "Deleting: $MEAS_NAME"
        influx delete --bucket "$BUCKET" --org "$ORG" --token "$TOKEN" --host "$URL" --predicate "_measurement=\"$MEAS_NAME\"" --start 1970-01-01T00:00:00Z --stop $(date +%Y-%m-%dT%H:%M:%SZ)
        DELETED_MEASUREMENTS+=("$MEAS_NAME")
      done
      echo "All inactive measurements have been deleted."
      break
    else
      echo "Aborted. Nothing was deleted."
      KEPT_MEASUREMENTS=("${INACTIVE_MEASUREMENTS[@]}")
      break
    fi
  elif [[ "$ACTION" == "2" ]]; then
    for INACTIVE in "${INACTIVE_MEASUREMENTS[@]}"; do
      MEAS_NAME=$(echo "$INACTIVE" | awk -F';;' '{print $1}')
      MEAS_TS=$(echo "$INACTIVE" | awk -F';;' '{print $2}')
      while true; do
        read -p "Delete measurement $MEAS_NAME? (y/n): " CONFIRM_ONE
        if [[ "$CONFIRM_ONE" == "y" ]]; then
          echo "Deleting: $MEAS_NAME"
          influx delete --bucket "$BUCKET" --org "$ORG" --token "$TOKEN" --host "$URL" --predicate "_measurement=\"$MEAS_NAME\"" --start 1970-01-01T00:00:00Z --stop $(date +%Y-%m-%dT%H:%M:%SZ)
          DELETED_MEASUREMENTS+=("$MEAS_NAME")
          echo ""
          break
        elif [[ "$CONFIRM_ONE" == "n" ]]; then
          echo "$MEAS_NAME will be kept."
          KEPT_MEASUREMENTS+=("$MEAS_NAME")
          echo ""
          break
        else
          echo "Invalid input. Please enter 'y' or 'n'."
        fi
      done
    done
    break
  elif [[ "$ACTION" == "q" ]]; then
    echo "Nothing was deleted."
    KEPT_MEASUREMENTS=("${INACTIVE_MEASUREMENTS[@]}")
    break
  else
    echo "Invalid choice. Please select again."
  fi
done

# Summary
echo "-----------------------------------------------"
echo "Summary:"
echo "Active measurements:"
IFS=$'\n'
echo "$ALL_MEASUREMENTS" | while read -r MEAS; do
  FOUND=0
  for INACTIVE in "${INACTIVE_MEASUREMENTS[@]}"; do
    MEAS_NAME=$(echo "$INACTIVE" | awk -F';;' '{print $1}')
    if [[ "$MEAS" == "$MEAS_NAME" ]]; then
      FOUND=1
      break
    fi
  done
  if [[ $FOUND -eq 0 ]]; then
    echo "$MEAS"
  fi
done
unset IFS

echo ""
echo "--------------------------------"
echo "Inactive measurements:"
for INACTIVE in "${INACTIVE_MEASUREMENTS[@]}"; do
  echo "$INACTIVE"
done

echo ""
echo "--------------------------------"
echo "Deleted measurements:"
for DEL in "${DELETED_MEASUREMENTS[@]}"; do
  echo "$DEL"
done

echo ""
echo "--------------------------------"
echo "Kept (not deleted) inactive measurements:"
for KEEP in "${KEPT_MEASUREMENTS[@]}"; do
  echo "$KEEP"
done

echo "-----------------------------------------------"
echo "Done."
exit 0
