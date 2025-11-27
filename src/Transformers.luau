--!strict

local Types = require(script.Parent.Types)

local pluginGlobalIndex: Types.pluginGlobalIndex = _G["AutoComplete+"]

local module = {}

local blacklistedCharacters: { [string]: true } = {}
for _, character in { " ", "-", "+", ",", ".", "/", "%", "$", "£", "&", "*", "(", ")", "'", "[", "]", "{", "}", "#", "?", "!", "~", "@", "=", ":", ";" } do
	blacklistedCharacters[character] = true
end
function module.asNeutralImportName(importName: string): string
	local result: { string } = table.create(#importName)
	for i, letter in string.split(importName, "") do
		result[i] = blacklistedCharacters[letter] and "_" or letter
	end

	return table.concat(result)
end

function module.processVariableName(variableDeclaration: string, importType: number): string
	local newVariableDeclaration: string = module.asNeutralImportName(variableDeclaration)
	if tonumber(string.sub(newVariableDeclaration, 1, 1)) then
		newVariableDeclaration = "_" .. string.sub(newVariableDeclaration, 2)
	end

	local importStyle = if importType == 1 then pluginGlobalIndex.ServiceImportStyle elseif importType == 2 then pluginGlobalIndex.ModuleImportStyle else pluginGlobalIndex.InstanceImportStyle
	-- PascalCase is default -> we do nothing (assume the instance name is in PascalCase)

	if importStyle == "camelCase" then
		return string.lower(string.sub(newVariableDeclaration, 1, 1)) .. string.sub(newVariableDeclaration, 2)
	elseif importStyle == "snake_case" then
		local spaced = string.gsub(newVariableDeclaration, "(%u)", " %1")
		local stringTable = string.split(spaced, " ")
		local result = table.create(#stringTable)

		for i, character in stringTable do
			result[i] = string.lower(character)
		end

		return table.concat(result, "_", 2)
	end

	return newVariableDeclaration
end

-- for when an instance's path needs its characters transformed to allow for it to exist in a script
function module.transformInstancePathToValid(instance: ModuleScript | Instance, importingScript: LuaSourceContainer): (string, boolean)
	local newImportPath: string = ""
	local lastAncestor: Instance

	local didNotUseService: boolean = false
	local prefix: string = "script"
	if instance:IsDescendantOf(importingScript) then
		didNotUseService = true
		lastAncestor = importingScript
	elseif instance:IsDescendantOf(importingScript.Parent :: any) then
		didNotUseService = true
		lastAncestor = importingScript.Parent :: any
		prefix = "script.Parent"
	else
		lastAncestor = game[string.split(instance:GetFullName(), ".")[1]]
	end
	
	local lastImportWasTransformed: boolean = false
	local parent: Instance = instance
	while parent ~= lastAncestor do
		local parentName: string = parent.Name
		local parentNameAsNeutral = module.asNeutralImportName(parentName)

		if parentNameAsNeutral ~= parentName or tonumber(string.sub(parentName, 1, 1)) then
			if not lastImportWasTransformed and parent ~= instance then
				newImportPath = "[\"" .. parentName .. "\"]" .. "." .. newImportPath
			else
				newImportPath = "[\"" .. parentName .. "\"]" .. newImportPath
			end

			lastImportWasTransformed = true
		else
			if lastImportWasTransformed or parent == instance then
				newImportPath = parentName .. newImportPath
			else
				newImportPath = parentName .. "." .. newImportPath
			end

			lastImportWasTransformed = false
		end

		parent = parent.Parent :: ModuleScript | Instance
	end

	local lastAncestorName = if didNotUseService then prefix else module.processVariableName(lastAncestor.Name, 1)
	if lastImportWasTransformed then
		newImportPath = lastAncestorName .. newImportPath
	else
		newImportPath = lastAncestorName .. "." .. newImportPath
	end

	return newImportPath, didNotUseService
end

function module.getNameOfImportedItemFromDeclaration(declaration: string): string
	local itemNameResult: { string } = {}

	local function walkBackUntil(terminator: string, offset: number): ()
		-- Walk backwards until a terminator, collecting characters
		local i: number = #declaration - offset
		while i > 0 do
			local character: string = string.sub(declaration, i, i)
			if character == terminator then
				break
			end
			table.insert(itemNameResult, 1, character)
			i -= 1
		end
	end

	local offset: number = 0
	if string.sub(declaration, -1) == ")" then
		offset = 1
	end
	if string.sub(declaration, -2, -2) ~= "]" then
		-- .NAME
		walkBackUntil(".", offset)
	else
		-- ["NAME"]
		walkBackUntil("\"", offset + 2)
	end	

	return table.concat(itemNameResult)
end

function module.getNeededServiceNameToImportFromModuleOrInstance(instance: ModuleScript | Instance, lastServiceImportGroup: Types.lastImportGroup): string?
	local serviceName: string = string.split(instance:GetFullName(), ".")[1]
	local neutralServiceImport: string = module.asNeutralImportName(`local {module.processVariableName(serviceName, 1)} = game:GetService("{serviceName}")`)

	for _, alreadyImportedService in lastServiceImportGroup.all do
		if string.find(alreadyImportedService, serviceName) then
			return nil
		end
	end

	return serviceName
end

function module.getVariableNameFromLine(lineContents: string): string
	local variableName: { string } = {}
 	
	for i = 7, #lineContents do
		local character: string = string.sub(lineContents, i, i)
		if character == " " or character == "=" then
			break
		end

		variableName[i - 6] = character
	end
	
	return table.concat(variableName)
end

return module
