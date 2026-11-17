-- Itinéraire : moteur d'ordre (Lua pur, aucune API du jeu, testable hors ligne).
-- Chemin ouvert le plus court qui part du joueur (nœud 0) et passe par tous les nœuds 1..n,
-- avec des contraintes « a avant b » (les objectifs d'une quête avant son rendu).
-- C[i][j] = coût (secondes) pour aller de i à j, i dans 0..n, j dans 1..n.

local _, ns = ...
ns = ns or {}
local Solver = {}
ns.Solver = Solver

local EPS = 1e-6

function Solver.Cost(C, order)
	local total, prev = 0, 0
	for k = 1, #order do
		local v = order[k]
		total = total + C[prev][v]
		prev = v
	end
	return total
end

local function BuildPreds(n, before)
	local preds = {}
	for i = 1, n do
		preds[i] = {}
	end
	for _, pair in ipairs(before or {}) do
		local a, b = pair[1], pair[2]
		if a ~= b and preds[a] and preds[b] then
			preds[b][#preds[b] + 1] = a
		end
	end
	return preds
end

-- Contraintes : précédences (preds) et, si présente, la place dans le journal (preds.cap) :
-- prendre une quête occupe une place, la rendre en libère ; on ne dépasse jamais le maximum.
local function Feasible(order, preds, pos)
	for k = 1, #order do
		pos[order[k]] = k
	end
	for k = 1, #order do
		local list = preds[order[k]]
		for t = 1, #list do
			local p = pos[list[t]]
			if p and p > k then
				return false
			end
		end
	end
	local cap = preds.cap
	if cap then
		local count = cap.start
		for k = 1, #order do
			local d = cap.delta[order[k]] or 0
			count = count + d
			if d > 0 and count > cap.max then
				return false -- on ne peut pas prendre de quête journal plein (rendre, si, toujours)
			end
		end
	end
	return true
end
Solver.Feasible = Feasible

-- Construction : le plus proche voisin parmi les nœuds dont tous les prérequis sont déjà placés.
local function Greedy(n, C, preds, first)
	local order, used, cur = {}, {}, 0
	local cap = preds.cap
	local count = cap and cap.start or 0
	local function Ready(v)
		local list = preds[v]
		for t = 1, #list do
			if not used[list[t]] then
				return false
			end
		end
		local d = cap and cap.delta[v] or 0
		if d > 0 and count + d > cap.max then
			return false -- journal plein : rendre une quête d'abord
		end
		return true
	end
	if first and first >= 1 and first <= n and Ready(first) then
		order[1], used[first], cur = first, true, first
		count = count + (cap and cap.delta[first] or 0)
	end
	while #order < n do
		local best, bestCost
		for v = 1, n do
			if not used[v] and Ready(v) then
				local c = C[cur][v]
				if not best or c < bestCost - EPS then
					best, bestCost = v, c
				end
			end
		end
		if not best then
			-- Contraintes circulaires (ne devrait pas arriver) : on place le reste tel quel.
			for v = 1, n do
				if not used[v] then
					best = v
					break
				end
			end
		end
		order[#order + 1], used[best], cur = best, true, best
		count = count + (cap and cap.delta[best] or 0)
	end
	return order
end

local function Copy(t)
	local r = {}
	for i = 1, #t do
		r[i] = t[i]
	end
	return r
end

-- Déplace le segment order[i..i+L-1] juste après la position `after` (indices de l'ordre SANS le segment).
local function Relocated(order, i, L, after)
	local rest, seg = {}, {}
	for k = 1, #order do
		if k >= i and k < i + L then
			seg[#seg + 1] = order[k]
		else
			rest[#rest + 1] = order[k]
		end
	end
	local result = {}
	for k = 1, after do
		result[#result + 1] = rest[k]
	end
	for k = 1, #seg do
		result[#result + 1] = seg[k]
	end
	for k = after + 1, #rest do
		result[#result + 1] = rest[k]
	end
	return result
end

-- Or-opt : déplacer un segment de 1 à 3 nœuds ailleurs. Renvoie le nouvel ordre au premier gain trouvé.
local function TryOrOpt(order, C, preds, pos, start, tick)
	local m = #order
	for L = 1, 3 do
		for i = start, m - L + 1 do
			local a = i > 1 and order[i - 1] or 0
			local s1, sL = order[i], order[i + L - 1]
			local b = order[i + L]
			local gain = C[a][s1] + (b and (C[sL][b] - C[a][b]) or 0)
			-- Positions possibles dans l'ordre sans le segment : après `after` (0 = tout début).
			local restLen = m - L
			for after = start - 1, restLen do
				if after ~= i - 1 then
					-- x = nœud à la position `after` du reste, y = celui d'après.
					local x, y
					if after == 0 then
						x = 0
					else
						local idx = after < i and after or after + L
						x = order[idx]
					end
					local nextIdx = after + 1
					if nextIdx <= restLen then
						local idx = nextIdx < i and nextIdx or nextIdx + L
						y = order[idx]
					end
					local add = C[x][s1] + (y and (C[sL][y] - C[x][y]) or 0)
					if add - gain < -EPS then
						local candidate = Relocated(order, i, L, after)
						if Feasible(candidate, preds, pos) then
							return candidate
						end
					end
				end
				if tick then
					tick()
				end
			end
		end
	end
	return nil
end

-- 2-opt : inverser order[i..j] (coûts asymétriques : on recalcule la portion touchée).
local function TryTwoOpt(order, C, preds, pos, start, tick)
	local m = #order
	for i = start, m - 1 do
		local a = i > 1 and order[i - 1] or 0
		for j = i + 1, m do
			local b = order[j + 1]
			local old = C[a][order[i]] + (b and C[order[j]][b] or 0)
			local new = C[a][order[j]] + (b and C[order[i]][b] or 0)
			for k = i, j - 1 do
				old = old + C[order[k]][order[k + 1]]
				new = new + C[order[k + 1]][order[k]]
			end
			if new - old < -EPS then
				local candidate = Copy(order)
				for k = 0, j - i do
					candidate[i + k] = order[j - k]
				end
				if Feasible(candidate, preds, pos) then
					return candidate
				end
			end
			if tick then
				tick()
			end
		end
	end
	return nil
end

local function LocalSearch(order, C, preds, pos, start, tick, maxMoves)
	local moves = 0
	while moves < maxMoves do
		local better = TryOrOpt(order, C, preds, pos, start, tick) or TryTwoOpt(order, C, preds, pos, start, tick)
		if not better then
			break
		end
		order = better
		moves = moves + 1
	end
	return order, moves
end

-- Petit générateur déterministe : même entrée => même résultat (évite que l'ordre saute d'un calcul à l'autre).
local function Random(seed)
	local state = seed
	return function(m)
		state = (state * 1103515245 + 12345) % 2147483648
		return 1 + math.floor(state / 2147483648 * m)
	end
end

-- Perturbation pour sortir d'un minimum local : deux déplacements de segment au hasard, toujours faisables.
local function Perturb(order, preds, pos, start, rand)
	local m = #order
	local current = order
	for _ = 1, 2 do
		for _ = 1, 20 do
			if m - start + 1 < 3 then
				return current
			end
			local L = rand(3)
			local i = start - 1 + rand(m - start + 1)
			if i + L - 1 <= m then
				local after = start - 2 + rand(m - L - start + 2)
				if after ~= i - 1 and after >= start - 1 then
					local candidate = Relocated(current, i, L, after)
					if Feasible(candidate, preds, pos) then
						current = candidate
						break
					end
				end
			end
		end
	end
	return current
end

-- opts : first (nœud imposé en tête), tick (appelé régulièrement, pour céder la main),
-- maxMoves (par recherche locale), restarts (itérations de recherche locale itérée).
function Solver.Solve(n, C, before, opts)
	opts = opts or {}
	if n == 0 then
		return {}, 0, 0
	end
	local preds = BuildPreds(n, before)
	if opts.capacity and opts.capacity.max then
		preds.cap = opts.capacity
	end
	local order = Greedy(n, C, preds, opts.first)
	if preds.cap and not Feasible(order, preds, {}) then
		preds.cap = nil -- impossible à respecter (journal déjà trop plein) : on l'ignore plutôt que de bloquer
		order = Greedy(n, C, preds, opts.first)
	end
	local start = (opts.first and order[1] == opts.first) and 2 or 1
	local pos = {}
	local maxMoves = opts.maxMoves or 400
	local best, moves = LocalSearch(order, C, preds, pos, start, opts.tick, maxMoves)
	local bestCost = Solver.Cost(C, best)
	if maxMoves > 0 then
		local rand = Random(n * 7919 + 17)
		for _ = 1, opts.restarts or (n <= 50 and 40 or 10) do
			local candidate = LocalSearch(Perturb(best, preds, pos, start, rand), C, preds, pos, start, opts.tick, maxMoves)
			local cost = Solver.Cost(C, candidate)
			if cost < bestCost - EPS then
				best, bestCost = candidate, cost
			end
		end
	end
	return best, bestCost, moves
end

return Solver
