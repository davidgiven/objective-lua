require "olua"

local args = {...}
local oluafilename = args[2]

xpcall(
	function()
		olua.run(oluafilename, unpack(args, 3))
	end,
	function(e)
		if (type(e) == "table") and e.traceback then
			print(e)
			print(e:traceback())
		else
			print(e)
		end
	end
)
