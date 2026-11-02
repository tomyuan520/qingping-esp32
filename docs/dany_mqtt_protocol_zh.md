# 青萍空气检测仪 Lite MQTT 协议

- [青萍空气检测仪 Lite MQTT 协议](#青萍空气检测仪-lite-mqtt-协议)
  - [1. 协议规则说明](#1-协议规则说明)
  - [2. 设备主动上报传感器数据](#2-设备主动上报传感器数据)
    - [2.1 设备上报临时数据](#21-设备上报临时数据)
    - [2.2 设备上报历史数据](#22-设备上报历史数据)
  - [3. 服务器下发命令](#3-服务器下发命令)
    - [3.1 设置历史数据上报频率](#31-设置历史数据上报频率)
    - [3.2 设置临时数据上报频率](#32-设置临时数据上报频率)
    - [3.3 设置屏保和其他](#33-设置屏保和其他)
    - [3.4 设置读数偏移](#34-设置读数偏移)
    - [3.5 读取设备配置](#35-读取设备配置)
    - [3.6 修改设备的 MQTT 服务器](#36-修改设备的-mqtt-服务器)
  - [4. 蓝牙网关功能](#4-蓝牙网关功能)
    - [4.1 功能说明](#41-功能说明)
    - [4.2 设备请求蓝牙子设备](#42-设备请求蓝牙子设备)
    - [4.3 设备上报蓝牙子设备数据](#43-设备上报蓝牙子设备数据)
    - [4.4 蓝牙子设备数据解析](#44-蓝牙子设备数据解析)

## 1. 协议规则说明

- 通讯协议：MQTT

- 数据协议：JSON

- 部分命令需要应答，具体条目中有说明

## 2. 设备主动上报传感器数据

注意：1 代产品传感器数据正常上报，需服务器先完成与蓝牙子设备请求的应答（参考 4.2 节）。

### 2.1 设备上报临时数据

数据示例

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

|参数名称|参数值|是否必须|备注|
|---|---|---|---|
|type|string|R|消息类型，固定值 12|
|timestamp|int|R|设备上报数据的时间|
|version|string|R|固件版本|
|mac|string|R|设备  Wi\-Fi MAC|
|sensorData|\[\]obj|R|传感器数据|
|battery|obj|R|电量单位：%|
|battery\.value|float|R|传感器数值|
|temperature|obj|R|温度单位：°C|
|humidity|obj|R|湿度单位：%|
|pm10|obj|C|PM10 单位：μg/m³|
|pm25|obj|C|PM2\.5 单位：μg/m³|
|co2|obj|R|CO2 单位：ppm|
|timestamp|obj|R|数据的采集时间|

服务器应答：不需要应答



### 2.2 设备上报历史数据

数据示例：

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

参数说明：

|参数名称|参数值|是否必须|备注|
|---|---|---|---|
|type|string|R|消息类型，固定值 17|
|timestamp|int|R|设备上报数据的时间|
|version|string|R|固件版本|
|mac|string|R|设备 Wi\-Fi mac|
|sensorData|\[\]obj|R|传感器数据|
|battery|obj|R|电量单位：%|
|battery\.value|float|R|传感器数值|
|co2|obj|R|CO2 单位：ppm|
|humidity|obj|R|湿度单位：%|
|pm10|obj|C|PM10 单位：μg/m³|
|pm25|obj|C|PM2\.5 单位：μg/m³|
|temperature|obj|R|温度单位：°C|
|timestamp|obj|R|数据的采集时间|

服务器应答示例：

```JSON
{"ack_id":2617,"code":0,"desc":"","timestamp":1779089426,"type":"18"}
```

应答参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|ack\_id|int|R|消息 id，等于下发命令的 id|
|code|int|R|此命令的执行状态，0 表示成功|
|type|string|R|命令类型，固定值 18|
|timestamp|int|R|当前时间戳|

## 3. 服务器下发命令

### 3.1 设置历史数据上报频率

下发命令示例：

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

下发命令说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|id|int|R|消息 id，可以用时间戳代替|
|type|string|R|命令类型，固定值 17|
|timestamp|int|R|当前时间戳，10 位，秒级别|
|setting|obj|R|设置项|
|report\_interval|int|R|数据上报间隔，单位秒|
|collect\_interval|int|R|数据记录间隔，单位秒|

设备响应示例：

```JSON
{"ack_id":1779070226,"code":0,"type":"18"}
```

设备响应参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|ack\_id|int|R|消息 id，等于下发命令的 id|
|code|int|R|此命令的执行状态，0 表示成功|
|type|string|R|命令类型，固定值 18|

### 3.2 设置临时数据上报频率

命令示例：

```JSON
{
    "type": "12",
    "up_itvl": "60",
    "duration": "60"
}
```

参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 12|
|up\_itvl|string|R|上报间隔，单位秒，取值大于 2|
|duration|string|R|数据间隔，单位秒，取值在 60\-3600 之间|

设备应答：无应答

### 3.3 设置屏保和其他

命令示例：

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

参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 17|
|setting|obj|R|设置项|
|is\_12\_hour\_mode|int|C|时间 12 小时制，0 不是，1 是|
|screensaver\_type|int|C|屏保，枚举值，参考“应答参数说明”|
|timezone|int|C|时区|
|temperature\_unit|string|C|温度单位，C 表示摄氏度，F 表示华氏度|
|others|int\|string|C|参考应答参数说明|

应答示例：

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

应答参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 28|
|id|int|R|消息 id|
|setting|obj|R|设置项|
|auto\_slideing\_time|int|R|轮播展示传感器数据间隔，单位秒。取值 0\-60|
|collect\_interval|int|R|历史数据的采集间隔，单位秒。取值大于 10|
|report\_interval|int|R|历史数据的上报间隔，单位秒。取值大于 10|
|is\_12\_hour\_mode|int|R|时间 12 小时制，0 不是，1 是|
|need\_ack|int|R|历史数据是否应答，1 需要应答|
|night\_mode\_start\_time|int|R|夜间模式开始时间，为从 0 点 0 分开始的分钟数|
|night\_mode\_end\_time|int|R|夜间模式结束时间，为从 0 点 0 分开始的分钟数|
|page\_sequence|string|R|设备展示传感器的顺序|
|power\_off\_time|int|R|自动关机时间，单位分钟，0 表示不自动关机，取值 0\-60|
|display\_off\_time|int|R|屏幕自动关闭时间，单位秒，0 表示不关闭，取值 0\-300|
|screensaver\_type|int|R|屏保，请参考屏保枚举表。|
|temperature\_unit|string|R|温度单位，C 表示摄氏度，F 表示华氏度|
|timezone|int|R|时区，80 表示东八区，\-80 表示西八区|
|\*\_offset|int|C|传感器读数偏移，参考 4\.4 读数偏移设置|
|\*\_zoom|int|C|传感器读数百分比偏移，参考 4\.4 读数偏移设置|

屏保枚举:

|枚举|说明|英文说明|
|---|---|---|
|0|轮播所有读数|Rotating Readings|
|1|当前读数|Current Reading|
|2|时间 \+ 轮换读数 |Time \+ Rotating Readings|
|3|时间 \+ 当前读数 |Time \+ Current Reading|

### 3.4 设置读数偏移

下发命令示例：

```JSON
{"type":"17"，"setting":{"temperature_offset":100,"temperature_zoom":0}}
```

下发命令说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 17|
|setting|obj|R|设置项|
|temperature\_offset|int|C|加减，\*100。如增加 1\.01：设置 1\.01\*100|
|humidity\_offset|int|C|加减，\*10。如增加 \-1\.1：设置 \-1\.1\*10|
|humidity\_zoom|int|C|百分比，\*10|
|co2\_offset|int|C|加减，\*1|
|co2\_zoom|int|C|百分比，\*10|
|pm10\_offset|int|C|加减，\*1|
|pm10\_zoom|int|C|百分比，\*10|
|pm25\_offset|int|C|加减，\*1|
|pm25\_zoom|int|C|百分比，\*10|

设备响应示例：

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

设备响应参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 28|
|setting|obj|R|设备生效的配置项|
|temperature\_offset|int|C|\*100。上报 100，则表示偏移 1|
|temperature\_zoom|int|C|百分比|
|\*\_offset|int|C|参考下发命令|
|\*\_zoom|int|C|参考下发命令|

### 3.5 读取设备配置

命令示例：

```JSON
{"type": "28"}
```

参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 28|

设备应答示例：同 4.3 的应答一样



### 3.6 修改设备的 MQTT 服务器

命令示例：

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


参数说明：

|参数名称|参数类型|是否必须|备注|
|---|---|---|---|
|type|string|R|命令类型，固定值 16|
|timestamp|int|R|当前时间戳|
|desc|string|C|命令描述|
|host|obj|R|MQTT 配置项|
|host|string|R|MQTT 服务地址|
|port|string|R|MQTT 端口号|
|user|string|R|用户名|
|password|string|R|密码|
|client\_id|string|R|唯一客户端标识|
|sub\_topic|string|R|设备订阅数据主题（下行）|
|pub\_topic|string|R|设备发布数据主题（上行）|

设备应答数据：不需要应答

## 4. 蓝牙网关功能

### 4.1 功能说明

- 仅 1 代设备具有此功能，2 代不支持

- 仅支持青萍的蓝牙子设备

- 设备请求蓝牙子设备必须应答（2.2），其他请求可忽略

### 4.2 设备请求蓝牙子设备

上报数据示例:

```JSON
{"id":4834,"type":"10"}
```

上报参数说明：

|参数名称|参数值|是否必须|备注|
|---|---|---|---|
|type|string|R|消息类型，固定值 10|
|id|int|R|消息 id|

服务器应答示例：

```JSON
{"code":0,"desc":"","dev_list":["FFFFFFFFFFFF"],"timestamp":1779154969,"type":"11"}
```

应答参数说明：

|参数名称|参数值|是否必须|备注|
|---|---|---|---|
|type|string|R|消息类型，固定值 11|
|timestamp|int|R|当前时间戳，注意：设备用这个时间戳对时，必须正确的时间|
|code|int|R|状态码|
|dev\_list|\[\]string|R|蓝牙子设备列表，没有子设备返回固定值 FFFFFFFFFFFF|

### 4.3 设备上报蓝牙子设备数据

上报数据示例:

```JSON
{
    "type": "9",
    "id": 4973,
    "adv_data": "0201061416CDFD884FCB3E85342D58010406011102020164",
    "mac": "582D34853ECB",
    "rssi": "-50"
}
```

上报参数说明：

|参数名称|参数值|是否必须|备注|
|---|---|---|---|
|type|string|R|消息类型，固定值 9|
|id|int|R|消息 id|
|mac|string|R|蓝牙设备 MAC|
|adv\_data|string|R|蓝牙设备数据|
|rssi|srting|R|蓝牙信号|

应答数据说明：不需要应答

### 4.4 蓝牙子设备数据解析

- 子设备数据为 HEX 编码二进制字节流

- 1字节对应 2 个 HEX 字符，字节转整数均使用小端法

- 数据包由多个 LTV 数据包组成，这些包的组成形式为 LTV，只需要 key 为 0x16 的数据包就可以

- 举例：

|len|key|value|len|key|value|\.\.\.|
|---|---|---|---|---|---|---|
|1 字节|1 字节|len\-1 字节|1 字节|1 字节|len\-1 字节||

```Shell
广播数据 hex 编码：0201061416CDFD884FCB3E85342D58010410010B02020164
拆分成 2 个包：
020106
1416CDFD884FCB3E85342D58010410010B02020164
详解：
02 是长度，读取后面 2 字节，01 是 cmd，06 是 value，此包读取结束，忽略这个包
14 是长度，读取后面 20(0x14) 个字节，16 是 key，后面是内容，我们只处理这个包
```

- 0x16 数据包组成和解析如下所示

|cmd|uuid|frameControl|productId|mac|key|len|vlue|key|len|value|
|---|---|---|---|---|---|---|---|---|---|---|
|1 字节，固定 16|2 字节|1 字节|1 字节|6 字节|1字节|1字节|len 字节|1 字节|1 字节|len 字节|

- mac 6 字节需要先把字节反转，然后 hex 编码，如 CB3E85342D58，反转后 mac 为 582D34853ECB

- key 01 是温湿度，4 字节长度，0\-1 字节温度，2\-3 字节湿度

- key 02 是电量，1 字节

- key 04 是门窗传感器的开关，1 字节

- key 08 和 0D 是人体传感器事件，4 字节，0 字节是事件，1\-2 字节是光照强度，最后 1 字节预留

- key 09 是光照强度，4 字节，0\-2 字节是光照强度，后 2 字节预留

- 解析代码参考：github\.com/ClearGrass/sdk\-go/blob/main/encoding/ble\.go

