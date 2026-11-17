local Solver = dofile(SOLVER_PATH)
math.randomseed(42)
local function rnd() return math.random() * 1000 end
local function instance(n, asym)
  local P = {}
  for i = 0, n do P[i] = {rnd(), rnd()} end
  local C = {}
  for i = 0, n do C[i] = {} for j = 1, n do
    local d = math.sqrt((P[i][1]-P[j][1])^2 + (P[i][2]-P[j][2])^2)
    C[i][j] = d * (asym and (1 + 0.2*math.random()) or 1)
  end end
  -- precedence: random quests: some nodes are "turnins" after 1-2 objective nodes
  local before = {}
  local k = 1
  while k + 2 <= n do
    local nobj = math.random(1, 2)
    if k + nobj > n then break end
    for t = 0, nobj - 1 do before[#before+1] = {k + t, k + nobj} end
    k = k + nobj + 1 + math.random(0, 1)
  end
  return C, before
end
local function permute(a, n, f)
  if n == 0 then f(a) return end
  for i = 1, n do a[i], a[n] = a[n], a[i]; permute(a, n - 1, f); a[i], a[n] = a[n], a[i] end
end
local worst, sumgap, cnt = 0, 0, 0
for trial = 1, 200 do
  local n = math.random(3, 8)
  local C, before = instance(n, trial % 2 == 0)
  local order, cost = Solver.Solve(n, C, before, {})
  -- feasibility
  local preds = {}
  for i = 1, n do preds[i] = {} end
  for _, p in ipairs(before) do table.insert(preds[p[2]], p[1]) end
  assert(#order == n, "length")
  local seen = {}
  for _, v in ipairs(order) do assert(not seen[v], "dup"); seen[v] = true end
  assert(Solver.Feasible(order, preds, {}), "infeasible result")
  -- brute force
  local a = {} for i = 1, n do a[i] = i end
  local best = math.huge
  permute(a, n, function(p)
    if Solver.Feasible(p, preds, {}) then
      local c = Solver.Cost(C, p); if c < best then best = c end
    end
  end)
  local gap = (cost - best) / best
  sumgap = sumgap + gap; cnt = cnt + 1
  if gap > worst then worst = gap end
end
print(string.format("small: avg gap %.2f%%, worst %.2f%%", 100*sumgap/cnt, 100*worst))
-- larger instances: compare with greedy-only (maxMoves=0) and timing
local t0 = os.clock()
local imp = 0
for trial = 1, 30 do
  local n = 40
  local C, before = instance(n, true)
  local _, g = Solver.Solve(n, C, before, {maxMoves = 0})
  local order, c = Solver.Solve(n, C, before, {})
  local preds = {} for i = 1, n do preds[i] = {} end
  for _, p in ipairs(before) do table.insert(preds[p[2]], p[1]) end
  assert(Solver.Feasible(order, preds, {}))
  imp = imp + (g - c) / g
end
print(string.format("n=40: improvement over greedy %.1f%%, %.3f s per solve", 100*imp/30, (os.clock()-t0)/30))
-- fixed first
local C, before = instance(10, false)
local order = Solver.Solve(10, C, {}, {first = 3})
print("first fixed ->", order[1])
