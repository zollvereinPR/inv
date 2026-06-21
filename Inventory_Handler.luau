local Inventory_Handler = {}

--[[
	Made by:
	
		Discord: zollverein.
		Roblox: Admin0408,
		Github: zollvereinPR
		
	Disclaimer:
		
		This module requires many other modules, so the game provided in the link isn't a byproduct of ONLY this module.
		The events module is here: https://github.com/zollvereinPR/inv/blob/main/Inventory_Events.luau.
		
	Short Description:
	
		An advanced inventory system that integrates both stackable and unstackable items, signal-based handler.
		
--]]

--// OOP //--

local MetaInventory = {}
local MetaItem = {}
MetaInventory.__index = MetaInventory
MetaItem.__index = MetaItem

--// Modules //--

local Networker = require(game.ReplicatedStorage.Network.Networker)
local Cooldown = require(game.ReplicatedStorage.Shared.Modules.Cooldown_System)
local ITEMS_DATA = require(game.ServerStorage.Data.Items)
local Storage = require(game.ServerStorage.Modules.Storage_Framework.Storage_Framework)
local Events = require(script.Parent.Inventory_Events)
local misc = require(game.ReplicatedStorage.Shared.Packages.Misc_Package)
local cooldown_handler = require(game.ReplicatedStorage.Shared.Modules.Cooldown_System)
local HB_Handler = require(script.Parent.Hotbar_Handler)
local tool_system = require(game.ServerStorage.Modules.Tool_System.Tool_System)

--// Types //--

export type Inventory = {

	Player: number,
	Items: {},
	IDS: {},
	bytes: number,
	Events: Events.events,

	--// Methods //--
	CheckItem:   (self: Inventory, itemName: string) -> {},
	GetID:       (self: Inventory, itemName: string) -> string,
	NewItem:     (self: Inventory, itemName: string, amount: number?) -> serialized_Item,
	GetItem:     (self: Inventory, itemName: string) -> serialized_Item,
	DestroyItem: (self: Inventory, itemID: string) -> (),
}

export type serialized_Item = {

	Player: number,
	Name: string,
	Amount: number,
	Type: string,
	Events: "pointer",
	ID: string,
}

----------------
--// System //--
----------------

function Inventory_Handler.BulkDestroy(tab: {})
	
	if typeof(tab) == "table" then
		
		for key, val in pairs(tab) do
			
			if typeof(val) == "table" then
				
				val:Destroy()
			end
		end
	end
end

function Inventory_Handler.OnPlayerAdded(plr)
	
	task.wait(5)

	local plrTable = Storage.PlayerData[plr.UserId]
	local data = plrTable.Inventory
	local newInv = Inventory_Handler.NewInventory(plr.UserId, data)
end

function Inventory_Handler.NewInventory(plrID, data): Inventory

	data = data or nil
	if data then
		
		if not data["Player"] then
			
			data = nil
		end
	end
	
	local plrTable = Storage.PlayerData[plrID]
	
	local self = data or {
		Player = plrID,
		Items = {},
		IDS = {},
		bytes = 0,
		Events = Events.New(plrID)
	} :: Inventory
	
	
	self.Events = Events.New(plrID)
	
	plrTable.Inventory = self
	
	setmetatable(self, MetaInventory)
	self:SetupConnections()
	
	self:Clear()

	task.spawn(function()
		
		while true do
			task.wait(5)

			local item = self:NewItem("health_potion", 1)
		end
	end)
	
	task.wait(3)
	
	--item:Decrement()
	
	warn(self, "SETUP INVENTORY!")
	
	return self
end

function Inventory_Handler.GetInventory(plrID): Inventory

	local plrTable = Storage.PlayerData[plrID]
	return plrTable.Inventory
end

function Inventory_Handler.GetEvents(plrID): Events.events
	
	local inv = Inventory_Handler.GetInventory(plrID)
	return inv.Events
end

-------------------------
--// Inventory Class //--
-------------------------

function MetaInventory:Synchronize()
	
	for id, data in pairs(self.Items) do
		
		self.Events:Fire("new_item", data)
	end
end

function MetaInventory:Clear()

	for id, data in pairs(self.Items) do

		self.Events:Fire("destroy_item", data)
		
		self.Items[id] = nil
	end
end

function MetaInventory:CheckItem(itemName)

	return ITEMS_DATA[itemName]
end

function MetaInventory:GetID(itemName, stackable)

	if not stackable then
		
		if not self.IDS[itemName] then

			self.IDS[itemName] = 0
		else
			self.IDS[itemName] += 1
		end

		return itemName..self.IDS[itemName]
	else
		return itemName
	end
end

function MetaInventory:NewItem(itemName, amount, loop): serialized_Item

	amount = amount or 1
	loop = loop or false

	local self = self :: Inventory
	local defData = self:CheckItem(itemName)
	local tab = {}
	
	if defData then
		local stackable = defData.Stackable
		if not stackable then
			
			if not loop then
				
				for i = 1, amount do

					local item = self:NewItem(itemName, 1, true)
					tab[item.ID] = item
				end
				
				return tab
			end
		end

		local ID = self:GetID(itemName, stackable)
		if not self.Items[ID] then
			
			local itemData = { 
				Player = self.Player,
				Name = itemName,
				Amount = amount,
				ID = ID,
				Stackable = stackable,
				Type = defData["Item_Type"]
			}:: serialized_Item

			self.Items[ID] = setmetatable(itemData, MetaItem)

			print("successfully created new item!")
			
			warn(itemData)

			self.Events:Fire("new_item", itemData)

			return itemData
		else
			
			if stackable then
				
				local itemData = self.Items[ID]
				setmetatable(itemData, MetaItem)
				itemData:Increment(amount)
			end
		end
	else
		warn("item is not available in game: ", itemName)
	end
end

function MetaInventory:GetItem(itemName): serialized_Item

	local itemData = self.Items[itemName]
	if not itemData then warn("item not found!") return end

	return itemData
end

function MetaInventory:DestroyItem(itemID, amount)

	local item = self:GetItem(itemID)
	amount = amount or 1
	
	if item then
		
		self.Events:Fire("destroy_item", item)

		self.Items[itemID] = nil
		
		print("successfully destroyed item!")
		
	else
		warn("item doesnt exist alread")
	end
end

function MetaInventory:SetupConnections()
	
	local self = self :: Inventory
	
	local connections = {}
	connections.manage_item_cl = Networker.OnEvent(self.Events.manage_item_from_client, {"RE"}, function(plr, args)
		
		
		if not cooldown_handler.CheckCooldown("use_item", 1) then return end
		
		local item = self:GetItem(args.ID)
		if not item then error() end
		
		local defdata = ITEMS_DATA[item.Name]
		
		if args.Type == "use" then
			
			if not defdata.IsTool then
				
				item:Decrement(args.Amount)
			else
				local bp = tool_system.GetBackpack(self.Player)
				if not bp then return end

				if bp:GetTool(item.ID) then
					
					if item.Tool:CheckIfEquipped() then

						item.Tool:Unequip()
					else
						item.Tool:Equip()
					end
					
					warn("CREATIGN TOOL")
					
				else
					local tooldata = bp:NewTool(item.Name, item.ID)
					item.Tool = tooldata
					
					item:SetupToolConnection()
				end
			end
		elseif args.Type == "destroy" then
			
			item:Destroy()
		elseif args.Type == "add_hotbar" then
			
			local hotbar = HB_Handler.GetHotbar(self.Player)
			if HB_Handler.GetItem(self.Player, args.ID) then
				
				local hbitem = HB_Handler.GetItem(self.Player, args.ID):Destroy()
			else
				HB_Handler.NewItem(self.Player, item.Name, item.ID, item)
			end
		end
	end)
	
	connections.get_item = Networker.OnEvent(self.Events.get_item_from_client, {"RF"}, function(plr, args)
		
		local ID = args.ID
		if not ID then error() end
		
		local item = self:GetItem(ID)
		if item then return item end
	end)
	
	return connections
end

--------------------
--// Item Class //--
--------------------

function MetaItem:Increment(amount)
	
	amount = amount or 1
	
	self["Amount"] += amount
	
	local ev = Inventory_Handler.GetEvents(self.Player)
	ev:Fire("update_item", self)
	
	return self["Amount"]
end

function MetaItem:Decrement(amount)

	amount = amount or 1

	self["Amount"] -= amount

	local tool = self.Tool
	if tool then

		task.spawn(function()
			tool:PlaySequence("Activate")
		end)
		tool:PlayVFXSequence("Activate")
	end

	
	if self["Amount"] <= 0 then
		
		return self:Destroy()
	end

	local ev = Inventory_Handler.GetEvents(self.Player)
	ev:Fire("update_item", self)
	
	
	return self["Amount"]
end

function MetaItem:GetDefaultData()
	
	local itemName = self.Name
	return ITEMS_DATA[itemName]
end

function MetaItem:Destroy()
	
	if self.Tool then
		
		self.Tool:Destroy()
	end
	
	local inv = Inventory_Handler.GetInventory(self.Player)
	if self.Stackable then
		
		if self.Amount > 0 then
			
			self:Decrement(self.Amount)
		else
			inv:DestroyItem(self.ID)
		end
	else
		inv:DestroyItem(self.ID)
	end
end

function MetaItem:SetupToolConnection()
	
	if self.Tool then
		
		self.Tool_Event = Networker.OnEvent(self.Player.."Tool_Activate", {"BE"}, function(args)
			
			local ID = args.Data.ID
			if ID == self.ID then
				
				self:Decrement()
			end
		end)
	end
end

return Inventory_Handler
