#!/bin/sh

. "./../../CameraConfiguration.sh"

# Формирование параметров JSON запроса.
JSON=$(cat << DELIMITER
{
	"ConfigurationToken": "token"
}
DELIMITER
)

echo "ptz.GetConfigurationOptions()"
./../../ipcam_request.py -a $IP -s ptz -c GetConfigurationOptions -l "$JSON"
