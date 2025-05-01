# InfluxDB Measurement Cleanup Script

### WORK IN PROGRESS ###

Ein Bash-Skript, um in InfluxDB 2 Messungen (`Measurements`) zu bereinigen, die seit einem bestimmten Zeitraum nicht mehr aktualisiert wurden.

## 📜 Funktionen

1. **Identifikation inaktiver Measurements**:
   - Findet Measurements, die seit einem definierten Zeitraum (z. B. 30 Tage) nicht mehr aktualisiert wurden.
   
2. **Interaktive Bestätigung**:
   - Listet diese Measurements auf und fragt vor der Löschung nach einer Bestätigung.

3. **Gezielte Löschung**:
   - Löscht nur die ausgewählten Measurements mit Hilfe eines InfluxDB-Predicates.

## 🚀 Installation

1. **Repository klonen**:
   ```bash
   git clone https://github.com/bloop16/influxdb_v2_measurement_clean_Skript.git
   cd influxdb_v2_measurement_clean_Skript
