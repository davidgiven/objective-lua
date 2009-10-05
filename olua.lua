-- Objective Lua runtime
-- © 2009 David Given
-- This program is licensed under the MIT public license.
--
-- WARNING!
-- This is a TOY!
-- Do not use this program for anything useful!
--
-- This file provides the runtime support needed for Objective Lua programs
-- to work. There's nothing complex here; it's based on a vanilla table
-- munging class structure. (In fact, it's not right, and needs to be
-- rewritten to use a different object model; see
-- Object#doesNotRecogniseSelector: in test.olua.)

module("olua", package.seeall)

function declareclass(classname, superclass)
	local class = {}
	class._methods = {}
	
	local superclassmethods = nil
	if superclass then
		superclassmethods = superclass._methods

		setmetatable(class, {__index = superclass})		
		setmetatable(class._methods, {__index = superclass._methods})
	end
	
	class._methods.class = function(self)
		return class
	end
	
	class.superclass = function(self)
		return superclass
	end
	
	class.superclassMethods = function(self)
		return superclassmethods
	end
	
	class.name = function(self)
		return classname
	end
	
	return class
end

function defineclassmethod(class, methodname, body)
	class[methodname] = body
end

function definemethod(class, methodname, body)
	class._methods[methodname] = body
end
