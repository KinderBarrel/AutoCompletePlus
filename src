--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ScriptEditorService = game:GetService("ScriptEditorService")

if not RunService:IsEdit() then
	return
end

print([[
	Running AutoComplete+ v1.12. Report bugs in the ROSS server or message 'kinderbarrel' on Discord.
	[Give modules the '_NoImport' tag to not suggest them. Folders with this tag will not suggest descendants]
	[Give modules or folders the '_ClientOnly' tag to prevent scripts on the server side from suggesting module descendants]
	[Give instances the '_Importable' tag to suggest them]
	
	Changelog since last version (v1.11):
		AutoComplete+ will now not delete content written in the space between service, module or instance imports.
		The icon for importing instances is now the enum member icon.
		The ordering for service & instance imports are now based on length.
		Fixed some miscellaneous issues.
		In the menu for the plugin, you can now add a character, such as ':', to only allow import suggestions immediately after it's typed.
]])

if not _G["AutoComplete+"] then
	_G["AutoComplete+"] = {}
end
local pluginGlobalIndex = _G["AutoComplete+"]
pluginGlobalIndex.ImportStyle = plugin:GetSetting("ImportStyle")
pluginGlobalIndex.SuggestionCharacter = plugin:GetSetting("SuggestionCharacter")

-- Plugin UI
do
	local DockWidgetPluginGui = plugin:CreateDockWidgetPluginGui(
		"StylePicker", 
		DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Float,
			false,
			true,
			200,
			150,
			200,
			150
		)
	)

	local Frame = Instance.new("Frame")
	Frame.BackgroundColor3 = Color3.fromRGB(127, 252, 132)
	Frame.BorderSizePixel = 3
	Frame.Size = UDim2.fromScale(1, 1)
	
	local SuggestionCharacter = Instance.new("TextBox")
	SuggestionCharacter.Size = UDim2.fromScale(.2, .5)
	SuggestionCharacter.BackgroundTransparency = .5
	SuggestionCharacter.BorderSizePixel = 3
	SuggestionCharacter.Text = "Current Suggestion Character: " .. (plugin:GetSetting("SuggestionCharacter") or "NONE")
	SuggestionCharacter.TextScaled = true
	SuggestionCharacter.Position = UDim2.fromScale(1, 0)
	SuggestionCharacter.AnchorPoint = Vector2.new(1, 0)
	SuggestionCharacter.Parent = Frame
	SuggestionCharacter:GetPropertyChangedSignal("Text"):Connect(function()
		SuggestionCharacter.Text = string.sub(SuggestionCharacter.Text, #SuggestionCharacter.Text)
		
		local newSuggestionCharacter: string? = SuggestionCharacter.Text
		if newSuggestionCharacter == "" then
			newSuggestionCharacter = nil
		end
		
		pluginGlobalIndex.SuggestionCharacter = newSuggestionCharacter
		plugin:SetSetting("SuggestionCharacter", newSuggestionCharacter)
	end)

	local CurrentStyle = Instance.new("TextLabel")
	CurrentStyle.Size = UDim2.fromScale(.8, .5)
	CurrentStyle.BackgroundTransparency = 1
	CurrentStyle.Text = "Current Style: " .. (pluginGlobalIndex.ImportStyle or "PascalCase")
	CurrentStyle.TextScaled = true
	CurrentStyle.Parent = Frame

	local Styles = { "PascalCase", "camelCase", "snake_case" }

	for i = 1, 3 do
		local StyleButton = Instance.new("TextButton")
		StyleButton.Size = UDim2.fromScale(.25, .5)
		StyleButton.BackgroundTransparency = .5
		StyleButton.BorderSizePixel = 1
		StyleButton.Text = Styles[i]
		StyleButton.AnchorPoint = Vector2.new(.5, 1)
		StyleButton.TextScaled = true
		StyleButton.Position = UDim2.fromScale(.25 * i, 1)

		StyleButton.MouseButton1Click:Connect(function()
			plugin:SetSetting("ImportStyle", Styles[i])
			pluginGlobalIndex.ImportStyle = Styles[i]
			CurrentStyle.Text = "Current Style: " .. Styles[i]
		end)

		StyleButton.ZIndex = 2
		StyleButton.Parent = Frame
	end

	DockWidgetPluginGui.ZIndexBehavior = Enum.ZIndexBehavior.Global

	Frame.Parent = DockWidgetPluginGui

	local Button = plugin:CreateToolbar("AutoComplete+"):CreateButton("1", "Choose Import Variable Declaration Style", "rbxassetid://111947305844735", "Import Style")
	Button.Click:Connect(function()
		DockWidgetPluginGui.Enabled = not DockWidgetPluginGui.Enabled
	end)
end
-- Plugin UI

-- Plugin code starts
local INTERNAL_NUMERICAL_CODE_FOR_RIGHTPARENTHESIS: number = 41
local MAXIMUM_LINES_TO_PARSE: number = 100
local SERVICE_PREFIX: string = "~"
local MODULE_PREFIX: string = ";"
local INSTANCE_PREFIX: string = ">"
local DUPLICATE_MODULE_IDENTIFIER: string = "+"

local string_find = string.find
local string_sub = string.sub
local string_lower = string.lower
local string_match = string.match
local string_len = string.len
local string_byte = string.byte
local string_split = string.split
local string_gsub = string.gsub
local string_rep = string.rep

local table_find = table.find
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local table_sort = table.sort

type subRange = { ["character"]: number, ["line"]: number }
type textEdit = {
	["insert"]: {
		["end"]: subRange;
		["start"]: subRange
	};
	["replace"]: {
		["end"]: subRange;
		["start"]: subRange
	};
	["newText"]: string
}
type autoCompleteSuggestion = {
	["codeSample"]: string?;
	["detail"]: string;
	["documentation"]: { ["value"]: string };
	["kind"]: Enum.CompletionItemKind;
	["label"]: string;
	["learnMoreLink"]: string?;
	["overloads"]: number?;
	["preselect"]: boolean?;
	["tags"]: { Enum.CompletionItemTag }?;
	["textEdit"]: textEdit
}
type lastImportGroup = {
	["group"]: { string };
	["all"]: { string };
	["startLine"]: number?;
	["receivedImport"]: true?;
	["prePadding"]: number
}

local services: { [string]: string } = {
	-- Manual definition as run service is labelled as "Run Service"
	["runservice"] = "RunService";
	-- Manual definitions as these do not appear as children of game until they are initialised by a :GetService() call.
	["scriptcontext"] = "ScriptContext";
	["datastoreservice"] = "DataStoreService";
	["messagingservice"] = "MessagingService";
	["memorystoreservice"] = "MemoryStoreService";
	["teleportservice"] = "TeleportService"
}
local modules: { ModuleScript } = {}
local instances: { Instance } = {}
local clientOnlyModules: { ModuleScript } = {}

for _, service in game:GetChildren() do
	local success, service = pcall(function()
		return game:FindService(service.Name)
	end)

	if success and service then
		local serviceName = service.Name
		services[string_lower(serviceName)] = serviceName
	end
end

local moduleScriptOrigins: { Instance } = {
	game.ReplicatedFirst;
	game.ReplicatedStorage;
	game.StarterPlayer.StarterPlayerScripts;
	ServerScriptService;
	ServerStorage
}
local noImportFolders: { Folder } = {}

local function addModuleScript(moduleScript: ModuleScript): ()
	if table_find(modules, moduleScript) or moduleScript:HasTag("_NoImport") then
		return
	end
	for _, folder in noImportFolders do
		if moduleScript:IsDescendantOf(folder) then
			return
		end
	end

	table_insert(modules, moduleScript)
end
local function removeModuleScript(moduleScript: ModuleScript): ()
	local found = table_find(modules, moduleScript)
	if found then
		table_remove(modules, found)
	end
end
local function addInstance(instance: Instance): ()
	if table_find(instances, instance) then
		return
	end

	table_insert(instances, instance)
end
local function removeInstance(instance: Instance): ()
	local found = table_find(instances, instance)
	if found then
		table_remove(instances, found)
	end 
end
local function registerNoImportInstance(instance: Folder | ModuleScript): ()
	if instance:IsA("Folder") then
		if not table_find(noImportFolders, instance) then
			table_insert(noImportFolders, instance)
		end

		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("ModuleScript") then
				removeModuleScript(descendant)
			end
		end
	elseif instance:IsA("ModuleScript") then
		removeModuleScript(instance)
	end
end

for _, noImportInstance: Folder | ModuleScript in CollectionService:GetTagged("_NoImport") do
	registerNoImportInstance(noImportInstance)
end
for _, instance: Instance in CollectionService:GetTagged("_Importable") do
	addInstance(instance)
end

CollectionService:GetInstanceAddedSignal("_NoImport"):Connect(function(instance: Folder | ModuleScript)
	registerNoImportInstance(instance)
end)
CollectionService:GetInstanceRemovedSignal("_NoImport"):Connect(function(instance: Folder | ModuleScript)
	if instance:IsA("Folder") then
		local found = table_find(noImportFolders, instance)
		if found then
			table_remove(noImportFolders, found)
		end

		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("ModuleScript") and not descendant:HasTag("_NoImport") then
				addModuleScript(descendant)
			end
		end
	elseif instance:IsA("ModuleScript") then
		addModuleScript(instance)
	end
end)
CollectionService:GetInstanceAddedSignal("_Importable"):Connect(function(instance: Instance)
	if instance:IsA("ModuleScript") then
		return
	end

	addInstance(instance)
end)
CollectionService:GetInstanceRemovedSignal("_Importable"):Connect(function(instance: Instance)
	if instance:IsA("ModuleScript") then
		return
	end

	removeInstance(instance)
end)
for _, origin in moduleScriptOrigins do
	for _, moduleScript in origin:GetDescendants() do
		if moduleScript:IsA("ModuleScript") then
			addModuleScript(moduleScript)
		end
	end
	origin.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ModuleScript") then
			addModuleScript(descendant)
		end
	end)
	origin.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("ModuleScript") then
			removeModuleScript(descendant)
		end
	end)
end

local blacklistedCharacters: { string } = { " ", "-", "+", ",", ".", "/", "%", "$", "£", "&", "*", "(", ")", "'", "[", "]", "{", "}", "#", "?", "!", "~", "@", "=", ":", ";" }
local function asNeutralImportName(importName: string): string
	local newImportName = ""
	for _, letter in string_split(importName, "") do
		if table_find(blacklistedCharacters, letter) then
			newImportName ..= "_"
		else
			newImportName ..= letter
		end
	end

	return newImportName
end

local function processVariableDeclaration(variableDeclaration: string): string
	local newVariableDeclaration: string = asNeutralImportName(variableDeclaration)
	if tonumber(string_sub(newVariableDeclaration, 1, 1)) then
		newVariableDeclaration = "_" .. string_sub(newVariableDeclaration, 2)
	end

	local importStyle = pluginGlobalIndex.ImportStyle
	-- PascalCase is default -> we do nothing

	if importStyle == "camelCase" then
		return string_lower(string_sub(newVariableDeclaration, 1, 1)) .. string_sub(newVariableDeclaration, 2)
	elseif importStyle == "snake_case" then
		local snakeVariableDeclaration: string = ""
		local stringTable = string_split(string_sub(string_gsub(newVariableDeclaration, "(%u)", " %1"), 1, -1), " ")

		for i, content in stringTable do
			snakeVariableDeclaration ..= string_lower(content)

			if i == 1 then
				continue
			end

			if stringTable[i + 1] then
				snakeVariableDeclaration ..= "_"
			end
		end

		return snakeVariableDeclaration
	end

	return newVariableDeclaration
end
-- for when an instance's path needs its characters transformed to allow for it to exist in a script
local function transformInstancePathToValid(instance: ModuleScript | Instance, importingScript: LuaSourceContainer): (string, boolean)
	local newModulePath: string = ""
	local lastAncestor: Instance
	
	local didNotUseService = false
	if instance:IsDescendantOf(importingScript) then
		didNotUseService = true
		lastAncestor = importingScript
	else
		lastAncestor = game[string_split(instance:GetFullName(), ".")[1]]
	end

	local lastImportWasTransformed: boolean = false
	local parent: Instance = instance
	while parent ~= lastAncestor do
		local parentName: string = parent.Name
		local parentNameAsNeutral = asNeutralImportName(parentName)
		
		if parentNameAsNeutral ~= parentName or tonumber(string_sub(parentName, 1, 1)) then
			if not lastImportWasTransformed and parent ~= instance then
				newModulePath = "[\"" .. parentName .. "\"]" .. "." .. newModulePath
			else
				newModulePath = "[\"" .. parentName .. "\"]" .. newModulePath
			end

			lastImportWasTransformed = true
		else
			if lastImportWasTransformed or parent == instance then
				newModulePath = parentName .. newModulePath
			else
				newModulePath = parentName .. "." .. newModulePath
			end

			lastImportWasTransformed = false
		end

		parent = parent.Parent :: ModuleScript -- isnt exclusive to ModuleScript but stops type solver from crying
	end

	local lastAncestorName = if didNotUseService then "script" else lastAncestor.Name
	if lastImportWasTransformed then
		newModulePath = processVariableDeclaration(lastAncestorName) .. newModulePath
	else
		newModulePath = processVariableDeclaration(lastAncestorName) .. "." .. newModulePath
	end

	return newModulePath, didNotUseService
end
local function getNameOfImportedItemFromDeclaration(declaration: string): string?
	local nameOfItem: string? = string_match(declaration, '%["(.-)"%]')
	if nameOfItem then
		return nameOfItem
	end

	nameOfItem = string_match(declaration, '[%[%.]([^%[%].]+)$')
	if nameOfItem then
		if string_byte(nameOfItem, -1) == INTERNAL_NUMERICAL_CODE_FOR_RIGHTPARENTHESIS then
			return string_sub(nameOfItem, 1, -2)
		end

		return nameOfItem
	end

	return nil
end
local function getNeededServiceNameToImportFromModuleOrInstance(instance: ModuleScript | Instance, lastServiceImportGroup: lastImportGroup): string?
	local serviceName: string = string_split(instance:GetFullName(), ".")[1]
	local serviceImport: string = `local {processVariableDeclaration(serviceName)} = game:GetService("{serviceName}")`
	local neutralServiceImport: string = asNeutralImportName(serviceImport)
	local canInsert: boolean = true
	for _, alreadyImportedService in lastServiceImportGroup.all do
		if asNeutralImportName(alreadyImportedService) == neutralServiceImport then
			canInsert = false
			break
		end
	end
	if canInsert then
		return serviceName
	end
	
	return
end

local duplicateModules: { [string]: { ModuleScript } } = {}
-- Imports the service/modules script. importType 1 -> Service, 2 -> ModuleScript, 3 -> Instance
local function import(document: ScriptDocument, importName: string, importType: number): number?
	local currentScript = document:GetScript()
	local documentLines: { string } = string_split(document:GetText(), "\n")
	local lastServiceImportGroup: lastImportGroup = { group = {}, all = {}, prePadding = 0 }
	local lastModuleImportGroup: lastImportGroup = { group = {}, all = {}, prePadding = 0 }
	local lastInstanceImportGroup: lastImportGroup = { group = {}, all = {}, prePadding = 0 }
	
	local serviceGroupImportStartLine: number = 1
	local selectedLine: number = document:GetSelection()
	
	-- First we check if this was already imported
	local commentBlocks: number = 0
	for lineNumber, lineContents in documentLines do
		if lineNumber > MAXIMUM_LINES_TO_PARSE or lineNumber > selectedLine then
			break
		end
		
		if commentBlocks > 0 or string_find(lineContents, "%-%-") then
			if string_find(lineContents, "%-%-%[%[") then
				commentBlocks += 1
			end
			if string_find(lineContents, "%]%]") then
				commentBlocks -= 1
			end
			
			serviceGroupImportStartLine += 1
			continue
		end
		
		if string_sub(lineContents, 1, 1) == "	" then
			continue
		end
		
		local serviceMatch: string? = string_match(lineContents, 'local[%s%w\_]+%s=%sgame:GetService%("%w+"%)')
		local moduleMatch: string? = string_match(lineContents, 'local[%s%w\_]+%s=%srequire%([%w%p%s]+%)') or string_match(lineContents, 'require%([%w%p%s]+%)')
		local existingImport: string? = (serviceMatch or moduleMatch)
		-- If neither module & service are imported on this line but a local exists,
		local instanceName: string?
		if not existingImport then
			-- check if it's an instance import
			instanceName = string_find(lineContents, "local") and getNameOfImportedItemFromDeclaration(lineContents)
			if instanceName then
				existingImport = lineContents
			end
		end
		if not existingImport then
			continue
		end
		-- Check if the line contains what we already imported to avoid double importing
		if string_find(asNeutralImportName(existingImport), "^" .. asNeutralImportName(importName)) then
			-- This is already imported. Exit
			return
		end
		
		-- Otherwise, build up the groups.
		local lastImportGroup =
			if serviceMatch then
				lastServiceImportGroup
			elseif moduleMatch then
				lastModuleImportGroup
			else
				lastInstanceImportGroup
		
		if not lastImportGroup.startLine then
			lastImportGroup.startLine = lineNumber
		else
			if lastImportGroup.startLine + #lastImportGroup.group < lineNumber  then
				lastImportGroup.startLine = lineNumber
				lastImportGroup.group = {}
			end
		end
		
		table_insert(lastImportGroup.all, existingImport)
		table_insert(lastImportGroup.group, existingImport)
	end

	local function importService(serviceName: string?): ()
		if not serviceName then
			return
		end
		
		-- Import service. No collateral import checks necessary.
		lastServiceImportGroup.receivedImport = true
		table_insert(lastServiceImportGroup.group, `local {processVariableDeclaration(serviceName)} = game:GetService("{serviceName}")`)

		if not lastServiceImportGroup.startLine then
			lastServiceImportGroup.startLine = serviceGroupImportStartLine
		end
		if #lastServiceImportGroup.group == 1 and serviceGroupImportStartLine > 1 then
			lastServiceImportGroup.prePadding = 1
		end
	end
	
	if importType == 1 then
		importService(importName)
	elseif importType == 2 then
		-- Import module. Duplicate import checks necessary
		local importModuleScript: ModuleScript
		-- check if module is a duplicate import attempt
		if string_sub(importName, -2, -2) == DUPLICATE_MODULE_IDENTIFIER then
			-- this does mean there is a limit of 9 duplicates
			importModuleScript = duplicateModules[string_sub(importName, 1, -3)][(tonumber(string_sub(importName, -1, -1)) :: number)]
		else
			local loweredImportName: string = string_lower(importName)
			for _, moduleScript in modules do
				if string_lower(moduleScript.Name) == loweredImportName then
					importModuleScript = moduleScript
					break
				end
			end
		end

		lastModuleImportGroup.receivedImport = true
		local path, noService = transformInstancePathToValid(importModuleScript, currentScript)
		if not noService then
			importService(getNeededServiceNameToImportFromModuleOrInstance(importModuleScript, lastServiceImportGroup))
		end
		table_insert(lastModuleImportGroup.group, `local {processVariableDeclaration(importName)} = require({path})`)
		
		if not lastModuleImportGroup.startLine then
			-- place after last service import group
			lastModuleImportGroup.startLine = (lastServiceImportGroup.startLine or serviceGroupImportStartLine) + #lastServiceImportGroup.group
			if lastModuleImportGroup.startLine ~= 1 and #lastModuleImportGroup.group == 1 and not (lastServiceImportGroup.receivedImport and #lastServiceImportGroup.group == 1) then
				if documentLines[lastModuleImportGroup.startLine :: any - 1] :: any ~= "" then
					lastModuleImportGroup.prePadding = 1
				end
			end
		end
	elseif importType == 3 then
		local importInstance: Instance
		local loweredImportName = string_lower(importName)
		for _, instance in instances do
			if string_lower(instance.Name) == loweredImportName then
				importInstance = instance
				break
			end
		end

		lastInstanceImportGroup.receivedImport = true
		local path, noService = transformInstancePathToValid(importInstance, currentScript)
		if not noService then
			importService(getNeededServiceNameToImportFromModuleOrInstance(importInstance, lastServiceImportGroup))
		end
		table_insert(lastInstanceImportGroup.group, `local {processVariableDeclaration(importName)} = {path}`)
		
		if not lastInstanceImportGroup.startLine then
			local startLine: number
			if lastModuleImportGroup.startLine then
				startLine = lastModuleImportGroup.startLine + #lastModuleImportGroup.group
			else
				startLine = (lastServiceImportGroup.startLine or serviceGroupImportStartLine) + #lastServiceImportGroup.group
			end
			
			lastInstanceImportGroup.startLine = startLine
			if startLine ~= 1 and #lastInstanceImportGroup.group == 1 and not (lastServiceImportGroup.receivedImport and #lastServiceImportGroup.group == 1) then
				if documentLines[lastInstanceImportGroup.startLine :: any - 1] :: any ~= "" then
					lastInstanceImportGroup.prePadding = 1
				end
			end
		end
	end
	
	table.sort(lastServiceImportGroup.group, function(a, b)
		return #a <  #b
	end)
	table.sort(lastInstanceImportGroup.group, function(a, b)
		return #a <  #b
	end)
	
	local numberOfLines: number = document:GetLineCount()
	local lastDocumentLineCount: number = numberOfLines
	local serviceImportMovedLine: boolean = false
	for i = 1, 3 do
		local lastImportGroup: lastImportGroup = if i == 1 then lastServiceImportGroup elseif i == 2 then lastModuleImportGroup else lastInstanceImportGroup
		if not lastImportGroup.receivedImport then
			continue
		end
		
		local lineCount: number = i == 1 and numberOfLines or document:GetLineCount()
		local lineCountDifference: number = lineCount - lastDocumentLineCount
		local text: string = string_rep("\n", lastImportGroup.prePadding) .. table_concat(lastImportGroup.group, "\n")
		local importGroupStartLine: number = math.min(lastImportGroup.startLine :: number + lineCountDifference, lineCount)
		if serviceImportMovedLine and lastServiceImportGroup.receivedImport and #lastImportGroup.group == 1 then
			-- if double import (service & module | service & instance), decrease by 1 if service caused a line to move
			-- so that the +1 lines are accounted for and the 2nd import is not offset
			importGroupStartLine -= 1
		end
		
		local nextLineNumber: number = importGroupStartLine + #lastImportGroup.group - 1
		local nextLine: string? = (i == 1 and documentLines or string_split(document:GetText(), "\n"))[nextLineNumber]
		
		if nextLine and string_len(nextLine) > 0 and not string_find(nextLine, importName) --[[and not (string_find(nextLine, importName) or string_find(nextLine, "require") or string_find(nextLine, "GetService") or getNameOfImportedItemFromDeclaration(nextLine))]] then
			-- if there exists content at point of import, it doesn't get erased
			if i == 1 then
				serviceImportMovedLine = true
			end
			-- space a line from import but don't create an extra space if it's an instance import
			text = text .. (i == 3 and "\n" or "\n\n") .. nextLine .. "\n"
		else
			-- space a line from import
			text ..= "\n\n"
		end

		lastDocumentLineCount = document:GetLineCount()
		document:EditTextAsync(
			text,
			importGroupStartLine,
			1,
			math.min(importGroupStartLine + #lastImportGroup.group, lastDocumentLineCount),
			1
		)
	end
	
	-- return the number of lines added to the document
	return document:GetLineCount() - numberOfLines
end

local function generateTextEdit(newText: string, startCharacter: number, line: number, length: number, duplicateIndexString: string?): textEdit
	return {
		insert = {
			start = {
				character = startCharacter - length;
				line = line
			};
			["end"] = {
				character = startCharacter;
				line = line
			}
		};
		replace = {
			start = {
				character = startCharacter - length;
				line = line
			};
			["end"] = {
				character = startCharacter;
				line = line
			}
		}
	} :: textEdit
end
local function generateAutoCompleteSuggestionFromServiceName(lower_serviceName: string, startCharacter: number, line: number, length: number): autoCompleteSuggestion
	local serviceName: string = services[lower_serviceName]
	local autoCompleteSuggestion: autoCompleteSuggestion = {
		label = serviceName;
		detail = "Get Service: " .. serviceName;
		kind = Enum.CompletionItemKind.Text;
		documentation = { value = "Imports the service [" .. serviceName .. "]." };
		textEdit = generateTextEdit(serviceName, startCharacter, line, length)
	}
	autoCompleteSuggestion.textEdit.newText = SERVICE_PREFIX .. serviceName

	return autoCompleteSuggestion
end
local function generateAutoCompleteSuggestionFromModuleScript(moduleScript: ModuleScript, startCharacter: number, line: number, length: number, duplicateIndex: number?, currentScript: LuaSourceContainer): autoCompleteSuggestion
	local moduleScriptName: string = moduleScript.Name
	local duplicateIndexString: string = moduleScriptName .. (duplicateIndex and (DUPLICATE_MODULE_IDENTIFIER .. duplicateIndex) or "")
	local autoCompleteSuggestion: autoCompleteSuggestion = {
		label = moduleScriptName;
		detail = "Require: " .. duplicateIndexString;
		kind = Enum.CompletionItemKind.Text;
		documentation = { value = "Imports the module script [" .. duplicateIndexString .. "] from [" .. transformInstancePathToValid(moduleScript, currentScript) .. "]." };
		textEdit = generateTextEdit(moduleScriptName, startCharacter, line, length, duplicateIndexString)
	}
	autoCompleteSuggestion.textEdit.newText = MODULE_PREFIX .. (duplicateIndexString or moduleScriptName)

	return autoCompleteSuggestion
end
local function generateAutoCompleteSuggestionFromInstance(instance: Instance, startCharacter: number, line: number, length: number): autoCompleteSuggestion
	local instanceName: string = instance.Name
	local autoCompleteSuggestion: autoCompleteSuggestion = {
		label = instanceName;
		detail = "Import: " .. instanceName;
		kind = Enum.CompletionItemKind.EnumMember;
		documentation = { value = "Imports the instance [" .. instanceName .. "]." };
		textEdit = generateTextEdit(instanceName, startCharacter, line, length)
	}
	autoCompleteSuggestion.textEdit.newText = INSTANCE_PREFIX .. instanceName

	return autoCompleteSuggestion
end

pcall(function()
	ScriptEditorService:DeregisterAutocompleteCallback("AutoComplete")
end)
ScriptEditorService:RegisterAutocompleteCallback("AutoComplete", 1, function(locator: { ["position"]: subRange, ["textDocument"]: { ["document"]: ScriptDocument, ["script"]: Script } }, existingSuggestions: { ["items"]: { autoCompleteSuggestion } })
	local document: ScriptDocument = locator.textDocument.document
	if document:IsCommandBar() then
		return existingSuggestions
	end
	
	local currentLine: string = document:GetText(locator.position.line, 1, locator.position.line, locator.position.character)
	local currentWordStart: number?, currentWordEnd: number? = string_find(currentLine, "%w+$")
	local currentWord: string
	
	local suggestionCharacter = pluginGlobalIndex.SuggestionCharacter
	if suggestionCharacter and suggestionCharacter ~= "" then
		currentWordStart, currentWordEnd = string.find(currentLine, suggestionCharacter .. "([^" .. suggestionCharacter .. "]*)$")
		
		if not currentWordEnd or locator.position.character <= currentWordEnd then
			return existingSuggestions
		end
		
		currentWord = string_lower(string_sub(currentLine, currentWordStart :: number + 1, currentWordEnd))
	else
		if not currentWordStart or not currentWordEnd then
			return existingSuggestions
		end

		-- Check import availability
		if #existingSuggestions.items == 0 then
			return existingSuggestions
		elseif currentWordStart > 1 then
			local previousCharacter = string.sub(currentLine, currentWordStart - 1, currentWordStart - 1)
			if previousCharacter ~= "(" and not string.find(previousCharacter, "%s") then
				return existingSuggestions
			end
		end
		
		currentWord = string_lower(string_sub(currentLine, currentWordStart :: number, currentWordEnd))
	end

	local currentWordLength = string_len(currentWord)

	local alreadyImported: { string } = {}
	for line, lineContents in string_split(document:GetText(), "\n") do
		if line > MAXIMUM_LINES_TO_PARSE or line > locator.position.line then
			break
		end

		-- Look for service import first
		local existingImport: string? = string_match(lineContents, '%(%s*"(.-)"%s*%)')
		if existingImport then
			table_insert(alreadyImported, string_lower(existingImport))
			continue
		end

		-- Look for instance / module script import
		existingImport = (string_find(lineContents, "local") or string_find(lineContents, "require")) and getNameOfImportedItemFromDeclaration(lineContents)
		if existingImport then
			table_insert(alreadyImported, asNeutralImportName(existingImport))
		end
	end

	local currentScript: Script | ModuleScript = locator.textDocument.script
	local isInServerContext: boolean = currentScript:IsDescendantOf(ServerScriptService) or currentScript:IsDescendantOf(ServerStorage)
	duplicateModules = {}

	for lower_serviceName, serviceName in services do
		if string_find(lower_serviceName, currentWord) and not table_find(alreadyImported, lower_serviceName) then
			table_insert(existingSuggestions.items, generateAutoCompleteSuggestionFromServiceName(lower_serviceName, locator.position.character, locator.position.line, currentWordLength))
		end
	end
	
	local clientOnlyModules = CollectionService:GetTagged("_ClientOnly")
	for _, moduleScript in modules do
		if isInServerContext then
			if moduleScript:HasTag("_ClientOnly") then
				continue
			end
			local fail: boolean = false
			for _, clientOnlyModule in clientOnlyModules do
				if moduleScript:IsDescendantOf(clientOnlyModule) then
					fail = true
					break
				end
			end
			if fail then
				continue
			end
		else
			if moduleScript:IsDescendantOf(ServerScriptService) or moduleScript:IsDescendantOf(ServerStorage) then
				continue
			end
		end

		local moduleScriptName: string = moduleScript.Name
		if moduleScript ~= (currentScript :: ModuleScript) and string_find(string_lower(moduleScriptName), currentWord) then
			local duplicateIndex: number? = nil
			local existingDuplicates = duplicateModules[moduleScriptName]
			if existingDuplicates then
				duplicateIndex = #existingDuplicates + 1
				table_insert(existingDuplicates, moduleScript)

				moduleScriptName ..= "_" .. (duplicateIndex :: number)
			else
				duplicateModules[moduleScriptName] = {}
			end

			if table_find(alreadyImported, asNeutralImportName(moduleScriptName))  then
				continue
			end

			table_insert(existingSuggestions.items, generateAutoCompleteSuggestionFromModuleScript(moduleScript, locator.position.character, locator.position.line, currentWordLength, duplicateIndex, currentScript))
		end
	end
	for _, instance in instances do
		if table_find(alreadyImported, asNeutralImportName(instance.Name)) then
			continue
		end
		if (instance:IsDescendantOf(ServerScriptService) or instance:IsDescendantOf(ServerStorage)) and not isInServerContext then
			continue
		end

		table_insert(existingSuggestions.items, generateAutoCompleteSuggestionFromInstance((instance :: ModuleScript), locator.position.character, locator.position.line, currentWordLength))
	end

	return existingSuggestions
end)

if pluginGlobalIndex.TextChangeConnection then
	pluginGlobalIndex.TextChangeConnection:Disconnect()
end
if pluginGlobalIndex.ListenToDisableConnection then
	pluginGlobalIndex.ListenToDisableConnection:Disconnect()
end

local lastWasUndone: boolean = false
pluginGlobalIndex.TextChangeConnection = ScriptEditorService.TextDocumentDidChange:Connect(function(document, changesArray: { { ["text"]: string, ["range"]: { ["end"]: subRange, ["start"]: subRange } } })
	if document:IsCommandBar() then
		return
	end

	local change = changesArray[1]
	local textLength: number = string_len(change.text)

	if textLength <= 1 then
		-- check if typing normally
		return
	end

	local firstCharacter: string = string_sub(change.text, 1, 1)
	if firstCharacter ~= SERVICE_PREFIX and firstCharacter ~= MODULE_PREFIX and firstCharacter ~= INSTANCE_PREFIX then
		return
	end

	local importWhat: string = string_sub(change.text, 2, textLength)
	local lines: { string } = string_split(document:GetText(), "\n")
	local selectedLine: number = document:GetSelection()

	if lastWasUndone and (#lines == 1 or string_find(lines[1], importWhat, 1, true)) then
		lastWasUndone = false
		return
	end

	for line, lineContents in lines do
		if line > MAXIMUM_LINES_TO_PARSE or line > selectedLine then
			break
		end

		if string_find(lineContents, `local {processVariableDeclaration(importWhat)} =`, 1, true) then
			lastWasUndone = true
			-- User just did an undo
			return
		end
	end
	lastWasUndone = false

	local currentLineContents: string = lines[change.range.start.line]
	local importType: number
	if firstCharacter == SERVICE_PREFIX then
		importType = 1
	elseif firstCharacter == MODULE_PREFIX then
		importType = 2
	elseif firstCharacter == INSTANCE_PREFIX then
		importType = 3
	end
	local padding: number? = import(document, importWhat, importType)

	if padding then
		local newLine: number = change.range.start.line + padding
		local findStart: number?, findEnd: number? = string_find("^" .. asNeutralImportName(currentLineContents), asNeutralImportName(change.text))
		if not findStart or not findEnd then
			return
		end

		local startCharacterOffset: number = 2
		if pluginGlobalIndex.SuggestionCharacter and pluginGlobalIndex.SuggestionCharacter ~= "" then
			startCharacterOffset = 3
		end
		
		document:EditTextAsync(
			string_sub(currentLineContents, 1, findStart - startCharacterOffset)
				.. processVariableDeclaration(importWhat)
				.. string_sub(currentLineContents, findEnd),
			newLine,
			1,
			newLine,
			string_len(string_split(document:GetText(), "\n")[newLine]) + 1
		)
		
		document:RequestSetSelectionAsync(newLine, string_len(string_sub(currentLineContents, 1, findStart - startCharacterOffset) .. importWhat) + 1)
	end
end)

pluginGlobalIndex.ListenToDisableConnection = plugin.Unloading:Once(function()
	print("Disabled AutoComplete+")

	pluginGlobalIndex.TextChangeConnection:Disconnect()
	ScriptEditorService:DeregisterAutocompleteCallback("AutoComplete")
end)
