#!/bin/bash

# Variablen
BUCKET="DEIN_BUCKET"
ORG="DEINE_ORGANISATION"
TOKEN="DEIN_API_TOKEN"  # Setze dein InfluxDB API-Token hier ein
URL="http://localhost:8086"  # URL der InfluxDB
OLDER_THAN="30d"  # Zeitraum, älter als 30 Tage

# Schritt 1: Measurements abrufen, die seit 1 Monat nicht aktualisiert wurden
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
