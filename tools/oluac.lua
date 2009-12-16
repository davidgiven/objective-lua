require 'olua'

local args = {...}
local infile = args[2]

local intext = io.open(infile):read("*a")
local outtext = olua.translate(intext)
print(outtext)

