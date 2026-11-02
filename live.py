"""Live CGDN1 readings in the terminal, like the menubar app.

  ~/qingping-flash/venv/bin/python ~/qingping-flash/live.py      (Mac; elsewhere python3 + paho-mqtt)

ESPHome firmware: streams the dashboard's /events (login from esphome-secrets.yaml).
Stock firmware: asks the monitor for realtime reports over the broker on this computer (documented
type 12) whenever it says hello, and prints each report. Stock only talks while it's connected, and
on battery it switches the CO2/PM sensors off (shown as "off").
"""
import json, os, re, socket, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MAC = os.environ.get("MAC", "CCB5D131D278")
HOST = os.environ.get("ESPHOME_HOST", "cgdn1.local")
BROKER = os.environ.get("BROKER", "localhost")


def secret(name, path=os.path.join(HERE, "esphome-secrets.yaml")):
    m = re.search(rf'^{name}:\s*"([^"]*)"', open(path).read(), re.M)
    return m.group(1) if m else ""


def line(values, off=()):
    fmt = lambda k, unit, nd=0: "off" if k in off else ("—" if values.get(k) is None else f"{values[k]:.{nd}f}{unit}")
    return (f"{time.strftime('%H:%M:%S')}  CO2 {fmt('co2', ' ppm'):>8}  PM2.5 {fmt('pm25', ''):>4}  "
            f"PM10 {fmt('pm10', ''):>4}  {fmt('temperature', '°C', 1):>7}  {fmt('humidity', '%', 1):>6}  "
            f"battery {fmt('battery', '%'):>4}")


def esphome_up():
    try:
        socket.create_connection((HOST, 80), timeout=2).close()
        return True
    except OSError:
        return False


def run_esphome():
    names = {"sensor/CO2": "co2", "sensor/PM2.5": "pm25", "sensor/PM10": "pm10",
             "sensor/Temperature": "temperature", "sensor/Humidity": "humidity", "sensor/Battery level": "battery"}
    mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
    mgr.add_password(None, f"http://{HOST}/", secret("web_username"), secret("web_password"))
    opener = urllib.request.build_opener(urllib.request.HTTPDigestAuthHandler(mgr), urllib.request.HTTPBasicAuthHandler(mgr))
    values, event, shown = {}, "", ""
    print(f"ESPHome at {HOST} — live (Ctrl-C to stop)")
    while True:
        try:
            with opener.open(f"http://{HOST}/events", timeout=90) as resp:
                for raw in resp:
                    text = raw.decode("utf-8", "replace").rstrip("\r\n")
                    if text.startswith("event:"):
                        event = text[6:].strip()
                    elif text.startswith("data:") and event == "state":
                        d = json.loads(text[5:])
                        if d.get("id") in names:
                            values[names[d["id"]]] = d.get("value")
                            out = line(values)
                            if out[10:] != shown[10:]:
                                print(out, flush=True)
                                shown = out
        except Exception as e:  # dropped stream, device rebooting, ...
            print(f"{time.strftime('%H:%M:%S')}  (connection lost: {e}; retrying in 5 s)", flush=True)
            time.sleep(5)


def run_stock():
    import paho.mqtt.client as mqtt
    up, down = f"qingping/{MAC}/up", f"qingping/{MAC}/down"
    ask = json.dumps({"type": "12", "up_itvl": "10", "duration": "3600"})
    last = {"ask": 0.0, "msg": time.time(), "warned": False}
    try:  # paho-mqtt 2.x needs the callback API version
        c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=f"cgdn1-live-{os.getpid()}")
    except AttributeError:
        c = mqtt.Client(client_id=f"cgdn1-live-{os.getpid()}")
    c.username_pw_set("qingping", open(os.path.join(HERE, "broker.pw")).read().strip())

    def on_message(cl, userdata, m):
        last["msg"], last["warned"] = time.time(), False
        try:
            d = json.loads(m.payload)
        except ValueError:
            return
        t = str(d.get("type"))
        if t in ("10", "13") and time.time() - last["ask"] > 50:  # it's online: (re)ask for realtime reports
            cl.publish(down, ask)
            last["ask"] = time.time()
        elif t == "12":
            s = d["sensorData"][0]
            vals = {k: v.get("value") for k, v in s.items() if isinstance(v, dict)}
            off = {k for k, v in s.items() if isinstance(v, dict) and v.get("status")}
            print(line(vals, off), flush=True)
        elif t == "24":
            print(f"{time.strftime('%H:%M:%S')}  (firmware download {d.get('percent')}%)", flush=True)

    c.on_message = on_message
    c.connect(BROKER, 1883, 30)
    c.subscribe(up)
    c.publish(down, ask)  # in case it's connected right now
    last["ask"] = time.time()
    print(f"Stock firmware via broker {BROKER} — live while the monitor is connected (Ctrl-C to stop)")
    print(f"{time.strftime('%H:%M:%S')}  (waiting for the monitor — if it's between connections, "
          "readings start when it reconnects, within ~10 min)", flush=True)
    last["msg"], last["warned"] = time.time(), True
    c.loop_start()
    while True:
        time.sleep(5)
        if time.time() - last["msg"] > 30 and not last["warned"]:
            print(f"{time.strftime('%H:%M:%S')}  (monitor went offline — it reconnects every ~10 min)", flush=True)
            last["warned"] = True


if __name__ == "__main__":
    try:
        run_esphome() if esphome_up() else run_stock()
    except KeyboardInterrupt:
        pass
