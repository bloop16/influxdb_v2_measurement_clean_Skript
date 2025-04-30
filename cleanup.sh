#!/bin/bash

# Einleitung
echo "Willkommen zum InfluxDB-Cleanup-Skript!"
echo "Dieses Skript hilft dir, inaktive Measurements in InfluxDB zu identifizieren und zu löschen."
echo ""

# Benutzer nach Eingaben fragen
read -p "Bitte gib den Namen des Buckets ein: " BUCKET
read -p "Bitte gib den Namen der Organisation ein: " ORG
read -p "Bitte gib dein API-Token ein: " TOKEN
read -p "Bitte gib den Zeitraum (z. B. 30d) ein, für den keine neuen Daten mehr vorhanden sein sollen: " OLDER_THAN
OLDER_THAN=${OLDER_THAN:-30d}  # Standardwert 30d setzen, falls nichts eingegeben wird
read -p "Bitte gib die URL deiner InfluxDB-Instanz ein (Standard: http://localhost:8086): " URL
URL=${URL:-http://localhost:8086}  # Standardwert setzen, falls nichts eingegeben wird

# Verbindung testen mit Timeout
echo "Prüfe die Verbindung zu InfluxDB unter $URL..."
if ! curl --silent --connect-timeout 5 --max-time 10 --head "$URL" | grep "HTTP/1.1 200 OK" > /dev/null; then
  echo "Fehler: Verbindung zur InfluxDB-Instanz fehlgeschlagen. Bitte überprüfe die URL oder den Serverstatus."
  exit 1
fi
echo "Verbindung erfolgreich!"

echo ""
echo "Folgende Parameter wurden gesetzt:"
echo "Bucket: $BUCKET"
echo "Organisation: $ORG"
echo "Zeitraum: Keine neuen Daten seit $OLDER_THAN"
echo "URL: $URL"
echo ""

# Funktion zur Statusanzeige
function log_status {
  echo "[Status] $1"
}

# Funktion zur Fehlerüberprüfung mit Optionen für Nichtbeenden
function check_error {
  local error_message="$1"
  local exit_on_error="${2:-true}"
  
  if [ $? -ne 0 ]; then
    echo "Fehler: $error_message"
    if [ "$exit_on_error" = true ]; then
      exit 1
    fi
    return 1
  fi
  return 0
}

# Funktion zum Extrahieren von Measurement-Namen aus InfluxDB-Ausgabe
function extract_measurements {
  local output="$1"
  local measurements=()
  
  while IFS= read -r line; do
    if [[ ! "$line" =~ ^# && ! "$line" =~ ^$ && "$line" =~ [a-zA-Z0-9] ]]; then
      measurement=$(echo "$line" | awk -F',' '{print $4}')
      if [[ ! -z "$measurement" && "$measurement" != "_measurement" ]]; then
        measurements+=("$measurement")
      fi
    fi
  done <<< "$output"
  
  echo "${measurements[@]}"
}

# Arrays für die Measurements erstellen
ALL_MEASUREMENTS=()
ACTIVE_MEASUREMENTS=()
INACTIVE_MEASUREMENTS=()

# Schritt 1: Alle Measurements mit verschiedenen Datentypen finden
log_status "Verbindung zu InfluxDB unter $URL..."
log_status "Suche nach allen Measurements (nach Datentyp getrennt)..."

# Query für float-Werte mit Timeout
log_status "Suche nach Measurements mit float-Werten..."
FLOAT_MEASUREMENTS_OUTPUT=$(timeout 60 influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -10y)
  |> filter(fn: (r) => types.isType(v: r._value, type: "float"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)

if [ $? -eq 0 ] && [ ! -z "$FLOAT_MEASUREMENTS_OUTPUT" ]; then
  echo "Float-Measurements erfolgreich abgefragt."
  FLOAT_MEASUREMENTS=($(extract_measurements "$FLOAT_MEASUREMENTS_OUTPUT"))
  ALL_MEASUREMENTS+=("${FLOAT_MEASUREMENTS[@]}")
  echo "Gefundene Float-Measurements: ${#FLOAT_MEASUREMENTS[@]}"
else
  echo "Warnung: Keine Float-Measurements gefunden oder Abfrage fehlgeschlagen."
fi

# Query für string-Werte mit Timeout
log_status "Suche nach Measurements mit string-Werten..."
STRING_MEASUREMENTS_OUTPUT=$(timeout 60 influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -10y)
  |> filter(fn: (r) => types.isType(v: r._value, type: "string"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)

if [ $? -eq 0 ] && [ ! -z "$STRING_MEASUREMENTS_OUTPUT" ]; then
  echo "String-Measurements erfolgreich abgefragt."
  STRING_MEASUREMENTS=($(extract_measurements "$STRING_MEASUREMENTS_OUTPUT"))
  ALL_MEASUREMENTS+=("${STRING_MEASUREMENTS[@]}")
  echo "Gefundene String-Measurements: ${#STRING_MEASUREMENTS[@]}"
else
  echo "Warnung: Keine String-Measurements gefunden oder Abfrage fehlgeschlagen."
fi

# Query für boolean-Werte mit Timeout
log_status "Suche nach Measurements mit boolean-Werten..."
BOOLEAN_MEASUREMENTS_OUTPUT=$(timeout 60 influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -10y)
  |> filter(fn: (r) => types.isType(v: r._value, type: "bool"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)

if [ $? -eq 0 ] && [ ! -z "$BOOLEAN_MEASUREMENTS_OUTPUT" ]; then
  echo "Boolean-Measurements erfolgreich abgefragt."
  BOOLEAN_MEASUREMENTS=($(extract_measurements "$BOOLEAN_MEASUREMENTS_OUTPUT"))
  ALL_MEASUREMENTS+=("${BOOLEAN_MEASUREMENTS[@]}")
  echo "Gefundene Boolean-Measurements: ${#BOOLEAN_MEASUREMENTS[@]}"
else
  echo "Warnung: Keine Boolean-Measurements gefunden oder Abfrage fehlgeschlagen."
fi

# Schritt 2: Aktive Measurements mit verschiedenen Datentypen finden
log_status "Suche nach aktiven Measurements (nach Datentyp getrennt)..."

# Query für aktive float-Werte mit Timeout
log_status "Suche nach aktiven Measurements mit float-Werten..."
ACTIVE_FLOAT_OUTPUT=$(timeout 60 influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "float"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)

if [ $? -eq 0 ] && [ ! -z "$ACTIVE_FLOAT_OUTPUT" ]; then
  echo "Aktive Float-Measurements erfolgreich abgefragt."
  ACTIVE_FLOAT_MEASUREMENTS=($(extract_measurements "$ACTIVE_FLOAT_OUTPUT"))
  ACTIVE_MEASUREMENTS+=("${ACTIVE_FLOAT_MEASUREMENTS[@]}")
  echo "Gefundene aktive Float-Measurements: ${#ACTIVE_FLOAT_MEASUREMENTS[@]}"
else
  echo "Warnung: Keine aktiven Float-Measurements gefunden oder Abfrage fehlgeschlagen."
fi

# Query für aktive string-Werte mit Timeout
log_status "Suche nach aktiven Measurements mit string-Werten..."
ACTIVE_STRING_OUTPUT=$(timeout 60 influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "string"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)

if [ $? -eq 0 ] && [ ! -z "$ACTIVE_STRING_OUTPUT" ]; then
  echo "Aktive String-Measurements erfolgreich abgefragt."
  ACTIVE_STRING_MEASUREMENTS=($(extract_measurements "$ACTIVE_STRING_OUTPUT"))
  ACTIVE_MEASUREMENTS+=("${ACTIVE_STRING_MEASUREMENTS[@]}")
  echo "Gefundene aktive String-Measurements: ${#ACTIVE_STRING_MEASUREMENTS[@]}"
else
  echo "Warnung: Keine aktiven String-Measurements gefunden oder Abfrage fehlgeschlagen."
fi

# Query für aktive boolean-Werte mit Timeout
log_status "Suche nach aktiven Measurements mit boolean-Werten..."
ACTIVE_BOOLEAN_OUTPUT=$(timeout 60 influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "bool"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)

if [ $? -eq 0 ] && [ ! -z "$ACTIVE_BOOLEAN_OUTPUT" ]; then
  echo "Aktive Boolean-Measurements erfolgreich abgefragt."
  ACTIVE_BOOLEAN_MEASUREMENTS=($(extract_measurements "$ACTIVE_BOOLEAN_OUTPUT"))
  ACTIVE_MEASUREMENTS+=("${ACTIVE_BOOLEAN_MEASUREMENTS[@]}")
  echo "Gefundene aktive Boolean-Measurements: ${#ACTIVE_BOOLEAN_MEASUREMENTS[@]}"
else
  echo "Warnung: Keine aktiven Boolean-Measurements gefunden oder Abfrage fehlgeschlagen."
fi

# Entferne Duplikate aus den Arrays
ALL_MEASUREMENTS=($(echo "${ALL_MEASUREMENTS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
ACTIVE_MEASUREMENTS=($(echo "${ACTIVE_MEASUREMENTS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

echo "Gefundene Measurements insgesamt: ${#ALL_MEASUREMENTS[@]}"
echo "Gefundene aktive Measurements: ${#ACTIVE_MEASUREMENTS[@]}"

# Finde inaktive Measurements (in ALL_MEASUREMENTS, aber nicht in ACTIVE_MEASUREMENTS)
for measurement in "${ALL_MEASUREMENTS[@]}"; do
  is_active=false
  for active in "${ACTIVE_MEASUREMENTS[@]}"; do
    if [[ "$measurement" == "$active" ]]; then
      is_active=true
      break
    fi
  done
  
  if [[ "$is_active" == "false" ]]; then
    INACTIVE_MEASUREMENTS+=("$measurement")
  fi
done

echo ""
echo "Gefundene inaktive Measurements (ohne neue Daten seit $OLDER_THAN):"
for measurement in "${INACTIVE_MEASUREMENTS[@]}"; do
  echo "- $measurement"
done

# Anzeige der Gesamtzahl der Measurements
echo ""
echo "Zusammenfassung:"
echo "Alle Measurements: ${#ALL_MEASUREMENTS[@]}"
echo "Aktive Measurements: ${#ACTIVE_MEASUREMENTS[@]}"
echo "Inaktive Measurements: ${#INACTIVE_MEASUREMENTS[@]}"

# Schritt 3: Measurements löschen nach Bestätigung
if [[ ${#INACTIVE_MEASUREMENTS[@]} -gt 0 ]]; then
  echo ""
  echo "Möchtest du fortfahren und inaktive Measurements löschen? (ja/nein)"
  read -p "Deine Auswahl: " CONTINUE

  if [[ "$CONTINUE" == "ja" ]]; then
    TOTAL_MEASUREMENTS=${#INACTIVE_MEASUREMENTS[@]}
    CURRENT_MEASUREMENT=0
    
    for MEASUREMENT in "${INACTIVE_MEASUREMENTS[@]}"; do
      CURRENT_MEASUREMENT=$((CURRENT_MEASUREMENT + 1))
      PERCENT=$((CURRENT_MEASUREMENT * 100 / TOTAL_MEASUREMENTS))
      
      echo "Fortschritt: $PERCENT% ($CURRENT_MEASUREMENT/$TOTAL_MEASUREMENTS)"
      echo "Measurement: $MEASUREMENT"
      read -p "Soll dieses Measurement gelöscht werden? (ja/nein): " CONFIRMATION
      if [[ "$CONFIRMATION" == "ja" ]]; then
        echo "Lösche $MEASUREMENT..."
        influx delete \
          --bucket "$BUCKET" \
          --org "$ORG" \
          --start "1970-01-01T00:00:00Z" \
          --stop "$(date -Iseconds --utc)" \
          --predicate "_measurement=\"$MEASUREMENT\"" \
          --token "$TOKEN"
        echo "Measurement $MEASUREMENT gelöscht."
      else
        echo "Measurement $MEASUREMENT wurde nicht gelöscht."
      fi
    done
  else
    echo "Abbruch durch Benutzer."
  fi
else
  echo "Keine inaktiven Measurements gefunden. Nichts zu löschen."
fi

echo "Skript abgeschlossen."
