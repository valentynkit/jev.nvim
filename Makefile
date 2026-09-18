NVIM ?= nvim
# Private ports: other projects in this monorepo run their own fakes.
PORT ?= 4372
BASE  = http://127.0.0.1:$(PORT)

.PHONY: test measure record dump demo clean

# Starts the fake, waits for the port, runs the suite, always kills the fake.
test:
	@lsof -ti tcp:$(PORT) >/dev/null 2>&1 && { echo "port $(PORT) is busy; set PORT=<free port>"; exit 1; }; \
	PORT=$(PORT) node tests/fake_jev.js & \
	FAKE=$$!; \
	trap "kill $$FAKE 2>/dev/null" EXIT INT TERM; \
	for _ in $$(seq 60); do curl -sf $(BASE)/_stats >/dev/null && break; sleep 0.1; done; \
	JEV_BASE_URL=$(BASE) $(NVIM) --headless -u tests/minimal.lua \
	  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal.lua', sequential=true}"

# Replays fixtures/recorded, so it costs nothing and needs no key.
measure:
	@JEV_UPSTREAM= node tools/proxy.js & \
	PROXY=$$!; \
	trap "kill $$PROXY 2>/dev/null" EXIT INT TERM; \
	for _ in $$(seq 60); do curl -sf http://127.0.0.1:4373/_stats >/dev/null && break; sleep 0.1; done; \
	JEV_BASE_URL=http://127.0.0.1:4373 $(NVIM) --headless -u tests/minimal.lua -l scripts/measure.lua

# One-time, costs money: records real answers into fixtures/recorded.
record:
	@./tools/record.sh

dump:
	@$(NVIM) --headless -u tests/minimal.lua -l scripts/dump_units.lua fixtures/corpus

# Renders both assets from one take: the GIF for the README, the square MP4 for X.
demo:
	@rm -rf .demo-frames demo.gif demo.mp4
	vhs demo.tape
	@[ -f demo.gif ] || ./scripts/gif.sh .demo-frames demo.gif
	@./scripts/mp4.sh .demo-frames demo.mp4
	@du -h demo.gif

clean:
	rm -rf .tests measure.json .demo-frames
