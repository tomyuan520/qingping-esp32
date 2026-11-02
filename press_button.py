import asyncio, sys, aioesphomeapi
KEY, NAME = sys.argv[1], sys.argv[2]
async def main():
    cli = aioesphomeapi.APIClient("cgdn1.local", 6053, None, noise_psk=KEY)
    await cli.connect(login=True)
    ents, _ = await cli.list_entities_services()
    btn = next(e for e in ents if isinstance(e, aioesphomeapi.ButtonInfo) and e.name == NAME)
    cli.button_command(btn.key)
    await asyncio.sleep(1)
    print(f"pressed '{NAME}'")
    await cli.disconnect()
asyncio.run(main())
