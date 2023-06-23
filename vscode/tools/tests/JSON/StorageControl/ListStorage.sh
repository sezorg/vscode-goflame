#!/bin/sh

. "./../../CameraConfiguration.sh"

# Формирование параметров JSON запроса.
JSON=$(cat << DELIMITER
{
}
DELIMITER
)

echo "storagecontrol.ListStorage()"
#echo "$JSON" > "./Analytics.CreateAnalyticsModules_Test12.json"
./../../ipcam_request.py -a $IP -s storagecontrol -c ListStorage -l "$JSON"
