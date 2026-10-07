import asyncio, re
from playwright.async_api import async_playwright

URL = "http://localhost:4200/?device={}"
CHROME = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"

async def status_of(page, name):
    return await page.locator(f'.row:has-text("{name}") select.status').input_value()

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path=CHROME)
        ca, cb = await b.new_context(viewport={"width":1000,"height":900}), await b.new_context(viewport={"width":1000,"height":900})
        A, B = await ca.new_page(), await cb.new_page()
        A.on("console", lambda m: m.type=="error" and print("A console:", m.text))
        await A.goto(URL.format("web-a")); await B.goto(URL.format("web-b"))
        await A.wait_for_selector('.pill[data-state="online"]', timeout=15000)
        print("1. A pill:", await A.locator(".pill").inner_text())

        await A.fill('input[name=name]', "Amina Wanjiru"); await A.fill('input[name=phone]', "0700111222")
        await A.click('button:has-text("Add record")')
        await A.wait_for_selector('.row:has-text("Amina") .tag.teal', timeout=10000)
        print("   A created + synced:", await A.locator('.row:has-text("Amina")').inner_text())
        await B.reload(); await asyncio.sleep(2.5); print("   B main:", (await B.locator("main").inner_text())[:300].replace("\n"," | "), "| pill:", await B.locator(".pill").inner_text())
        await B.wait_for_selector('.row:has-text("Amina")', timeout=15000)
        print("   B sees record, status:", await status_of(B, "Amina"))

        # 2. both offline, conflicting edits on same field
        await ca.set_offline(True); await cb.set_offline(True)
        await A.wait_for_selector('.pill[data-state="offline"]', timeout=5000)
        await A.select_option('.row:has-text("Amina") select.status', "INACTIVE")
        await asyncio.sleep(1.2)
        await B.select_option('.row:has-text("Amina") select.status', "SUSPENDED")
        await asyncio.sleep(0.5)
        print("2. A offline pill:", await A.locator(".pill").inner_text().__await__() if False else await A.locator(".pill").inner_text())
        await A.click('nav button:has-text("Pending")'); await asyncio.sleep(0.3)
        await A.screenshot(path="/home/claude/shots/a-pending-offline.png")
        print("   A pending:", (await A.locator(".banner").inner_text()).replace("\n"," | "))
        await A.click('nav button:has-text("Records")')

        # B (newer edit) reconnects first, then A (older edit)
        await cb.set_offline(False); await B.wait_for_selector('.row:has-text("Amina") .tag.teal', timeout=15000)
        await ca.set_offline(False)
        await A.wait_for_selector('.notice[data-kind="warn"]', timeout=15000)
        print("3. A conflict notice:", (await A.locator('.notice[data-kind="warn"]').inner_text()).replace("\n"," | "))
        await asyncio.sleep(0.8)
        print("   A local status after LWW:", await status_of(A, "Amina"))
        await A.screenshot(path="/home/claude/shots/a-conflict.png")
        await A.click('.notice button:has-text("Re-enter mine")')
        await asyncio.sleep(2)
        print("   A after re-enter:", await status_of(A, "Amina"))
        await B.click('nav button:has-text("Pending")'); await B.click('button:has-text("Sync now")'); await asyncio.sleep(1.5)
        await B.click('nav button:has-text("Records")')
        print("   B after sync:", await status_of(B, "Amina"))

        # 4. merge: different fields
        await ca.set_offline(True); await cb.set_offline(True); await asyncio.sleep(0.5)
        await A.click('.row:has-text("Amina") button:has-text("Edit")')
        inputs = A.locator('.row .edit input'); await inputs.nth(1).fill("0799000111")
        await A.click('.row button:has-text("Save")')
        await B.select_option('.row:has-text("Amina") select.status', "ACTIVE")
        await ca.set_offline(False); await A.wait_for_selector('.row:has-text("Amina") .tag.teal', timeout=15000)
        await cb.set_offline(False)
        await B.wait_for_selector('.notice:has-text("Changes merged")', timeout=15000)
        print("4. B merge notice:", (await B.locator('.notice:has-text("Changes merged")').inner_text()).replace("\n"," | "))
        await asyncio.sleep(1)
        await A.click('nav button:has-text("Pending")'); await A.click('button:has-text("Sync now")'); await asyncio.sleep(1.5)
        await A.click('nav button:has-text("Records")')
        print("   A row:", (await A.locator('.row:has-text("Amina")').inner_text()).replace("\n"," | "))
        print("   B row:", (await B.locator('.row:has-text("Amina")').inner_text()).replace("\n"," | "))

        # 5. duplicate replay
        await A.click('nav button:has-text("Pending")')
        await A.click('button:has-text("Replay last batch")')
        await A.wait_for_selector('.notice:has-text("Replay sent")', timeout=10000)
        print("5. replay:", (await A.locator('.notice:has-text("Replay sent")').inner_text()).replace("\n"," | "))

        # 6. history
        await A.click('nav button:has-text("Sync history")'); await asyncio.sleep(0.5)
        await A.screenshot(path="/home/claude/shots/a-history.png")
        print("6. stats:", (await A.locator(".stats").inner_text()).replace("\n"," "))
        await A.click('nav button:has-text("Records")'); await asyncio.sleep(0.3)
        await A.screenshot(path="/home/claude/shots/a-records.png")
        await b.close()

asyncio.run(main())
