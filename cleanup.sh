#!/bin/bash

# Einleitung
echo "Willkommen zum InfluxDB-Cleanup-Skript!"
echo "Dieses Skript hilft dir, alte Measurements in InfluxDB zu identifizieren und zu löschen."
echo ""

# Benutzer nach Eingaben fragen
read -p "Bitte gib den Namen des Buckets ein: " BUCKET
read -p "Bitte gib den Namen der Organisation ein: " ORG
read -p "Bitte gib dein API-Token ein: " TOKEN
read -p "Bitte gib den Zeitraum (z. B. 30d) ein, für den ältere Daten gesucht werden sollen: " OLDER_THAN
read -p "Bitte gib die URL deiner InfluxDB-Instanz ein (Standard: http://localhost:8086): " URL
URL=${URL:-http://localhost:8086}  # Standardwert setzen, falls nichts eingegeben wird

# Verbindung testen
echo "Prüfe die Verbindung zu InfluxDB unter $URL..."
if ! curl --silent --head "$URL" | grep "HTTP/1.1 200 OK" > /dev/null; then
  echo "Fehler: Verbindung zur InfluxDB-Instanz fehlgeschlagen. Bitte überprüfe die URL oder den Serverstatus."
  exit 1
fi
echo "Verbindung erfolgreich!"

echo ""
echo "Folgende Parameter wurden gesetzt:"
echo "Bucket: $BUCKET"
echo "Organisation: $ORG"
echo "Zeitraum: Älter als $OLDER_THAN"
echo "URL: $URL"
echo ""

# Funktion zur Statusanzeige
function log_status {
  echo "[Status] $1"
}

# Funktion zur Fehlerüberprüfung
function check_error {
  if [ $? -ne 0 ]; then
    echo "Fehler: $1"
    exit 1
  fi
}

# Funktion zum Filtern der Metadaten aus InfluxDB-Antworten
function filter_influx_output {
  local output="$1"
  # Filtert Metadaten-Zeilen und extrahiert nur die Measurement-Namen
  echo "$output" | grep -v "^#" | grep -v "^," | grep -v "^$" | awk -F',' '{print $4}' | sort | uniq | grep -v "^$"
}

# Arrays für die Measurements erstellen
FLOAT_MEASUREMENTS_ARRAY=()
STRING_MEASUREMENTS_ARRAY=()
BOOLEAN_MEASUREMENTS_ARRAY=()

# Schritt 1: Measurements mit verschiedenen Datentypen getrennt abrufen
log_status "Verbindung zu InfluxDB unter $URL..."
log_status "Suche nach Measurements mit float-Werten..."
FLOAT_OUTPUT=$(influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "float"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)
check_error "Abfrage für float-Werte fehlgeschlagen."

# Filtere die Metadaten aus dem Ergebnis
FILTERED_FLOAT_OUTPUT=$(filter_influx_output "$FLOAT_OUTPUT")

echo ""
echo "Gefundene Measurements (float):"
while read -r line; do
  if [[ ! -z "$line" ]]; then
    echo "- $line"
    FLOAT_MEASUREMENTS_ARRAY+=("$line")
  fi
done <<< "$FILTERED_FLOAT_OUTPUT"

log_status "Verbindung zu InfluxDB unter $URL..."
log_status "Suche nach Measurements mit string-Werten..."
# Verwende try/catch-Struktur für den String-Query
STRING_OUTPUT=$(influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "string"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null) || true

# Prüfe, ob die Ausgabe leer ist, ohne einen Fehler auszugeben
if [[ -z "$STRING_OUTPUT" ]]; then
  echo "Keine Measurements mit string-Werten gefunden."
else
  # Filtere die Metadaten aus dem Ergebnis
  FILTERED_STRING_OUTPUT=$(filter_influx_output "$STRING_OUTPUT")
  
  echo ""
  echo "Gefundene Measurements (string):"
  while read -r line; do
    if [[ ! -z "$line" ]]; then
      echo "- $line"
      STRING_MEASUREMENTS_ARRAY+=("$line")
    fi
  done <<< "$FILTERED_STRING_OUTPUT"
fi

# Gleiche Anpassungen für bool-Werte
log_status "Verbindung zu InfluxDB unter $URL..."
log_status "Suche nach Measurements mit boolean-Werten..."
BOOLEAN_OUTPUT=$(influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "bool"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null) || true

if [[ -z "$BOOLEAN_OUTPUT" ]]; then
  echo "Keine Measurements mit boolean-Werten gefunden."
else
  FILTERED_BOOLEAN_OUTPUT=$(filter_influx_output "$BOOLEAN_OUTPUT")
  
  echo ""
  echo "Gefundene Measurements (boolean):"
  while read -r line; do
    if [[ ! -z "$line" ]]; then
      echo "- $line"
      BOOLEAN_MEASUREMENTS_ARRAY+=("$line")
    fi
  done <<< "$FILTERED_BOOLEAN_OUTPUT"
fi

# Option zum Ausschließen aktiver Measurements
echo ""
echo "Möchtest du aktive Measurements ausschließen? (ja/nein)"
read -p "Deine Auswahl: " EXCLUDE_ACTIVE

if [[ "$EXCLUDE_ACTIVE" == "ja" ]]; then
  echo ""
  echo "Gib eine Liste von Measurements ein, die beibehalten werden sollen (durch Komma getrennt):"
  read -p "Zu behaltende Measurements: " KEEP_MEASUREMENTS
  
  # Konvertiere die Eingabe in ein Array
  IFS=',' read -ra KEEP_ARRAY <<< "$KEEP_MEASUREMENTS"
  
  # Filtere die zu behaltenden Measurements aus den Arrays
  for keep in "${KEEP_ARRAY[@]}"; do
    keep=$(echo "$keep" | xargs)  # Entferne Leerzeichen
    for i in "${!FLOAT_MEASUREMENTS_ARRAY[@]}"; do
      if [[ "${FLOAT_MEASUREMENTS_ARRAY[i]}" == "$keep" ]]; then
        unset 'FLOAT_MEASUREMENTS_ARRAY[i]'
      fi
    done
    for i in "${!STRING_MEASUREMENTS_ARRAY[@]}"; do
      if [[ "${STRING_MEASUREMENTS_ARRAY[i]}" == "$keep" ]]; then
        unset 'STRING_MEASUREMENTS_ARRAY[i]'
      fi
    done
    for i in "${!BOOLEAN_MEASUREMENTS_ARRAY[@]}"; do
      if [[ "${BOOLEAN_MEASUREMENTS_ARRAY[i]}" == "$keep" ]]; then
        unset 'BOOLEAN_MEASUREMENTS_ARRAY[i]'
      fi
    done
  done
  
  # Neu-Indizierung der Arrays
  FLOAT_MEASUREMENTS_ARRAY=("${FLOAT_MEASUREMENTS_ARRAY[@]}")
  STRING_MEASUREMENTS_ARRAY=("${STRING_MEASUREMENTS_ARRAY[@]}")
  BOOLEAN_MEASUREMENTS_ARRAY=("${BOOLEAN_MEASUREMENTS_ARRAY[@]}")
fi

# Anzeige der aktualisierten Gesamtzahl der Measurements
echo ""
echo "Zusammenfassung nach Filterung:"
echo "Float Measurements: ${#FLOAT_MEASUREMENTS_ARRAY[@]}"
echo "String Measurements: ${#STRING_MEASUREMENTS_ARRAY[@]}"
echo "Boolean Measurements: ${#BOOLEAN_MEASUREMENTS_ARRAY[@]}"

# Schritt 2: Measurements löschen nach Bestätigung
echo ""
echo "Möchtest du fortfahren und Measurements löschen? (ja/nein)"
read -p "Deine Auswahl: " CONTINUE

if [[ "$CONTINUE" == "ja" ]]; then
  # Alle Measurements in einem Array zusammenfassen
  ALL_MEASUREMENTS=("${FLOAT_MEASUREMENTS_ARRAY[@]}" "${STRING_MEASUREMENTS_ARRAY[@]}" "${BOOLEAN_MEASUREMENTS_ARRAY[@]}")
  TOTAL_MEASUREMENTS=${#ALL_MEASUREMENTS[@]}
  CURRENT_MEASUREMENT=0
  
  for MEASUREMENT in "${ALL_MEASUREMENTS[@]}"; do
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

echo "Skript abgeschlossen."
