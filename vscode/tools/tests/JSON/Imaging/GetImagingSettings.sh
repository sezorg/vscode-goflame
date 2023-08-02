#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"VideoSourceToken":"src"
}
DELIMITER
)
json_test imaging/GetImagingSettings
