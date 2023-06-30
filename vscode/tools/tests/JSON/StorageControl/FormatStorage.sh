#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Token": "/dev/mmcblk0"
}
DELIMITER
)
json_test storagecontrol/FormatStorage
