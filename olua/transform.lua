module(..., package.seeall)

local function mangle(s)
	return s:gsub(":", "_")
end

local function stringify(s)
	if not s:find('"') then
		return '"'..s..'"'
	elseif not s:find("'") then
		return "'"..s.."'"
	end
	
	local i = 0
	while true do
		local e = string.rep('=', i)
		if not s:find("%["..e.."%]") then
			return "["..e.."["..s.."]"..e.."]"
		end
		i = i + 1
	end
end

local function leaf(t)
	return {type="leaf", value=t}
end

local function identifierleaf(s)
	return leaf({type="identifier", text=s})
end

local function stringleaf(s)
	return leaf({type="string", text=stringify(s)})
end

function methodcall(ast)
	local object = ast.object
	local selector = ast.selector
	local args = ast.args
	
	selector = {type="leaf", value=mangle(selector)}
	
	if object then
		-- Normal method call.
		return 
			{
				type="functioncall",
				value=
				{
					type="binop",
					operator=":",
					left=object,
					right=selector
				},
				args={
					type="list",
					unpack(args)
				}
			}
	else
		-- super call.
		return 
			{
				type="functioncall",
				value=
				{
					type="binop",
					operator=".",
					left=identifierleaf("__olua_super"),
					right=selector
				},
				args={
					type="list",
					identifierleaf("self"),
					unpack(args)
				}
			}
	end
end

local function methoddefinition(ast)
	local args = {}
	if ast.args then
		for _, v in ipairs(ast.args) do
			args[#args+1] = v
		end
	end
	if ast.extraargs then
		for _, v in ipairs(ast.extraargs) do
			args[#args+1] = v
		end
	end
	
	return
		{
			type="assignment",
			left=
			{
				type="binop",
				operator=".",
				left=identifierleaf("__olua_template"),
				right=identifierleaf(mangle(ast.selector))
			},
			right=
			{
				type="functiondef",
				args=
				{
					type="list",
					identifierleaf("self"),
					unpack(args)
				},
				chunk=ast.chunk
			}
		}
end

function implementation(ast)
	local category = identifierleaf("nil")
	if ast.category then
		category = stringleaf(ast.category.text)
	end
	
	local newast = {
		type="doend",
		chunk=
		{
			type="chunk"
		}
	}
	
	-- Emit code to create the subclass, if necessary.
	
	if ast.superclass then
		newast.chunk[#newast.chunk+1] = {
			type="assignment",
			left=leaf(ast.class),
			right=
			{
				type="functioncall",
				value=
				{
					type="binop",
					operator=":",
					left=ast.superclass,
					right=identifierleaf("createSubclassNamed_")
				},
				args=
				{
					type="list",
					stringleaf(ast.class.text),
				}
			}
		}
	end

	-- Collect the contents of the implementation chunk into local definitions,
	-- object methods and class methods.
	
	local locals = {}
	local objectmethods = {}
	local classmethods = {}
	for _, k in ipairs(ast) do
		if (k.type == "olua_methoddefinition") then
			if k.classmethod then
				classmethods[#classmethods + 1] = k
			else
				objectmethods[#objectmethods + 1] = k
			end
		else
			locals[#locals + 1] = k
		end
	end

	-- Check that we have *either* class methods *or* object methods.
	
	if (#classmethods > 0) and (#objectmethods > 0) then
		olua.parser.error("you cannot have both class methods and object "..
			"methods in the same category.")
	end

	local addclassmethod
	local methods
	if (#objectmethods > 0) then
		addclassmethod = "addObjectMethodCategory_withTemplate_"
		methods = objectmethods
	elseif (#classmethods > 0) then
		addclassmethod = "addClassMethodCategory_withTemplate_"
		methods = classmethods
	else
		return newast
	end
	
	-- Emit category template.
			
	local chunk = {type="chunk"}
	for _, k in ipairs(locals) do
		chunk[#chunk+1] = k
	end
	for _, k in ipairs(methods) do
		chunk[#chunk+1] = methoddefinition(k)
	end
	
	newast.chunk[#newast.chunk+1] = {
		type="functioncall",
		value=
		{
			type="binop",
			operator=":",
			left=leaf(ast.class),
			right=identifierleaf(addclassmethod)
		},
		args=
		{
			type="list",
			category,
			{
				type="functiondef",
				args=
				{
					type="list",
					identifierleaf("__olua_template"),
					identifierleaf("__olua_super"),
					identifierleaf("self")
				},
				chunk = chunk
			}
		}
	}
	
	return newast
end

function throw(ast)
	return
		{
			type = "functioncall",
			value = identifierleaf("error"),
			args =
			{
				type="list",
				ast.exception,
				identifierleaf(0)
			}
		}
end

-- Objective Lua's try-catch-finally support is a bit cumbersome.
--
-- @try fnord() @catch(e) catch() @finally finally() @end
--
-- ...becomes:
--
-- do
--   local __olua_result = {pcall(function()
--     fnord()
--     return "__olua_success"
--   end)}
--   if not __olua_tryresult[1] then
--     local e = __olua_result[2]
--     __olua_result = {function()
--       catch()
--       return "__olua_success"
--     end}
--   end
--   do
--     finally()
--   end
--   if __olua_tryresult[1] and (__olua_tryresult[2] ~= "__olua_success") then
--     return unpack(__olua_tryresult, 2)
--   end
-- end
           
function trycatchfinally(ast)
	local result = identifierleaf("__olua_result")
	local success = stringleaf("__olua_success")
	
	local chunk =
		{
			type="chunk",
			-- Try block.
			{
				type="local",
				value=
				{
					type="assignment",
					left=result,
					right=
					{
						type="tableliteral",
						{
							value=
							{
								type="functioncall",
								value=identifierleaf("pcall"),
								args=
								{
									type="list",
									{
										type="functiondef",
										args={type="list"},
										chunk=
										{
											type="chunk",
											{
												type="doend",
												chunk=ast.try
											},
											{
												type="return",
												value=success
											}
										},
										
									}
								}
							}
						}
					}
				},
			},
			
			-- Catch block.
			
			{
				type="ifelseend",
				{
					condition=
					{
						type="unop",
						operator="not",
						value=
						{
							type="deref",
							left=result,
							right=identifierleaf("1")
						}
					},
					chunk=
					{
						type="chunk",
						{
							type="local",
							value=
							{
								type="assignment",
								left=ast.catchvar,
								right=
								{
									type="deref",
									left=result,
									right=identifierleaf("2")
								}
							}
						},
						{
							type="assignment",
							left=result,
							right=
							{
								type="tableliteral",
								{
									value=identifierleaf("true")
								},
								{
									value=
									{
										type="functioncall",
										value=
										{
											type="functiondef",
											args={type="list"},
											chunk=
											{
												type="chunk",
												{
													type="doend",
													chunk=ast.catch
												},
												{
													type="return",
													value=success
												}
											}
										},
										args=
										{
											type="list"
										}
									}
								}
							}
						}
					}
				}
			}
		}
		
	-- Add optional 'finally' block.
	
	if ast.finally then
		chunk[#chunk+1] =
			{
				type="doend",
				chunk=ast.finally
			}
	end
	
	-- Now add the return-from-function handler.
	
	chunk[#chunk+1] =
		{
			type="ifelseend",
			{
				condition=
				{
					type="binop",
					operator="and",
					left=
					{
						type="deref",
						left=result,
						right=identifierleaf("1")
					},
					right=
					{
						type="binop",
						operator="~=",
						left=
						{
							type="deref",
							left=result,
							right=identifierleaf("2")
						},
						right=success
					}
				},
				chunk=
				{
					type="chunk",
					{
						type="return",
						value=
						{
							type="functioncall",
							value=identifierleaf("unpack"),
							args=
							{
								type="list",
								result,
								identifierleaf("2")
							}
						}
					}
				}
			}
		}
		
	return
		{
			type="doend",
			chunk=chunk
		}
end
