#!/bin/sh

. "./../../CameraConfiguration.sh"

# Формирование параметров JSON запроса.
JSON=$(cat << DELIMITER
{
}
DELIMITER
)

echo "AtorageControl.GetStorageStates,()"
#echo "$JSON" > "./AtorageControl.GetStorageStates.json"
./../../ipcam_request.py -a $IP -s storagecontrol -c GetStorageStates -l "$JSON" | jq
