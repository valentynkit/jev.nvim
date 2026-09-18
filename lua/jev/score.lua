-- Threshold sweep, Wilson interval, tune/hold split. Pure arithmetic, no I/O, so the
-- spec can check it without a corpus and without a server.
local M = {}

M.thresholds = { 0.5, 0.7, 0.75, 0.8, 0.9, 0.95 }

--- Split corpus files into a tuning half and a held-out half.
--- Alternates inside each language, so both halves span every language and no file
--- can land in both. Selection never sees the held-out half, which is the whole point:
--- reporting the tuned number would make the headline true by construction.
function M.split(files)
  local by_lang = {}
  for _, file in ipairs(files) do
    local lang = file:match("%.(%w+)$") or ""
    by_lang[lang] = by_lang[lang] or {}
    table.insert(by_lang[lang], file)
  end
  local langs = vim.tbl_keys(by_lang)
  table.sort(langs)
  local tune, hold = {}, {}
  for _, lang in ipairs(langs) do
    table.sort(by_lang[lang])
    for i, file in ipairs(by_lang[lang]) do
      table.insert(i % 2 == 1 and tune or hold, file)
    end
  end
  return tune, hold
end

--- Precision and recall over the hits at one threshold.
--- rows: { { p = number, label = 0|1 }, ... }
function M.at(rows, t)
  local hits, true_hits, positives = 0, 0, 0
  for _, row in ipairs(rows) do
    if row.label == 1 then
      positives = positives + 1
    end
    if row.p >= t then
      hits = hits + 1
      if row.label == 1 then
        true_hits = true_hits + 1
      end
    end
  end
  return {
    t = t,
    n = #rows,
    hits = hits,
    true_hits = true_hits,
    positives = positives,
    precision = hits > 0 and true_hits / hits or 0,
    recall = positives > 0 and true_hits / positives or 0,
  }
end

function M.sweep(rows, thresholds)
  return vim.tbl_map(function(t)
    return M.at(rows, t)
  end, thresholds or M.thresholds)
end

--- Lowest threshold clearing `target` precision, else the strictest one tried.
function M.choose(sweep, target)
  for _, row in ipairs(sweep) do
    if row.hits > 0 and row.precision >= target then
      return row.t
    end
  end
  return sweep[#sweep].t
end

--- Wilson score interval. The normal approximation runs past 1.0 at n near 70 with
--- p near 0.9, which would put an impossible number in the README.
function M.wilson(k, n, z)
  if n == 0 then
    return 0, 0
  end
  z = z or 1.96
  local p = k / n
  local zz = z * z
  local d = 1 + zz / n
  local centre = (p + zz / (2 * n)) / d
  local margin = z * math.sqrt(p * (1 - p) / n + zz / (4 * n * n)) / d
  return math.max(0, centre - margin), math.min(1, centre + margin)
end

return M
