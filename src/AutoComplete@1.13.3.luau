--!strict

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ScriptEditorService = game:GetService("ScriptEditorService")

if not RunService:IsEdit() then
	return
end
if not _G["AutoComplete+"] then
	_G["AutoComplete+"] = {}
end

local Types = require(script.Types)

print("Running AutoComplete+ v1.13.3. View ROSS server for update info.")

local pluginGlobalIndex: Types.pluginGlobalIndex = _G["AutoComplete+"]

pluginGlobalIndex.ServiceImportStyle = plugin:GetSetting("ServiceImportStyle") or "PascalCase"
pluginGlobalIndex.ModuleImportStyle = plugin:GetSetting("ModuleImportStyle") or "PascalCase"
pluginGlobalIndex.InstanceImportStyle = plugin:GetSetting("InstanceImportStyle") or "PascalCase"
pluginGlobalIndex.SuggestionCharacter = plugin:GetSetting("SuggestionCharacter")
pluginGlobalIndex.SnippetCharacter = plugin:GetSetting("SnippetCharacter")
pluginGlobalIndex.plugin = plugin

local Transformers = require(script.Transformers)
local UI = require(script.UI)

if pluginGlobalIndex.Connections then
	for _, Connection in pluginGlobalIndex.Connections do
		Connection:Disconnect()
	end
end
pluginGlobalIndex.Connections = {}

local NO_IMPORT_TAG: string = "_NoImport"
local CLIENT_ONLY_TAG: string = "_ClientOnly"
local IMPORTABLE_TAG: string = "_Importable"
local MAXIMUM_LINES_TO_PARSE: number = 100
local SERVICE_PREFIX: string = "[~]"
local MODULE_PREFIX: string = "[;]"
local INSTANCE_PREFIX: string = "[>]"
local DUPLICATE_MODULE_IDENTIFIER: string = "+"

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
local noImportFolders: { Folder } = {}
local moduleScriptOrigins: { Instance } = {
	game.ReplicatedFirst;
	game.ReplicatedStorage;
	game.StarterPlayer.StarterPlayerScripts;
	ServerScriptService;
	ServerStorage
}

for _, service in game:GetChildren() do
	local serviceName = service.Name
	local success, service = pcall(function()
		return game:FindService(serviceName)
	end)

	if success and service then
		services[string.lower(serviceName)] = serviceName
	end
end

local function addItem(item: Instance | ModuleScript): ()
	local isModule = item:IsA("ModuleScript")
	local destination = if isModule then modules else instances
	
	if table.find(destination, item) then
		return
	end
	if isModule then
		if item:HasTag(NO_IMPORT_TAG) then
			return
		end
		for _, folder in noImportFolders do
			if item:IsDescendantOf(folder) then
				return
			end
		end
	end
	
	table.insert(destination, item)
end
local function removeItem(item: Instance | ModuleScript): ()
	local origin = if item:IsA("ModuleScript") then modules else instances
	local found = table.find(origin, item)
	if found then
		table.remove(origin, found)
	end
end
local function registerNoImportInstance(instance: Folder | ModuleScript): ()
	if instance:IsA("Folder") then
		if not table.find(noImportFolders, instance) then
			table.insert(noImportFolders, instance)
		end

		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("ModuleScript") then
				removeItem(descendant)
			end
		end
	elseif instance:IsA("ModuleScript") then
		removeItem(instance)
	end
end

for _, noImportInstance: Folder | ModuleScript in CollectionService:GetTagged(NO_IMPORT_TAG) do
	registerNoImportInstance(noImportInstance)
end
for _, instance: Instance in CollectionService:GetTagged(IMPORTABLE_TAG) do
	addItem(instance)
end

table.insert(pluginGlobalIndex.Connections, CollectionService:GetInstanceAddedSignal(NO_IMPORT_TAG):Connect(function(instance: Folder | ModuleScript)
	registerNoImportInstance(instance)
end))
table.insert(pluginGlobalIndex.Connections, CollectionService:GetInstanceRemovedSignal(NO_IMPORT_TAG):Connect(function(instance: Folder | ModuleScript)
	if instance:IsA("Folder") then
		local found = table.find(noImportFolders, instance)
		if found then
			table.remove(noImportFolders, found)
		end

		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("ModuleScript") and not descendant:HasTag(NO_IMPORT_TAG) then
				addItem(descendant)
			end
		end
	elseif instance:IsA("ModuleScript") then
		addItem(instance)
	end
end))
table.insert(pluginGlobalIndex.Connections, CollectionService:GetInstanceAddedSignal(IMPORTABLE_TAG):Connect(function(instance: Instance)
	if instance:IsA("ModuleScript") then
		return
	end

	addItem(instance)
end))
table.insert(pluginGlobalIndex.Connections, CollectionService:GetInstanceRemovedSignal(IMPORTABLE_TAG):Connect(function(instance: Instance)
	if instance:IsA("ModuleScript") then
		return
	end

	removeItem(instance)
end))

for _, origin in moduleScriptOrigins do
	for _, moduleScript in origin:GetDescendants() do
		if moduleScript:IsA("ModuleScript") then
			addItem(moduleScript)
		end
	end
	table.insert(pluginGlobalIndex.Connections, origin.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ModuleScript") then
			addItem(descendant)
		end
	end))
	table.insert(pluginGlobalIndex.Connections, origin.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("ModuleScript") then
			removeItem(descendant)
		end
	end))
end

local duplicateModules: { [string]: { ModuleScript } } = {}
-- Imports the service/modules script. importType 1 -> Service, 2 -> ModuleScript, 3 -> Instance
local function import(document: ScriptDocument, importName: string, importType: number): number?
	local currentScript: LuaSourceContainer = document:GetScript()
	local documentLines: { string } = string.split(document:GetText(), "\n")
	
	local lastServiceImportGroup: Types.lastImportGroup = { group = {}, all = {}, prePadding = 0 }
	local lastModuleImportGroup: Types.lastImportGroup = { group = {}, all = {}, prePadding = 0 }
	local lastInstanceImportGroup: Types.lastImportGroup = { group = {}, all = {}, prePadding = 0 }
	
	local serviceGroupImportStartLine: number = 1
	local selectedLine: number = document:GetSelection()
	local commentBlocks: number = 0

	for lineNumber, lineContents in documentLines do
		if lineNumber > MAXIMUM_LINES_TO_PARSE or lineNumber > selectedLine then
			break
		end

		if (not lastModuleImportGroup.startLine and not lastServiceImportGroup.startLine) and (commentBlocks > 0 or string.sub(lineContents, 1, 2) == "--") then
			if string.find(lineContents, "%-%-%[%[") then
				commentBlocks += 1
			end
			if string.find(lineContents, "%]%]") then
				commentBlocks -= 1
			end
			serviceGroupImportStartLine += 1
			continue
		end
		if string.sub(lineContents, 1, 1) == "	" then
			continue
		end
		
		local serviceMatch = string.match(lineContents, 'local[%s%w_]+%s=%sgame:GetService%("%w+"%)')
		local moduleMatch = string.match(lineContents, 'local[%s%w_]+%s=%srequire%([%w%p%s]+%)') or string.match(lineContents, 'require%([%w%p%s]+%)')
		local existingImport = serviceMatch or moduleMatch
		-- If neither module & service are imported on this line but a local exists,
		if not existingImport then
			-- check if it's an instance import
			local instanceName = string.find(lineContents, "local") and Transformers.getNameOfImportedItemFromDeclaration(lineContents)
			if instanceName then
				for _, instance in instances do
					if instance.Name == instanceName then
						existingImport = lineContents
						break
					end
				end
			end
		end
		if not existingImport then
			continue
		end
		-- Check if the line contains what we already imported to avoid double importing
		if string.find(Transformers.asNeutralImportName(existingImport), "^" .. Transformers.asNeutralImportName(importName)) then
			return
		end

		-- Otherwise, build up the groups.
		local lastImportGroup = if serviceMatch then lastServiceImportGroup elseif moduleMatch then lastModuleImportGroup else lastInstanceImportGroup
		if not lastImportGroup.startLine then
			lastImportGroup.startLine = lineNumber
		else
			if lastImportGroup.startLine + #lastImportGroup.group < lineNumber then
				-- If the next group is separated from the last, restart from next group
				lastImportGroup.startLine = lineNumber
				lastImportGroup.group = {}
			end
		end

		table.insert(lastImportGroup.all, existingImport)
		table.insert(lastImportGroup.group, existingImport)
	end

	local function importService(serviceName: string?): ()
		if not serviceName then
			return
		end

		-- Import service. No collateral import checks necessary.
		lastServiceImportGroup.receivedImport = true
		table.insert(lastServiceImportGroup.group, `local {Transformers.processVariableName(serviceName, 1)} = game:GetService("{serviceName}")`)

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
		if string.sub(importName, -2, -2) == DUPLICATE_MODULE_IDENTIFIER then
			-- this does mean there is a limit of 9 duplicates
			importModuleScript = duplicateModules[string.sub(importName, 1, -3)][tonumber(string.sub(importName, -1, -1)) :: number]
		else
			local loweredImportName = string.lower(importName)
			for _, moduleScript in modules do
				if string.lower(moduleScript.Name) == loweredImportName then
					importModuleScript = moduleScript
					break
				end
			end
		end

		lastModuleImportGroup.receivedImport = true
		local path, noService = Transformers.transformInstancePathToValid(importModuleScript, currentScript)
		if not noService then
			importService(Transformers.getNeededServiceNameToImportFromModuleOrInstance(importModuleScript, lastServiceImportGroup))
		end

		table.insert(lastModuleImportGroup.group, `local {Transformers.processVariableName(importName, importType)} = require({path})`)

		if not lastModuleImportGroup.startLine then
			-- place after last service import group
			lastModuleImportGroup.startLine = (lastServiceImportGroup.startLine or serviceGroupImportStartLine) + #lastServiceImportGroup.group
			if lastModuleImportGroup.startLine ~= 1 and #lastModuleImportGroup.group == 1 then
				if not (lastServiceImportGroup.receivedImport and #lastServiceImportGroup.group == 1) then
					if documentLines[lastModuleImportGroup.startLine :: any - 1] ~= "" then
						lastModuleImportGroup.prePadding = 1
					end
				end
			end
		end
	elseif importType == 3 then
		local importInstance
		local loweredImportName = string.lower(importName)
		for _, instance in instances do
			if string.lower(instance.Name) == loweredImportName then
				importInstance = instance
				break
			end
		end

		lastInstanceImportGroup.receivedImport = true
		local path, noService = Transformers.transformInstancePathToValid(importInstance, currentScript)
		if not noService then
			importService(Transformers.getNeededServiceNameToImportFromModuleOrInstance(importInstance, lastServiceImportGroup))
		end

		table.insert(lastInstanceImportGroup.group, `local {Transformers.processVariableName(importName, importType)} = {path}`)

		if not lastInstanceImportGroup.startLine then
			local startLine
			if lastModuleImportGroup.startLine then
				startLine = lastModuleImportGroup.startLine + #lastModuleImportGroup.group
			else
				startLine = (lastServiceImportGroup.startLine or serviceGroupImportStartLine) + #lastServiceImportGroup.group
			end
			lastInstanceImportGroup.startLine = startLine

			if startLine ~= 1 and #lastInstanceImportGroup.group == 1 then
				if not (lastServiceImportGroup.receivedImport and #lastServiceImportGroup.group == 1) then
					if documentLines[startLine - 1] ~= "" then
						lastInstanceImportGroup.prePadding = 1
					end
				end
			end
		end
	end

	table.sort(lastServiceImportGroup.group, function(a, b) return #a < #b end)
	table.sort(lastInstanceImportGroup.group, function(a, b) return #a < #b end)

	local numberOfLines: number = document:GetLineCount()
	local lastDocumentLineCount: number = numberOfLines
	local serviceImportMovedLine: boolean = false

	for i = 1, 3 do
		local lastImportGroup: Types.lastImportGroup = if i == 1 then lastServiceImportGroup elseif i == 2 then lastModuleImportGroup else lastInstanceImportGroup
		if not lastImportGroup.receivedImport then
			continue
		end

		local lineCount: number = i == 1 and numberOfLines or document:GetLineCount()
		local lineCountDifference: number = lineCount - lastDocumentLineCount
		local text: string = string.rep("\n", lastImportGroup.prePadding) .. table.concat(lastImportGroup.group, "\n")
		local importGroupStartLine: number = math.min(lastImportGroup.startLine :: number + lineCountDifference, lineCount)
		if serviceImportMovedLine and lastServiceImportGroup.receivedImport and #lastImportGroup.group == 1 then
			-- if double import (service & module | service & instance), decrease by 1 if service caused a line to move
			-- so that the +1 lines are accounted for and the 2nd import is not offset
			importGroupStartLine -= 1
		end

		local nextLineNumber: number = importGroupStartLine + #lastImportGroup.group - 1
		local nextLine: string? = documentLines[nextLineNumber]

		if nextLine and #nextLine > 0 and not (i == importType and string.find(nextLine, importName)) then
			-- if there exists content at point of import, move it up so it doesn't get erased
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
		
		document:EditTextAsync(text, importGroupStartLine, 1, math.min(importGroupStartLine + #lastImportGroup.group, lastDocumentLineCount), 1)
		documentLines = string.split(document:GetText(), "\n")
	end

	-- return the number of lines added to the document
	return document:GetLineCount() - numberOfLines
end

local function generateAutoCompleteSuggestion(item: string | ModuleScript | Instance, locatorPosition: Types.subRange, length: number, duplicateIndex: number?, currentScript: LuaSourceContainer?): Types.autoCompleteSuggestion
	local isService = typeof(item) == "string"
	local isModule = not isService and (item :: Instance):IsA("ModuleScript")
	
	local itemName: string
	local kind: Enum.CompletionItemKind
	local itemType: "service" | "module" | "instance"
	local detailStart: "Get Service:" | "Require:" | "Import:"
	local documentationEnd: string
	local prefix: string
	
	if isService then
		itemName = services[item :: string]
		kind = Enum.CompletionItemKind.Text
		itemType = "service"
		detailStart = "Get Service:"
		documentationEnd = "."
		prefix = SERVICE_PREFIX
	elseif isModule then
		itemName = (item :: ModuleScript).Name .. (duplicateIndex and (DUPLICATE_MODULE_IDENTIFIER .. duplicateIndex) or "")
		kind = Enum.CompletionItemKind.Text
		itemType = "module"
		detailStart = "Require:"
		documentationEnd = ` from {Transformers.transformInstancePathToValid(item :: ModuleScript, currentScript :: LuaSourceContainer)}.`
		prefix = MODULE_PREFIX
	else
		itemName = (item :: Instance).Name
		kind = Enum.CompletionItemKind.EnumMember
		itemType = "instance"
		detailStart = "Import:"
		documentationEnd = ` from {Transformers.transformInstancePathToValid(item :: ModuleScript, currentScript :: LuaSourceContainer)}.`
		prefix = INSTANCE_PREFIX
	end
	
	local suggestion: Types.autoCompleteSuggestion = {
		label = itemName;
		detail = `{detailStart} {itemName}`;
		kind = kind;
		documentation = { value = `Imports the {itemType} [{itemName}]{documentationEnd}` };
		textEdit = {
			insert = {
				start = {
					character = locatorPosition.character - length;
					line = locatorPosition.line
				};
				["end"] = {
					character = locatorPosition.character;
					line = locatorPosition.line
				}
			};
			replace = {
				start = {
					character = locatorPosition.character - length;
					line = locatorPosition.line
				};
				["end"] = {
					character = locatorPosition.character;
					line = locatorPosition.line
				}
			}
		} :: Types.textEdit
	}
	suggestion.textEdit.newText = prefix .. itemName
	
	return suggestion
end

pcall(function()
	ScriptEditorService:DeregisterAutocompleteCallback("AutoComplete")
end)
ScriptEditorService:RegisterAutocompleteCallback("AutoComplete", 1, function(locator, existingSuggestions)
	local document: ScriptDocument = locator.textDocument.document
	if document:IsCommandBar() then return existingSuggestions end

	local currentLine: string = document:GetText(locator.position.line, 1, locator.position.line, locator.position.character)

	local suggestionCharacter: string? = pluginGlobalIndex.SuggestionCharacter
	local currentWordStart: number?, currentWordEnd: number?, currentWord: string

	if suggestionCharacter and suggestionCharacter ~= "" then
		currentWordStart, currentWordEnd = string.find(currentLine, suggestionCharacter .. "([^" .. suggestionCharacter .. "]*)$")
		if not currentWordEnd or locator.position.character <= currentWordEnd then
			return existingSuggestions
		end
		currentWord = string.lower(string.sub(currentLine, currentWordStart :: number + 1, currentWordEnd))
	else
		currentWordStart, currentWordEnd = string.find(currentLine, "%w+$")
		if not (currentWordStart and currentWordEnd) or #existingSuggestions.items == 0 then
			return existingSuggestions
		end

		if currentWordStart > 1 then
			local previousCharacter = string.sub(currentLine, currentWordStart - 1, currentWordStart - 1)
			if previousCharacter ~= "(" and not string.find(previousCharacter, "%s") then
				return existingSuggestions
			end
		end

		currentWord = string.lower(string.sub(currentLine, currentWordStart, currentWordEnd))
	end

	local currentWordLength: number = string.len(currentWord)
	local documentLines: { string } = string.split(document:GetText(), "\n")
	
	-- Gather already imported
	local alreadyImported: { [string]: number } = {}
	for line, lineContents in documentLines do
		if line > MAXIMUM_LINES_TO_PARSE or line > locator.position.line :: number then
			break
		end

		local serviceImport: string? = string.match(lineContents, '%(%s*"(.-)"%s*%)')
		if serviceImport then
			alreadyImported[string.lower(serviceImport)] = line
		else
			local moduleImport = string.find(lineContents, "require") and Transformers.getNameOfImportedItemFromDeclaration(lineContents)
			if moduleImport then
				local variableName = Transformers.getVariableNameFromLine(lineContents)
				if variableName ~= moduleImport and string.find(variableName, "_") then
					alreadyImported[variableName] = line
				else
					alreadyImported[moduleImport] = line
				end
				continue
			end
			
			local instanceImport = string.find(lineContents, "local") and Transformers.getNameOfImportedItemFromDeclaration(lineContents)
			if instanceImport then
				alreadyImported[instanceImport] = line
			end
		end
	end

	local currentScript: LuaSourceContainer = locator.textDocument.script
	local isInServerContext = currentScript:IsDescendantOf(ServerScriptService)
		or currentScript:IsDescendantOf(ServerStorage)

	-- Services
	for lower_serviceName in services do
		if string.find(lower_serviceName, currentWord) and not alreadyImported[lower_serviceName] then
			table.insert(existingSuggestions.items, generateAutoCompleteSuggestion(lower_serviceName, locator.position :: Types.subRange, currentWordLength))
		end
	end

	-- ModuleScripts
	duplicateModules = {}
	local clientOnlyModules = CollectionService:GetTagged(CLIENT_ONLY_TAG)
	for _, moduleScript in modules do
		local moduleScriptName: string = moduleScript.Name
		local neutralName: string = Transformers.asNeutralImportName(moduleScriptName)
		
		if moduleScript == currentScript or not string.find(string.lower(moduleScriptName), currentWord) then
			continue
		end
		
		if isInServerContext then
			if moduleScript:HasTag(CLIENT_ONLY_TAG) then
				continue
			else
				local skip: boolean = false
				for _, clientOnlyModule in clientOnlyModules do
					if moduleScript:IsDescendantOf(clientOnlyModule) then 
						skip = true 
						break 
					end
				end
				if skip then
					continue
				end
			end
		elseif moduleScript:IsDescendantOf(ServerScriptService) or moduleScript:IsDescendantOf(ServerStorage) then
			continue
		end
		
		local duplicateIndex: number?
		if duplicateModules[moduleScriptName] then
			duplicateIndex = #duplicateModules[moduleScriptName] + 1
			table.insert(duplicateModules[moduleScriptName], moduleScript)
			
			if alreadyImported[moduleScriptName .. "_" .. duplicateIndex :: number] or alreadyImported[neutralName .. "_" .. duplicateIndex :: number] then
				continue
			end
		else
			duplicateModules[moduleScriptName] = {}
			
			if alreadyImported[moduleScriptName] or alreadyImported[neutralName] then
				continue
			end
		end
		
		table.insert(existingSuggestions.items, generateAutoCompleteSuggestion(moduleScript, locator.position :: Types.subRange, currentWordLength, duplicateIndex, currentScript))
	end

	-- Instances
	for _, instance in instances do
		if alreadyImported[instance.Name] then
			continue
		end
		if (instance:IsDescendantOf(ServerScriptService) or instance:IsDescendantOf(ServerStorage)) and not isInServerContext then
			continue
		end

		table.insert(existingSuggestions.items, generateAutoCompleteSuggestion(instance, locator.position :: Types.subRange, currentWordLength, nil, currentScript))
	end

	return existingSuggestions
end)

table.insert(pluginGlobalIndex.Connections, ScriptEditorService.TextDocumentDidChange:Connect(function(document, changesArray: { { ["text"]: string, ["range"]: { ["end"]: Types.subRange, ["start"]: Types.subRange } } })
	if document:IsCommandBar() then
		return
	end

	local change = changesArray[1]
	local textLength: number = string.len(change.text)

	if textLength <= 1 then
		-- check if typing normally
		return
	end

	local firstThreeCharacters: string = string.sub(change.text, 1, 3)
	local importType: number
	if firstThreeCharacters == SERVICE_PREFIX then
		importType = 1
	elseif firstThreeCharacters == MODULE_PREFIX then
		importType = 2
	elseif firstThreeCharacters == INSTANCE_PREFIX then
		importType = 3
	else
		return
	end

	local importWhat: string = string.sub(change.text, 4, textLength)
	local lines: { string } = string.split(document:GetText(), "\n")
	local selectedLine: number = document:GetSelection()

	if selectedLine ~= change.range.start.line then
		-- Undo check 1
		return
	end
	for line, lineContents in lines do
		if line > MAXIMUM_LINES_TO_PARSE or line > selectedLine then
			break
		end

		if string.find(lineContents, `local {Transformers.processVariableName(importWhat, importType)} =`, 1, true) then
			-- Undo check 2
			return
		end
	end
	
	local padding: number? = import(document, importWhat, importType)
	if not padding then
		return
	end
	
	local currentLineContents: string = lines[change.range.start.line]
	local newLine: number = change.range.start.line + padding
	local findStart: number?, findEnd: number? = string.find("^" .. Transformers.asNeutralImportName(currentLineContents), Transformers.asNeutralImportName(change.text))
	if not findStart or not findEnd then
		return
	end

	local startCharacterOffset: number = 2
	if pluginGlobalIndex.SuggestionCharacter and pluginGlobalIndex.SuggestionCharacter ~= "" then
		startCharacterOffset = 3
	end

	document:EditTextAsync(
		string.sub(currentLineContents, 1, findStart - startCharacterOffset)
			.. Transformers.processVariableName(importWhat, importType)
			.. string.sub(currentLineContents, findEnd),
		newLine,
		1,
		newLine,
		string.len(string.split(document:GetText(), "\n")[newLine]) + 1
	)

	document:RequestSetSelectionAsync(newLine, string.len(string.sub(currentLineContents, 1, findStart - startCharacterOffset) .. importWhat) + 1)
end))

table.insert(pluginGlobalIndex.Connections, plugin.Unloading:Once(function()
	print("Disabled AutoComplete+")

	for _, Connection in pluginGlobalIndex.Connections do
		Connection:Disconnect()
	end
	pluginGlobalIndex.Connections = {}
	ScriptEditorService:DeregisterAutocompleteCallback("AutoComplete")
end))

UI.Setup()
