--!strict

local module = {}

export type ImportStyle = "PascalCase" | "camelCase" | "snake_case"
export type pluginGlobalIndex = {
	["ServiceImportStyle"]: ImportStyle,
	["ModuleImportStyle"]: ImportStyle,
	["InstanceImportStyle"]: ImportStyle,
	
	["SuggestionCharacter"]: string?,
	["SnippetCharacter"]: string?,
	["Connections"]: { RBXScriptConnection };
	["plugin"]: typeof(plugin)
}
export type subRange = { ["character"]: number, ["line"]: number }
export type textEdit = {
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
export type autoCompleteSuggestion = {
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
export type lastImportGroup = {
	["group"]: { string };
	["all"]: { string };
	["startLine"]: number?;
	["receivedImport"]: true?;
	["prePadding"]: number
}

return module
