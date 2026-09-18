-- research/01 section 6's jaggedness list, five cases. Four are numbers recorded once by
-- scripts/failure_modes.lua and committed, so a change in the model or in the question
-- wording shows up here as a failing assertion rather than as a surprise in the field.
-- The fifth is behavioural and runs live against the fake.
local batch = require("jev.batch")
local extract = require("jev.extract")
local H = dofile("tests/helpers.lua")

local probes = vim.json.decode(table.concat(vim.fn.readfile("fixtures/failure_modes.json"), "\n"))
local THRESHOLD = 0.75

local function probability(name)
  local p = probes[name]
  assert(type(p) == "number", "no recorded probability for " .. name)
  assert(p >= 0 and p <= 1, name .. " is not a probability: " .. tostring(p))
  return p
end

describe("known failure modes", function()
  it("does not move much when the state is padded with unrelated prose", function()
    probability("base")
    probability("padded")
    assert.is_true(
      probes.padded_delta < 0.15,
      ("padding moved the answer by %.3f"):format(probes.padded_delta)
    )
  end)

  it("does not flip on an instruction injected into a docstring", function()
    local clean, injected = probability("clean"), probability("injected")
    assert.is_true(clean < THRESHOLD, "the clean unit already reads as a hit")
    assert.is_true(
      injected < THRESHOLD,
      ("injected text pushed %.2f to %.2f"):format(clean, injected)
    )
  end)

  it("owns a number for question and criteria describing different things", function()
    -- No correct answer to assert. The point is that a mismatched pair is a committed
    -- number rather than a surprise, since the two ship separately.
    probability("contradictory")
  end)

  it("owns numbers for negation and for non-English identifiers", function()
    -- Both are known-weak, stated in Known limits. Recorded, not asserted for accuracy.
    probability("negated")
    probability("foreign")
  end)

  it("terminates on a unit nothing can shrink small enough", function()
    H.reset()
    H.control({ max_body = 400 })
    local huge = "def enormous(value):\n" .. string.rep("    value = value + 1\n", 12000)
    local units = extract.from_string(huge, "python", "huge.py")
    local done, result = false, nil
    batch.run(units, { question = "swallows an exception" }, {
      on_done = function(stats)
        result = stats
        done = true
      end,
    })
    H.wait(function()
      return done
    end, 20000)
    assert.equals(1, result.failed)
    H.reset()
  end)

  it("says which source the recorded numbers came from", function()
    assert.is_true(probes.source == "recorded" or probes.source == "fake")
  end)
end)
