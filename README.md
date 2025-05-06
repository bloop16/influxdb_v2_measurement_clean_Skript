# InfluxDB Measurement Cleanup Script

A Bash script to identify and (optionally) delete InfluxDB 2 measurements that have not been updated for a specified period.

## ⚠️ Warning

- **Explicitly built for the ioBroker Adapter Storage!**
- Use with caution! Deleting measurements is irreversible. BackUp first!
- Always double-check your configuration and selection before confirming deletions.

## 📜 Features

1. **Identify Inactive Measurements**
   - Finds measurements that have not been updated for a defined period (e.g., 30 days).

2. **Interactive Confirmation**
   - Lists these measurements and asks for confirmation before deletion.

3. **Selective Deletion**
   - Deletes only the selected measurements using an InfluxDB predicate.

## 🚀 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/bloop16/influxdb_v2_measurement_clean_Skript.git
   cd influxdb_v2_measurement_clean_Skript
   ```

2. **Create a configuration file:**
   Copy or create a file named `cleanup.config` in the project directory with the following content:
   ```bash
   BUCKET=your_bucket
   ORG=your_organization
   TOKEN=your_token
   OLDER_THAN=30d
   URL=http://localhost:8086
   ```

## 🛠️ Usage

1. **Make the script executable:**
   ```bash
   chmod +x cleanup.sh
   ```

2. **Run the script:**
   ```bash
   ./cleanup.sh
   ```

   - The script will display all loaded parameters and test the connection to your InfluxDB instance.
   - It will list all inactive measurements and offer options to delete all, delete selectively, or skip deletion.