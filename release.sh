./refresh.sh
./test.sh

echo "Continue?"
read

shards build
tar czf "/home/jkoff/Desktop/mount/host/20-29 Creations/28 Machines/28.03 Athens/athens/airflow-server/release.tar.gz" --transform 's,^,airflow-server/,' .
