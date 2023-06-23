#!/bin/sh

. "./../../CameraConfiguration.sh"

JSON=$(cat << DELIMITER
{
	"ConfigurationToken":"vac",
	"AnalyticsModule":[
		{
			"Parameters":"<Parameters><SimpleItem Name=\"Sensitivity\" Value=\"90\"/><ElementItem Name=\"Layout\"><CellLayout Columns=\"32\" Rows=\"18\"/></ElementItem></Parameters>",
			"Name":"Test1",
			"Type":"cellmotiondetector"
		},
		{
			"Parameters":"<Parameters><SimpleItem Name=\"Sensitivity\" Value=\"90\"/><ElementItem Name=\"Layout\"><CellLayout Columns=\"32\" Rows=\"18\"/></ElementItem></Parameters>",
			"Name":"Test2",
			"Type":"cellmotiondetector"
		}
	]
}
DELIMITER
)

echo "Analytics.ModifyAnalyticsModules(Test1, Test2)"
echo "$JSON" > "./Analytics.ModifyAnalyticsModules_Test12.json"
./ipcam_request.py -a $IP -s analytics -c ModifyAnalyticsModules -l "$JSON" | jq
