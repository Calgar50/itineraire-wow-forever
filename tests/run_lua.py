import sys, lupa.lua51 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
g = rt.globals()
for kv in sys.argv[2:]:
    k, v = kv.split("=", 1); g[k] = v
rt.execute(open(sys.argv[1], encoding="utf-8").read())
