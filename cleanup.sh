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

echo ""
echo "Folgende Parameter wurden gesetzt:"
echo "Bucket: $BUCKET"
echo "Organisation: $ORG"
echo "Zeitraum: Älter als $OLDER_THAN"
echo "URL: $URL"
echo ""

# Schritt 1: Measurements abrufen, die seit X Tagen nicht aktualisiert wurden
echo "Suche nach Measurements, die seit mehr als $OLDER_THAN nicht aktualisiert wurden..."
MEASUREMENTS=$(influx query '
from(bucket: "'"$BUCKET"'")
  |> range(start: -'"$OLDER_THAN"')
  |> group(columns: ["_measurement"])
  |> keep(columns: ["_measurement", "_time"])
  |> last()
' --org "$ORG" --token "$TOKEN" --raw | awk -F',' '{print $1}' | tail -n +2)

# Überprüfen, ob Measurements gefunden wurden
if [ -z "$MEASUREMENTS" ]; then
  echo "Keine Measurements gefunden, die älter als $OLDER_THAN sind."
  exit 0
fi

echo "Gefundene Measurements:"
echo "$MEASUREMENTS"

# Schritt 2: Jedes Measurement anzeigen und löschen nach Bestätigung
for MEASUREMENT in $MEASUREMENTS; do
  echo "Measurement: $MEASUREMENT"
  read -p "Soll dieses Measurement gelöscht werden? (ja/nein): " CONFIRMATION
  if [[ "$CONFIRMATION" == "ja" ]]; then
    # Schritt 3: Measurement löschen
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

echo "Skript abgeschlossen."
