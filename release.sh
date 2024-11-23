./test.sh

echo "Continue?"
read

shards build
tar czf "/mount/host/28 Machines/28.03 Athens/athens/airflow-server/release.tar.gz" --transform 's,^,airflow-server/,' --exclude="airflow-browser" .
