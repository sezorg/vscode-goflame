#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"ConfigurationToken":"asc-1"
}
DELIMITER
)
json_test media/GetAudioSourceConfiguration
