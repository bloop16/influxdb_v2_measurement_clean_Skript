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

# Schritt 1: Measurements mit verschiedenen Datentypen getrennt abrufen
log_status "Suche nach Measurements mit float-Werten..."
FLOAT_MEASUREMENTS=$(influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "float"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)
check_error "Abfrage für float-Werte fehlgeschlagen."

log_status "Suche nach Measurements mit string-Werten..."
STRING_MEASUREMENTS=$(influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "string"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)
check_error "Abfrage für string-Werte fehlgeschlagen."

log_status "Suche nach Measurements mit boolean-Werten..."
BOOLEAN_MEASUREMENTS=$(influx query '
import "types"
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> filter(fn: (r) => types.isType(v: r._value, type: "bool"))
  |> group(columns: ["_measurement"])
  |> distinct(column: "_measurement")
' --org "$ORG" --token "$TOKEN" --raw 2> /dev/null)
check_error "Abfrage für boolean-Werte fehlgeschlagen."

# Anzeige der Ergebnisse
echo ""
echo "Gefundene Measurements (float):"
echo "$FLOAT_MEASUREMENTS"

echo ""
echo "Gefundene Measurements (string):"
echo "$STRING_MEASUREMENTS"

echo ""
echo "Gefundene Measurements (boolean):"
echo "$BOOLEAN_MEASUREMENTS"

# Schritt 2: Measurements löschen nach Bestätigung
echo ""
echo "Möchtest du fortfahren und Measurements löschen? (ja/nein)"
read -p "Deine Auswahl: " CONTINUE

if [[ "$CONTINUE" == "ja" ]]; then
  for MEASUREMENT in $FLOAT_MEASUREMENTS $STRING_MEASUREMENTS $BOOLEAN_MEASUREMENTS; do
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
