--!strict

local Types = require(script.Parent.Parent.Parent.Types)

local pluginGlobalIndex: Types.pluginGlobalIndex = _G["AutoComplete+"]

local module = {}

function module.setupDropper(DropperButton: TextButton, DropperOptionTemplate: TextButton, SettingName: string): ()
	local DropperOptions: { TextButton } = {}
	
	local function ClearOptions(): ()
		for _, DropperOption in DropperOptions do
			DropperOption:Destroy()
		end
		
		DropperButton:RemoveTag("Active")
	end
	
	DropperButton.MouseButton1Click:Connect(function()
		if DropperButton:HasTag("Active") then
			ClearOptions()
			return
		end
		
		DropperButton:AddTag("Active")
		
		local Choices: { string } = string.split(DropperButton:GetAttribute("Options"), ",")
		
		for i, Choice in Choices do
			local DropperOption = DropperOptionTemplate:Clone()
			DropperOption.Text = Choice
			DropperOption.ZIndex = 9
			DropperOption.Position = UDim2.fromScale(0, i)
			DropperOption.Parent = DropperButton.Parent
			
			DropperOption.MouseButton1Click:Connect(function()
				ClearOptions()
				
				pluginGlobalIndex[SettingName] = Choice
				pluginGlobalIndex.plugin:SetSetting(SettingName, Choice);
				(DropperButton.Parent :: TextLabel).Text = Choice
			end)
			
			table.insert(DropperOptions, DropperOption)
		end
	end)
end

return module
