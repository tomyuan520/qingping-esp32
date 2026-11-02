import asyncio, sys, aioesphomeapi
KEY=sys.argv[1]
async def main():
    cli = aioesphomeapi.APIClient("cgdn1.local", 6053, None, noise_psk=KEY)
    await cli.connect(login=True)
    info = await cli.device_info()
    print(f"device: {info.name}  esphome {info.esphome_version}  model={info.model}  mac={info.mac_address}")
    ents, _ = await cli.list_entities_services()
    names = {e.key: (e.name or e.object_id) for group in [ents] for e in group}
    states = {}
    def cb(s):
        states[s.key] = getattr(s, "state", None)
    cli.subscribe_states(cb)
    await asyncio.sleep(5)
    print("live sensor states:")
    for k, v in sorted(states.items(), key=lambda kv: str(names.get(kv[0]))):
        n = names.get(k, k)
        if isinstance(v, float): v = round(v, 2)
        print(f"   {n}: {v}")
    await cli.disconnect()
asyncio.run(main())
