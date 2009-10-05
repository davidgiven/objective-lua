-- Objective Lua preprocessor
-- © 2009 David Given
-- This program is licensed under the MIT public license.
--
-- WARNING!
-- This is a TOY!
-- Do not use this program for anything useful!
--
-- This program preprocesses an Objective Lua input file into a standard Lua
-- output file. Use it as follows:
--
--   lua oluac.lua <infile> <outfile>
--
-- You'll need the Leg parser on your Lua path. Error handling and
-- documentation is nonexistent; here be dragons.

local lpeg = require("lpeg")
local parser = require("leg.parser")

local V = lpeg.V
local P = lpeg.P
local S = lpeg.S
local C = lpeg.C
local Cs = lpeg.Cs

-- Merge our new rules into the standard parser.

local ALL
do
	local oldStat = parser.rules.Stat
	local oldBlock = parser.rules.Block
	local oldExp = parser.rules.Exp
	local s = parser.rules.IGNORED -- scanner.IGNORED or V'IGNORED' could be used

	local OLUA = P(
		parser.apply
			-- Rules
			{
				UnarySelectorElement = V'ID',
				MultipleSelectorElement = V'ID' * P':',
				
				MultipleMethodArg = s* C(V'MultipleSelectorElement') *s* V'Exp' *s,
				MultipleMethodContinuingArg = s* C(V'MultipleSelectorElement' + P',') *s* V'Exp' *s,
				
				UnaryMethodArgList = C(V'UnarySelectorElement')
					/ function(selector)
						return selector, ""
					end,
				
				MultipleMethodArgList = V'MultipleMethodArg' *s*
						(s* V'MultipleMethodContinuingArg')^0,
				 
				MethodArgList = (V'MultipleMethodArgList' +
					V'UnaryMethodArgList')
					/ function(...)
						local selector = {}
						local args = {}
						for i = 1, select('#', ...), 2 do
							local selectorelement = select(i, ...)
							if (selectorelement ~= ',') then
								selector[#selector+1] = selectorelement
							end
							
							local arg = select(i+1, ...)
							if (arg ~= '') then
								args[#args+1] = arg
							end
						end
						
						return table.concat(selector), args
					end,
						
				MultipleDeclarationArg = s* C(V'MultipleSelectorElement') *s* C(V'ID') *s,
				MultipleDeclarationContinuingArg = s* C(V'MultipleSelectorElement' + P',') *s* C(V'ID') *s,
				
				UnaryDeclarationArgList = C(V'UnarySelectorElement')
					/ function(selector)
						return selector, ""
					end,
				
				MultipleDeclarationArgList = V'MultipleDeclarationArg' *s*
						(s* V'MultipleDeclarationContinuingArg')^0,
				 
				DeclarationArgList = (V'MultipleDeclarationArgList' +
					V'UnaryDeclarationArgList')
					/ function(...)
						local selector = {}
						local args = {}
						for i = 1, select('#', ...), 2 do
							local selectorelement = select(i, ...)
							if (selectorelement ~= ',') then
								selector[#selector+1] = selectorelement
							end
							
							local arg = select(i+1, ...)
							if (arg ~= '') then
								args[#args+1] = arg
							end
						end
						
						if (#args > 0) then
							return table.concat(selector), ','..table.concat(args, ',')
						else
							return table.concat(selector), ''
						end 
					end,
						
				SuperMethodCall = P'[' *s* P'super' *s* V'MethodArgList'
						 *s* P']'
					/ function(selector, args)
						local comma = ','
						if #args == 0 then
							comma = ''
						end
						
						selector = string.gsub(selector, ':', '_')
						return '__olua_superclass_methods.' .. selector ..
							'(self' .. comma .. table.concat(args, ',') .. ')'
					end,
				
				MethodCall = P'[' *s* V'Exp' *s* V'MethodArgList'
						 *s* P']'
					/ function(object, selector, args)
						selector = string.gsub(selector, ':', '_')
						return object .. ':' .. selector .. '(' .. table.concat(args, ',') .. ')'
					end,
				
				ClassImplementation = P'@implementation' *s* C(V'ID')
						*s* V'Block' *s* P'@end'
					/ function(class, block)
						return 'do ' ..
							'local __olua_current_class = '..class..
							' local __olua_superclass_methods = '..class..':superclassMethods()'..
							' '..block..
							' end'
					end,
				
				ClassDeclaration = P'@interface' *s* C(V'ID')
						*s* (P':' *s* C(V'ID'))^-1 *s* P'@end'
					/ function(class, superclass)
						if not superclass then
							superclass = 'nil'
						end
						return class .. '=olua.declareclass(' ..
							'"' .. class .. '",' ..
							superclass .. ')' ..
							'local ' .. class .. '=' .. class
					end,
					
				MethodImplementation = C(S'-+') *s* V'DeclarationArgList'
						 *s* V'Block' *s* P'end'
					/ function(type, selector, args, block)
						local result = {}
						if (type == '-') then
							result[#result+1] = 'olua.definemethod'
						else
							result[#result+1] = 'olua.defineclassmethod'
						end
						
						result[#result+1] = '(__olua_current_class, "'
						result[#result+1] = selector:gsub(':', '_')
						result[#result+1] = '", function(self'
						result[#result+1] = args
						result[#result+1] = ')'
						result[#result+1] = block
						result[#result+1] = 'end)'
						return table.concat(result)
					end,
					
				Exp = Cs(V'SuperMethodCall' + V'MethodCall' + oldExp),
				
				Stat = Cs(V'ClassDeclaration' +
					V'ClassImplementation' +
					V'MethodImplementation' +
					V'SuperMethodCall' +
					V'MethodCall' +
					oldStat),
				Block = Cs(oldBlock)
			}, 
			
			-- Captures
			{
			}
	)
	
	ALL = Cs(OLUA)	
end

-- Do the preprocessing.

do
	local infile = io.open(arg[1], "r")
	local intext = infile:read("*a")
	
	local outtext = ALL:match(intext)
	local outfile = io.open(arg[2], "w")
	outfile:write('require "olua"\n')
	outfile:write(outtext)
end
