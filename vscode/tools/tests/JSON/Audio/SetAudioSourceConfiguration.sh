#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(
	cat <<DELIMITER
{
	"Configuration": {
		"Name": "name",
		"UseCount": 2,
		"Token": "asc-1",
		"SourceToken": "asrc"
	}
}
DELIMITER
)
json_test media/SetAudioSourceConfiguration
