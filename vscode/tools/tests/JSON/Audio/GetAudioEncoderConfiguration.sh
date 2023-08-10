#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"ConfigurationToken":"aec-1"
}
DELIMITER
)
json_test media/GetAudioEncoderConfiguration
