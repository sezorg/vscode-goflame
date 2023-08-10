#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"AuxiliaryCommand": "tt:IRLamp|Off"
}
DELIMITER
)
json_test device/SendAuxiliaryCommand
