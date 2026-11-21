#!/usr/bin/env bash
# Build the warehouse from scratch and export every result to output/.
# Connection settings come from the standard libpq variables
# (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE).
set -euo pipefail
cd "$(dirname "$0")"

export PGDATABASE="${PGDATABASE:-retail}"
PSQL=(psql --no-psqlrc --quiet -v ON_ERROR_STOP=1)

[ -f data/raw/order_lines.csv ] || python data/generate_data.py --out data/raw --seed 42

mkdir -p output
for script in sql/0[1-6]_*.sql; do
    echo ">> $script"
    "${PSQL[@]}" -f "$script"
done

echo ">> sql/07_performance.sql"
"${PSQL[@]}" -f sql/07_performance.sql > output/query_plans.txt

export_csv() {  # export_csv <name> <query>
    "${PSQL[@]}" -c "\\copy ($2) TO 'output/$1.csv' WITH (FORMAT csv, HEADER true)"
    echo "   output/$1.csv"
}

echo ">> exporting marts and analyses"
export_csv data_quality_report "SELECT * FROM staging.dq_report ORDER BY table_name, failing_rows DESC, check_name"
export_csv monthly_revenue     "SELECT * FROM marts.monthly_revenue ORDER BY order_month"
export_csv cohort_retention    "SELECT * FROM marts.cohort_retention ORDER BY cohort_month, months_since_first"
for file in analysis/*.sql; do
    name="$(basename "$file" .sql)"
    query="$(sed 's/--.*$//' "$file" | tr '\n' ' ' | sed 's/;[[:space:]]*$//')"
    export_csv "$name" "$query"
done

python report/make_charts.py
echo "done"
