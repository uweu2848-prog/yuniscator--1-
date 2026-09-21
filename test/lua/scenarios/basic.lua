-- Run loader, let a few syncs/heartbeats happen, report what got drawn.
return function(H)
    H.runLoader()
    H.advance(25)
    H.result({ tags = H.tags(), controls = (function() local n = {} for k in pairs(H.controls) do n[#n + 1] = k end table.sort(n) return n end)() })
end
