-- Flip the Nametag settings the way the UI would and report tag state after each.
return function(H)
    H.runLoader()
    H.advance(15)
    local out = { initial = H.tags() }
    H.controls["Show Nametags"].Callback(false) out.tagsOff = H.tags()
    H.controls["Show Nametags"].Callback(true) H.advance(2) out.tagsOn = H.tags()
    H.controls["Show Member Tags"].Callback(false) H.advance(2) out.noMembers = H.tags()
    H.controls["Show Member Tags"].Callback(true) H.advance(2)
    H.controls["Show My Own Tag"].Callback(false) H.advance(2) out.noSelf = H.tags()
    H.controls["Show My Own Tag"].Callback(true) H.advance(2)
    H.controls["Tag Distance"].Callback(220) H.advance(2) out.dist = H.tags()[1] and H.tags()[1].maxDistance
    H.controls["Preview Style:"].Callback("vip") H.advance(2) out.preview = H.tags()
    H.controls["Preview Style:"].Callback("Off") H.advance(2) out.previewOff = H.tags()
    -- unload: tags gone, leave sent
    H.window:Destroy()
    out.afterUnload = H.tags()
    H.result(out)
end
