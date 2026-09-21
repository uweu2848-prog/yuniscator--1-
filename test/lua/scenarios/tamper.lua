return function(H)
    H.runLoader()
    H.advance(70)
    H.result({ tags = H.tags() })
end
