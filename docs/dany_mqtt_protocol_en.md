# Qingping Air Monitor Lite MQTT Protocol Document

- [Qingping Air Monitor Lite MQTT Protocol Document](#qingping-air-monitor-lite-mqtt-protocol-document)
  - [1. Protocol Rules Description](#1-protocol-rules-description)
  - [2. Device Reports Sensor Data](#2-device-reports-sensor-data)
    - [2.1 Device Reports Realtime Data](#21-device-reports-realtime-data)
    - [2.2 Device Reports Historical Data](#22-device-reports-historical-data)
  - [3. Server Issues Commands](#3-server-issues-commands)
    - [3.1 Set Historical Data Reporting Interval](#31-set-historical-data-reporting-interval)
    - [3.2 Set Realtime Data Reporting Interval](#32-set-realtime-data-reporting-interval)
    - [3.3 Screen Saver and Other Settings](#33-screen-saver-and-other-settings)
    - [3.4 Set Reading Offset](#34-set-reading-offset)
    - [3.5 Read Device Configuration](#35-read-device-configuration)
    - [3.6 Change Device MQTT Server](#36-change-device-mqtt-server)
  - [4. Bluetooth Gateway Function](#4-bluetooth-gateway-function)
    - [4.1 Function Description](#41-function-description)
    - [4.2 Device Requests Bluetooth Sub-Devices](#42-device-requests-bluetooth-sub-devices)
    - [4.3 Device Reports Bluetooth Sub-Device Data](#43-device-reports-bluetooth-sub-device-data)
    - [4.4 Sub-device Data Parsing](#44-sub-device-data-parsing)

## 1. Protocol Rules Description

- Communication Protocol: MQTT

- Data Protocol: JSON

- Some commands require acknowledgment, as specified in each entry\.

## 2. Device Reports Sensor Data

Note: Sensor data can only be reported normally after the server responds to the device's request regarding the Bluetooth sub-device  (refer to section 4.2).

### 2.1 Device Reports Realtime Data

Example Data Report:

```JSON
{
    "type": "12",
    "mac": "04CF8C28BF78",
    "sensorData": [{
        "battery": {"value": 100},
        "co2": {"value": 689},
        "humidity": {"value": 63.72},
        "pm10": {"value": 32},
        "pm25": {"value": 27},
        "temperature": {"value": 26.29},
        "timestamp": {"value": 1779159120}
    }],
    "version": "4.8.1"
    "timestamp": 1779159144
}
```

Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Message type, fixed value 12|
|timestamp|int|R|Time when device reports data|
|version|string|R|Firmware version|
|mac|string|R|Device Wi\-Fi MAC address|
|sensorData|\[\]obj|R|Sensor data|
|battery|obj|R|Battery level, unit: %|
|battery\.value|float|R|Sensor value|
|temperature|obj|R|Temperature, unit: °C|
|humidity|obj|R|Humidity, unit: %|
|pm10|obj|C|PM10, unit: μg/m³|
|pm25|obj|C|PM2\.5, unit: μg/m³|
|co2|obj|R|CO2, unit: ppm|
|timestamp|obj|R|Data collection time|

Server Response: No response required\.



### 2.2 Device Reports Historical Data

Example Data Report:

```JSON
{
    "id": 5171,
    "type": "17",
    "mac": "04CF8C28BF78",
    "need_ack": 1,
    "sensorData": [{
        "battery": {"value": 100},
        "co2": {"value": 689},
        "humidity": {"value": 63.72},
        "pm10": {"value": 32},
        "pm25": {"value": 27},
        "temperature": {"value": 26.29},
        "timestamp": {"value": 1779159120}
    }],
    "timestamp": 1779159144
}
```

Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Message type, fixed value 17|
|timestamp|int|R|Time when device reports data|
|version|string|R|Firmware version|
|mac|string|R|Device Wi\-Fi MAC address|
|sensorData|\[\]obj|R|Sensor data|
|battery|obj|R|Battery level, unit: %|
|battery\.value|float|R|Sensor value|
|co2|obj|R|CO2, unit: ppm|
|humidity|obj|R|Humidity, unit: %|
|pm10|obj|C|PM10, unit: μg/m³|
|pm25|obj|C|PM2\.5, unit: μg/m³|
|temperature|obj|R|Temperature, unit: °C|
|timestamp|obj|R|Data collection time|

Server Response Example:

```JSON
{"ack_id":2617,"code":0,"desc":"","timestamp":1779089426,"type":"18"}
```

Response Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|ack\_id|int|R|Message ID, equals the ID of the sent command|
|code|int|R|Execution status, 0 indicates success|
|type|string|R|Command type, fixed value 18|
|timestamp|int|R|Current timestamp|

## 3. Server Issues Commands

### 3.1 Set Historical Data Reporting Interval

Example Command:

```JSON
{
    "id": 1779077338,
    "type": "17",
    "timestamp": 1779077338,
    "setting": {
        "report_interval": 60,
        "collect_interval": 60
    }
}
```

Command Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|id|int|R|Message ID, can use timestamp|
|type|string|R|Command type, fixed value 17|
|timestamp|int|R|Current timestamp \(seconds, 10\-digit\)|
|setting|obj|R|Settings|
|report\_interval|int|R|Data reporting interval, in seconds|
|collect\_interval|int|R|Data collection interval, in seconds|

Device Response Example:

```JSON
{"ack_id":1779070226,"code":0,"type":"18"}
```

Device Response Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|ack\_id|int|R|Message ID, equals the sent command ID|
|code|int|R|Execution status, 0 indicates success|
|type|string|R|Command type, fixed value 18|



### 3.2 Set Realtime Data Reporting Interval

Example Command:

```JSON
{
    "type": "12",
    "up_itvl": "60",
    "duration": "60"
}
```

Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Command type, fixed value 12|
|up\_itvl|string|R|Report interval, in seconds, value \> 2|
|duration|string|R|Data interval, in seconds, value between 60\-3600|

Device Response: No response required\.



### 3.3 Screen Saver and Other Settings

Example Command:

```JSON
{
    "type": "17",
    "setting": {
        "is_12_hour_mode": 1,
        "screensaver_type": 0,
        "temperature_unit": "C",
        "timezone": 80
    }
}
```

Parameter Description:

|**type**|**string**|**Required**|**Command type, fixed value 17**|
|---|---|---|---|
|setting|obj|R|Settings|
|is\_12\_hour\_mode|int|C|12\-hour time format: 0 = no, 1 = yes|
|screensaver\_type|int|C|Screen saver type, see response parameter description for enum values|
|timezone|int|C|Timezone|
|temperature\_unit|string|C|Temperature unit: C = Celsius, F = Fahrenheit|
|others|int/string|C|See response parameter description|
|others|int\|string|C|参考应答参数说明|

Device Response Example:

```JSON
{
    "type": "28",
    "id": 4817,
    "setting": {
        "auto_slideing_time": 120,
        "co2_asc": 1,
        "co2_led_th": "1000,2000,3000",
        "co2_offset": -3,
        "co2_zoom": 0,
        "collect_interval": 60,
        "display_off_time": 120,
        "humi_led_th": "2000,4000,6000",
        "humidity_offset": 0,
        "humidity_zoom": 20,
        "is_12_hour_mode": 1,
        "need_ack": 1,
        "night_mode_end_time": 0,
        "night_mode_start_time": 0,
        "page_sequence": "pm25,pm10,co2,temp,pm25",
        "pm10_led_th": "50,150,250,350,450",
        "pm10_offset": 0,
        "pm10_zoom": 50,
        "pm25_calib_mode": 0,
        "pm25_led_th": "35,75,115,150,250",
        "pm25_offset": 0,
        "pm25_standard": 0,
        "pm25_zoom": -40,
        "pm_sampling_interval": 1,
        "power_off_time": 30,
        "report_interval": 60,
        "screensaver_type": 1,
        "temp_led_th": "2300,2650,2800",
        "temperature_offset": 0,
        "temperature_unit": "C",
        "temperature_zoom": 0,
        "timezone": 80
    }
}
```

Response Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Command type, fixed value 28|
|id|int|R|Message ID|
|setting|obj|R|Settings|
|auto\_slideing\_time|int|R|Interval for rotating sensor data display, in seconds\. Range 0\-60\.|
|collect\_interval|int|R|Historical data collection interval, in seconds\. Value \> 10\.|
|report\_interval|int|R|Historical data reporting interval, in seconds\. Value \> 10\.|
|is\_12\_hour\_mode|int|R|12\-hour time format: 0 = no, 1 = yes|
|need\_ack|int|R|Whether historical data requires acknowledgment: 1 = required|
|night\_mode\_start\_time|int|R|Night mode start time, minutes from 00:00|
|night\_mode\_end\_time|int|R|Night mode end time, minutes from 00:00|
|page\_sequence|string|R|Order of sensors displayed on device|
|power\_off\_time|int|R|Auto power\-off time, in minutes\. 0 = never off\. Range 0\-60\.|
|display\_off\_time|int|R|Screen auto\-off time, in seconds\. 0 = never off\. Range 0\-300\.|
|screensaver\_type|int|R|Screen saver type, see enumer table below|
|temperature\_unit|string|R|Temperature unit: C = Celsius, F = Fahrenheit|
|timezone|int|R|Timezone: 80 = UTC\+8, \-80 = UTC\-8|
|\*\_offset|int|C|Sensor reading offset, see section 4\.4|
|\*\_zoom|int|C|Sensor reading percentage offset, see section 4\.4|

Screen Saver Enumeration:

|**Enum**|**Description**|**English Description**|
|---|---|---|
|0|轮播所有读数|Rotating Readings|
|1|当前读数|Current Reading|
|2|时间 \+ 轮换读数|Time \+ Rotating Readings|
|3|时间 \+ 当前读数|Time \+ Current Reading|



### 3.4 Set Reading Offset

Example Command:

```JSON
{"type":"17"，"setting":{"temperature_offset":100,"temperature_zoom":0}}
```

Command Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Command type, fixed value 17|
|setting|obj|R|Settings|
|temperature\_offset|int|C|Add/subtract, \*100\. e\.g\., \+1\.01 = 101|
|humidity\_offset|int|C|Add/subtract, \*10\. e\.g\., \-1\.1 = \-11|
|humidity\_zoom|int|C|Percentage, \*10|
|co2\_offset|int|C|Add/subtract, \*1|
|co2\_zoom|int|C|Percentage, \*10|
|pm10\_offset|int|C|Add/subtract, \*1|
|pm10\_zoom|int|C|Percentage, \*10|
|pm25\_offset|int|C|Add/subtract, \*1|
|pm25\_zoom|int|C|Percentage, \*10|

Device Response Example:

```JSON
{
    "type":"28"
    "setting":{
        "co2_offset":0,
        "co2_zoom":10,
        "humidity_offset":0,
        "humidity_zoom":0,
        "pm10_offset":0,
        "pm10_zoom":0,
        "pm25_offset":0,
        "pm25_zoom":0,
        "temperature_offset":100,
        "temperature_zoom":0
    }
}
```

Device Response Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Command type, fixed value 28|
|setting|obj|R|Settings active on device|
|temperature\_offset|int|C|\*100\. e\.g\., 100 means offset 1|
|temperature\_zoom|int|C|Percentage|
|\*\_offset|int|C|See command description|
|\*\_zoom|int|C|See command description|



### 3.5 Read Device Configuration

Example Command:

```JSON
{"type": "28"}
```

Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Command type, fixed value 28|

Device Response: Same as the response in section 4\.3\.



### 3.6 Change Device MQTT Server

Example Command:

```JSON
{
    "type": "16",
    "desc": "change env",
    "timestamp": 1779176643,   
    "host": { 
        "host": "127.0.0.1",                         
        "port": "1886",
        "user": "root",
        "password":"*******",
        "client_id":"sensor_582D340005EE",
        "sub_topic": "sensor/582D340005EE/down",
        "pub_topic": "sensor/582D340005EE/up",
    }
}
```



Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Command type, fixed value 16|
|timestamp|int|R|Current timestamp|
|desc|string|C|Command description|
|host|obj|R|MQTT configuration|
|host|string|R|MQTT server address|
|port|string|R|MQTT port|
|user|string|R|Username|
|password|string|R|Password|
|client\_id|string|R|Unique client identifier|
|sub\_topic|string|R|Device subscription topic|
|pub\_topic|string|R|Device publishing topic|

Device Response: No response required\.



## 4. Bluetooth Gateway Function

### 4.1 Function Description

- Only 1st generation devices have this function\. 2nd generation does not support it\.

- Only supports Qingping Bluetooth sub\-devices\.

- Device requests for Bluetooth sub\-devices must be answered \(2\.2\); others can be ignored\.



### 4.2 Device Requests Bluetooth Sub-Devices

Example Data Report:

```JSON
{"id":4834,"type":"10"}
```

Report Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Message type, fixed value 10|
|id|int|R|Message ID|

Server Response Example:

```JSON
{"code":0,"desc":"","dev_list":["FFFFFFFFFFFF"],"timestamp":1779154969,"type":"11"}
```

Response Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Message type, fixed value 11|
|timestamp|int|R|Current timestamp\. Note: Device uses this for time sync; must be correct\.|
|code|int|R|Status code|
|dev\_list|\[\]string|R|List of Bluetooth sub\-devices\. If none, returns fixed value `FFFFFFFFFFFF`\.|



### 4.3 Device Reports Bluetooth Sub-Device Data

Example Data Report:

```JSON
{
    "type": "9",
    "id": 4973,
    "adv_data": "0201061416CDFD884FCB3E85342D58010406011102020164",
    "mac": "582D34853ECB",
    "rssi": "-50"
}
```

Report Parameter Description:

|**Parameter**|**Type**|**Required**|**Remarks**|
|---|---|---|---|
|type|string|R|Message type, fixed value 9|
|id|int|R|Message ID|
|mac|string|R|Bluetooth device MAC address|
|adv\_data|string|R|Bluetooth device data \(parsing not provided\)|
|rssi|string|R|Bluetooth signal strength|

Server Response: No response required\.



### 4.4 Sub-device Data Parsing

Sub\-device data is in HEX\-encoded binary byte stream\.

- 1 byte corresponds to 2 HEX characters\. Byte\-to\-integer conversion uses little\-endian\.

- The data packet consists of multiple LTV \(Length\-Type\-Value\) packets\. Only the packet with key `0x16` needs to be processed\.

Example:

|len|key|value|len|key|value|\.\.\.|
|---|---|---|---|---|---|---|
|1 byte|1 byte|len\-1 bytes|1 byte|1 byte|len\-1 bytes||

```Shell
Broadcast data hex: 0201061416CDFD884FCB3E85342D58010410010B02020164

Split into 2 packets:
020106
1416CDFD884FCB3E85342D58010410010B02020164

Explanation:
02 is the length, read next 2 bytes. 01 is cmd, 06 is value. Packet ends, ignore this packet.
14 is the length, read next 20 (0x14) bytes. 16 is the key, followed by content. Process only this packet.
```

Structure of the `0x16` data packet: 

|cmd|uuid|frameControl|productId|mac|key|len|vlue|key|len|value|
|---|---|---|---|---|---|---|---|---|---|---|
|1 byte \(fixed 16\)|2 bytes|1 byte|1 byte|6 bytes|1 byte|1 byte|len bytes|1 byte|1 byte|len bytes|

- The 6\-byte MAC needs to be byte\-reversed and then HEX encoded\. For example, `CB3E85342D58` reversed becomes `582D34853ECB`\.

- Key `01`: Temperature and humidity, 4\-byte length\. Bytes 0\-1: temperature, bytes 2\-3: humidity\.

- Key `02`: Battery level, 1 byte\.

- Key `04`: Door/window sensor state, 1 byte\.

- Key `08` and `0D`: Motion sensor event, 4 bytes\. Byte 0: event, bytes 1\-2: light intensity, last 1 byte reserved\.

- Key `09`: Light intensity, 4 bytes\. Bytes 0\-2: light intensity, last 2 bytes reserved\.

Parsing code reference: github\.com/ClearGrass/sdk\-go/blob/main/encoding/ble\.go \.

