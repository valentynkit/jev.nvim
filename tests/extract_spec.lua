local extract = require("jev.extract")

local function names(units)
  return vim.tbl_map(function(u)
    return u.name
  end, units)
end

describe("extract", function()
  it("finds four functions in every corpus file", function()
    local files = vim.fn.glob("fixtures/corpus/*", false, true)
    assert.equals(12, #files)
    for _, path in ipairs(files) do
      local units, err = extract.from_file(path)
      assert.is_nil(err)
      assert.equals(4, #units, path .. " gave " .. #units .. " units")
    end
  end)

  it("covers every language the plugin claims", function()
    local seen = {}
    for _, path in ipairs(vim.fn.glob("fixtures/corpus/*", false, true)) do
      for _, u in ipairs(extract.from_file(path)) do
        seen[u.lang] = true
      end
    end
    for _, lang in ipairs({ "lua", "python", "rust", "go", "javascript", "typescript" }) do
      assert.is_true(seen[lang] == true, "no units for " .. lang)
    end
  end)

  it("names an arrow function from the variable it is bound to", function()
    local units = extract.from_file("fixtures/corpus/report.ts")
    assert.is_true(vim.tbl_contains(names(units), "reportQuery"))
  end)

  it("keeps the wrapper when a function matches twice", function()
    -- `export async function saveEvent` matches both function_declaration and
    -- export_statement; the wider match wins so the signature keeps `export`.
    local units = extract.from_file("fixtures/corpus/errors.ts")
    for _, u in ipairs(units) do
      if u.name == "saveEvent" then
        assert.is_truthy(u.signature:match("^export"))
      end
    end
  end)

  it("parses a tsx buffer", function()
    local src = table.concat({
      "export function Panel({ hits }: { hits: number }) {",
      "  return <div className=\"panel\">{hits}</div>;",
      "}",
    }, "\n")
    local units, err = extract.from_string(src, "tsx", "Panel.tsx")
    assert.is_nil(err)
    assert.same({ "Panel" }, names(units))
  end)

  it("reads the buffer, not the file, for unsaved edits", function()
    local path = "fixtures/corpus/errors.py"
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.bo[buf].filetype = "python"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "def only_in_the_buffer(x):",
      "    return x + 1",
    })

    local from_buf = extract.from_buf(buf)
    assert.same({ "only_in_the_buffer" }, names(from_buf))

    local from_disk = extract.from_file(path)
    assert.equals(4, #from_disk)
    assert.is_false(vim.tbl_contains(names(from_disk), "only_in_the_buffer"))

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("fails open on an unknown language", function()
    local units, err = extract.from_string("x = 1", nil, "thing.cobol")
    assert.same({}, units)
    assert.is_truthy(err:match("no language mapping"))
  end)

  it("truncates a body past the source cap", function()
    local body = string.rep("    value = value + 1\n", 400)
    local units = extract.from_string("def big(value):\n" .. body, "python", "big.py")
    assert.equals(1, #units)
    assert.is_true(units[1].truncated)
    assert.is_true(#units[1].source <= extract.max_source + 20)
  end)

  it("carries the docstring and the signature line", function()
    local units = extract.from_file("fixtures/corpus/errors.py")
    for _, u in ipairs(units) do
      if u.name == "save_event" then
        assert.equals("def save_event(conn, event):", u.signature)
        assert.equals(u.lnum, u.sig_lnum)
        assert.is_truthy(u.doc:match("Persist one event"))
      end
    end
  end)
end)
