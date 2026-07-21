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
	
		An advanced inventory system that integrates both stackable and unstackable items, bindable-based handler
		
--]]


--// OOP //--

local MetaInventory = {} --// inv class
local MetaItem = {} --// item class 
MetaInventory.__index = MetaInventory --// if not found in self, check here
MetaItem.__index = MetaItem --// if not found in self, check here

--// Modules //--

local Networker = require(game.ReplicatedStorage.Network.Networker) --// remote event handler
local ITEMS_DATA = require(game.ServerStorage.Data.Items) --// items config
local Storage = require(game.ServerStorage.Modules.Storage_Framework.Storage_Framework) --// profilestore wrapper and data hadling
local Events = require(script.Parent.Inventory_Events) --// remote events' names for this module
local cooldown_handler = require(game.ReplicatedStorage.Shared.Modules.Cooldown_System) --// handles cooldowns through ID
local HB_Handler = require(script.Parent.Hotbar_Handler) --// handles hotbar
local tool_system = require(game.ServerStorage.Modules.Tool_System.Tool_System) --// automatic tool system (doesnt use roblox tools)

export type Inventory = {
	Player: number,
	Items: {[string]: serialized_Item},
	IDS: {[string]: number},
	bytes: number,
	Events: Events.events,
	Connections: {[string]: RBXScriptConnection},

	CheckItem: (self: Inventory, itemName: string) -> {}, --// method returns nothing
	GetID: (self: Inventory, itemName: string, stackable: boolean) -> string, --// method returns a string
	NewItem: (self: Inventory, itemName: string, amount: number, loop: boolean?) -> serialized_Item | {[string]: serialized_Item}, --//method returns serialized item (base item of inventory)
	GetItem: (self: Inventory, itemID: string) -> serialized_Item, --//method also returns serialized item
	DestroyItem: (self: Inventory, itemID: string) -> (),--//method  returns nothing
	Cleanup: (self: Inventory) -> (),--//method returns nothing
	Synchronize: (self: Inventory) -> (),--//method returns nothing
	Clear: (self: Inventory) -> (),
	HandleUse: (self: Inventory, item: serialized_Item, defData: {[string]: any}, args: {[string]: any}) -> (),
	HandleAddHotbar: (self: Inventory, item: serialized_Item) -> (),
	SetupConnections: (self: Inventory) -> {[string]: RBXScriptConnection}, --//method returns a connections table
	CleanupConnections: (self: Inventory) -> (),
} --// type for inventory

export type serialized_Item = {
	Player: number,
	Name: string,
	Amount: number,
	Type: string,
	Stackable: boolean,
	Tool: {[string]: any}, --// its a table containing a tool and properties (custom tool system)
	Tool_Event: RBXScriptConnection,
	Events: "pointer", --// basically points to the events
	ID: string,

	Increment: (self: serialized_Item, amount: number) -> number, --//method returns a number
	Decrement: (self: serialized_Item, amount: number) -> number, --//method returns a numbwer
	GetDefaultData: (self: serialized_Item) -> {[string]: any}, --// method returns a table containing the item main config
	Destroy: (self: serialized_Item) -> (),
	SetupToolConnection: (self: serialized_Item) -> (),
	CleanupToolConnections: (self: serialized_Item) -> (),
} --// type for items

function Inventory_Handler.OnPlayerAdded(plr: Player) --// once plr is added, run this (automatically run by the LOADER module, but it is the same as doing game.players.onplayeradded())

	local plrTable = Storage.PlayerData[plr.UserId] --// gets the plr data
	Inventory_Handler.NewInventory(plr.UserId, plrTable.Inventory)
end

function Inventory_Handler.OnPlayerRemoving(plr: Player) --// once plr is removed, run this (automatically run by the LOADER module, but it is the same as doing game.players.onplayerremoving() and game:bindtoclose)

	local inv = Inventory_Handler.GetInventory(plr.UserId)
	inv:Cleanup() --// cleans up all connections to prevent memory leaks
end

function Inventory_Handler.NewInventory(plrID: number, data: Inventory?): Inventory
	if data and not data.Player then
		data = nil
	end --// if the old data doesnt have "Player" then its a invalid data so nil

	local plrTable = Storage.PlayerData[plrID] --// plr data

	local self = data or {
		Player = plrID,
		Items = {},
		IDS = {},
	} :: Inventory

	self.Events = Events.New(plrID) --// creates new inventory events, its basically a dictionary of events {[string]: string}
	plrTable.Inventory = self --// reconciles inventory

	setmetatable(self, MetaInventory) --// attaches class
	self:SetupConnections()
	self:Synchronize() --// synching with client, runs every time to make sure the clients know which items exist

	return self
end

function Inventory_Handler.GetInventory(plrID: number): Inventory
	return Storage.PlayerData[plrID].Inventory --// returns plr inventory
end

function Inventory_Handler.GetEvents(plrID: number): Events.events --// we get the dictionary of inventory events
	return Inventory_Handler.GetInventory(plrID).Events
end

--// INVENTORY CLASS //--

function MetaInventory:Cleanup()

	self:CleanupConnections()
	for _, itemData in self.Items do
		itemData:CleanupToolConnections()
	end
end

function MetaInventory:Synchronize() --// synchs with client for GUI related purposes
	for _, data in self.Items do
		self.Events:Fire("new_item", data)
	end
end

function MetaInventory:Clear() --// clears all items of the inventory
	for id, data in self.Items do
		self.Events:Fire("destroy_item", data)
		self.Items[id] = nil
	end
end

function MetaInventory:CheckItem(itemName: string) --// check if it exists in the CONFIG
	return ITEMS_DATA[itemName]
end

function MetaInventory:GetID(itemName: string, stackable: boolean?): string
	if stackable then --// if its stackable, why need an ID? js return the default name
		return itemName
	end

	if not self.IDS[itemName] then --// creates id, or updates it
		self.IDS[itemName] = 0
	else
		self.IDS[itemName] += 1
	end
	return itemName..self.IDS[itemName]
end

function MetaInventory:NewItem(itemName: string, amount: number, loop: boolean) --// loop is if its an unstackable item
	local self = self :: Inventory --// types check inventory
	amount = amount or 1

	local defData = self:CheckItem(itemName) --//if its not in a config then warn 
	if not defData then
		warn("item is not available in game: ", itemName)
		return
	end

	local stackable = defData.Stackable
	if not stackable and not loop then --// used to create multiple unstackable items
		local items = {}
		for i = 1, amount do
			local item = self:NewItem(itemName, 1, true)
			items[item.ID] = item
		end
		return items
	end

--// since loop is true, (if its unstackable), we can create the item now

	local ID = self:GetID(itemName, stackable) --// gets id
	local existing = self.Items[ID] --// checks if exist
	if existing then
		if stackable then existing:Increment(amount) end --/ if its stackable then increment it
		return existing
	end

	--//otherwise js create it new

	local itemData = {
		Player = self.Player,
		Name = itemName,
		Amount = amount,
		ID = ID,
		Stackable = stackable,
		Type = defData.Item_Type, --// type of item (tool, non-tool)
	} :: serialized_Item

	self.Items[ID] = setmetatable(itemData, MetaItem) --// atttaches item class
	self.Events:Fire("new_item", itemData) --// creates a new item, remote for the client

	return itemData
end

function MetaInventory:GetItem(itemID: string): serialized_Item --// gets item in the plr inventory
	local item = self.Items[itemID]
	if not item then
		warn("item not found!")
	end
	return item
end

function MetaInventory:DestroyItem(itemID: string) --// destroys item in plr inventory
	local item = self:GetItem(itemID)
	if not item then
		warn("item doesn't exist")
		return
	end

	item:CleanupToolConnections()

	self.Events:Fire("destroy_item", item) --// for client GUI purposes
	self.Items[itemID] = nil
end

function MetaInventory:HandleUse(item: serialized_Item, defData, args) --// defdata is config
	local self = self :: Inventory --// type checks inventory

	if not defData.IsTool then
		item:Decrement(args.Amount) --// if its not a tool, it means its a consumable
		return
	end

	local bp = tool_system.GetBackpack(self.Player) --// gets tool backpack, its basically a folder that owns these custom tools
	if not bp then return end

	if bp:GetTool(item.ID) then --// gets tool using item ID
		if item.Tool:CheckIfEquipped() then
			item.Tool:Unequip() --// automatically unequips all other tools to prevent conflicts (its in the method itself, not here)
		else
			item.Tool:Equip()
		end

		--// equips it if its unequipped and unequips it if its equipped
		return
	end

	item.Tool = bp:NewTool(item.Name, item.ID) --// if it doesnt exist then we creatre a new tool
	item:SetupToolConnection()
end

function MetaInventory:HandleAddHotbar(item: serialized_Item) --// hotbar helper
	local self = self :: Inventory
	local hbItem = HB_Handler.GetItem(self.Player, item.ID)

	if hbItem then
		hbItem:Destroy()
	else
		HB_Handler.NewItem(self.Player, item.Name, item.ID, item) --// creates a new hb item
	end
end

function MetaInventory:SetupConnections() --//new conns for each inventory
	local self = self :: Inventory
	local connections = {}

	--[[
		how the networker works:
			Networker.OnEvent() --> gets all the events it should connect to based on the "towho" arguments which is a table that contains all types of remotes (events, functions, unreliable, etc)
			they go by their alias {
				[RE] = RemoteEvent
				[RF] = RemoteFunction
			},
			the networker automatically detects which script is running it using RunService:IsClient() and connects to the designated events (.OnClientEvent and .OnServerEvent)

			Networker.Fire() --> fires all the events based on "towho" which is the same thing as before and the networker also detects
			which script is running it using RunService:IsClient() and connects to the designated events (:FireClient, :FireServer, :FireAllClients())

			every method has server authority and rate limits
	--]]

	connections.manage_item_cl = Networker.OnEvent(self.Events.manage_item_from_client, {"RE"}, function(plr, args) --// .onevent returns .OnServerEvent, therefore a connection, || manage_item includes "equip" and "unequip"
		if not cooldown_handler.CheckCooldown("use_item_"..self.Player, 1) then return end --// checks cooldown, first arg = id, second arg = amount (if the cooldown exists already, it substracts time elapsed and deletes it)

		local item = self:GetItem(args.ID) --// specific ID
		if not item then return end --// if the item doesnt exist then return 

		local defData = ITEMS_DATA[item.Name] --// CONFIG DESIGNATED for the specific item name

		if args.Type == "use" then --// detects which type of packet this was
			self:HandleUse(item, defData, args)
		elseif args.Type == "destroy" then
			item:Destroy()
		elseif args.Type == "add_hotbar" then
			self:HandleAddHotbar(item)
		end
	end)

	connections.get_item = Networker.OnEvent(self.Events.get_item_from_client, {"RF"}, function(plr, args) --// gets an item from the server through remote functions
		if not args.ID then return end
		return self:GetItem(args.ID)
	end)

	self.Connections = connections --// attaches connections for cleanup
	return connections
end

function MetaInventory:CleanupConnections() --// cleanup connections
	if self.Connections then
		for _, conn in self.Connections do --//disconnect all connections
			conn:Disconnect()
		end

		self.Connections = nil
	end
end

function MetaItem:Increment(amount: number) --// increments an item

	amount = amount or 1
	self.Amount += amount

	Inventory_Handler.GetEvents(self.Player):Fire("update_item", self) --// updates item for client
	return self.Amount
end

function MetaItem:Decrement(amount: number?)
	amount = amount or 1
	self.Amount -= amount

	if self.Tool then
		task.spawn(self.Tool.PlaySequence, self.Tool, "Activate") --// if its a tool we play the tool animation
	end

	if self.Amount <= 0 then
		return self:Destroy()
	end

	Inventory_Handler.GetEvents(self.Player):Fire("update_item", self)
	return self.Amount
end

function MetaItem:GetDefaultData() --// also gets item config
	return ITEMS_DATA[self.Name]
end

function MetaItem:Destroy() --// destroys an item
	local self = self :: serialized_Item

	if self.Stackable and self.Amount > 0 then
		self.Amount = 0
		Inventory_Handler.GetEvents(self.Player):Fire("update_item", self) --// updates it for client (theres a type that tells the client if its destroyed)
	end

	if self.Tool then --// destroyd tool if it exists
		self.Tool:Destroy()
		self.Tool = nil
	end

	Inventory_Handler.GetInventory(self.Player):DestroyItem(self.ID) --// removes it from inventory
end

function MetaItem:SetupToolConnection() --// setups a bindable event connection where the server retrieves when a client activates a tool (its a bindable cuz its fired by a remote first then by the own tool system through a bindable(
	if not self.Tool then return end

	self.Tool_Event = Networker.OnEvent(self.Player.."Tool_Activate", {"BE"}, function(args)
		if args.Data.ID == self.ID then
			self:Decrement()
		end
	end)
end

function MetaItem:CleanupToolConnections() --// cleans up tool connections
	if not self.Tool then return end

	if self.Tool_Event then
		self.Tool_Event:Disconnect()
	end
end

return Inventory_Handler
