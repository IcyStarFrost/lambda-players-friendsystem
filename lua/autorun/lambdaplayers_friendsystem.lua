local IsValid = IsValid
local table_Count = table.Count
local pairs = pairs
local RandomPairs = RandomPairs
local random = math.random
local table_Add = table.Add
local VectorRand = VectorRand
local net = net
local string_find = string.find
local string_Explode = string.Explode
local player_GetAll = player.GetAll
local string_lower = string.lower
local table_IsEmpty = table.IsEmpty
local debugoverlay = debugoverlay
local dev = GetConVar( "developer" )
local uiscale = GetConVar( "lambdaplayers_uiscale" )

-- Friend System Convars

hook.Add( "LambdaOnConvarsCreated", "lambdafriendsystemConvars", function()

    CreateLambdaConvar( "lambdaplayers_friend_enabled", 1, true, false, false, "Enables the friend system that will allow Lambda Players to be friends with each other or with players and treat them as such", 0, 1, { name = "Enable Friend System", type = "Bool", category = "Friend System" } )
    CreateLambdaConvar( "lambdaplayers_friend_drawhalo", 1, true, true, false, "If friends should have a halo around them", 0, 1, { name = "Draw Halos", type = "Bool", category = "Friend System" } )
    CreateLambdaConvar( "lambdaplayers_friend_friendcount", 3, true, false, false, "How many friends a Lambda/Real Player can have", 1, 30, { name = "Friend Count", type = "Slider", decimals = 0, category = "Friend System" } )
    CreateLambdaConvar( "lambdaplayers_friend_friendchance", 5, true, false, false, "The chance a Lambda Player will spawn as someone's friend", 1, 100, { name = "Friend Chance", type = "Slider", decimals = 0, category = "Friend System" } )

end )


-- Helper function
local function GetPlayers()
    local lambda = GetLambdaPlayers()
    local realplayers = player_GetAll()
    table_Add( lambda, realplayers )
    return lambda
end 

local function Initialize( self, wepent )
    if CLIENT then return end

    self.l_friends = {}

    -- If we are friends with ent
    function self:IsFriendsWith( ent )
        return IsValid( ent ) and IsValid( self.l_friends[ ent:GetCreationID() ] )
    end

    -- If we can be friends with ent
    function self:CanBeFriendsWith( ent )
        ent.l_friends = ent.l_friends or {}
        return ( ent.IsLambdaPlayer or ent:IsPlayer() ) and table_Count( self.l_friends ) < GetConVar( "lambdaplayers_friend_friendcount" ):GetInt() and table_Count( ent.l_friends ) < GetConVar( "lambdaplayers_friend_friendcount" ):GetInt() and !self:IsFriendsWith( ent )
    end
    
    -- Return a random friend we have
    function self:GetRandomFriend()
        for k, v in RandomPairs( self.l_friends ) do return v end
    end

    -- Add ent to our friends list
    function self:AddFriend( ent, forceadd )
        ent.l_friends = ent.l_friends or {} -- Make sure this table exists
        if self:IsFriendsWith( ent ) or !self:CanBeFriendsWith( ent ) and !forceadd or !GetConVar( "lambdaplayers_friend_enabled" ):GetBool() then return end
        
        self.l_friends[ ent:GetCreationID() ] = ent -- Add ent to our friends list
        ent.l_friends[ self:GetCreationID() ] = self -- Add ourselves to ent's friends list

        net.Start( "lambdaplayerfriendsystem_addfriend" )
        net.WriteUInt( self:GetCreationID(), 32 )
        net.WriteEntity( self )
        net.WriteEntity( ent )
        net.Broadcast()

        net.Start( "lambdaplayerfriendsystem_addfriend" )
        net.WriteUInt( ent:GetCreationID(), 32 )
        net.WriteEntity( ent )
        net.WriteEntity( self )
        net.Broadcast()

        -- Become friends with ent's friends
        for ID, entfriend in pairs( ent.l_friends ) do
            if entfriend == self or !self:CanBeFriendsWith( entfriend ) then continue end -- We can't be friends with em
            entfriend.l_friends = entfriend.l_friends or {}

            net.Start( "lambdaplayerfriendsystem_addfriend" )
            net.WriteUInt( self:GetCreationID(), 32 )
            net.WriteEntity( self )
            net.WriteEntity( entfriend)
            net.Broadcast()

            net.Start( "lambdaplayerfriendsystem_addfriend" )
            net.WriteUInt( entfriend:GetCreationID(), 32 )
            net.WriteEntity( entfriend )
            net.WriteEntity( self )
            net.Broadcast()


            self.l_friends[ entfriend:GetCreationID() ] = entfriend -- Add entfriend to our friends list
            entfriend.l_friends[ self:GetCreationID() ] = self -- Add ourselves to entfriend's friends list
        end
    end
    
    -- Remove ent from our friends list
    function self:RemoveFriend( ent )
        if !self:IsFriendsWith( ent ) then return end

        net.Start( "lambdaplayerfriendsystem_removefriend" )
        net.WriteUInt( self:GetCreationID(), 32 )
        net.WriteEntity( ent )
        net.Broadcast()

        net.Start( "lambdaplayerfriendsystem_removefriend" )
        net.WriteUInt( ent:GetCreationID(), 32 )
        net.WriteEntity( self )
        net.Broadcast()


        self.l_friends[ ent:GetCreationID() ] = nil -- Remove ent from our friend list
        ent.l_friends[ self:GetCreationID() ] = nil -- Remove ourselves from ent's friends list
    end

    -- Randomly set someone as our friend if it passes the chance
    if random( 0, 100 ) < GetConVar( "lambdaplayers_friend_friendchance" ):GetInt() then
        for k, v in RandomPairs( GetPlayers() ) do
            if v == self or self:IsFriendsWith( v ) or !self:CanBeFriendsWith( v ) then continue end
            self:AddFriend( v )
            break
        end
    end

end


local function Think( self, wepent )
    if CLIENT then return end

    -- Debug lines that visualizes friends
    if dev:GetBool() then
        for k, v in pairs( self.l_friends ) do
            debugoverlay.Line( self:WorldSpaceCenter(), v:WorldSpaceCenter(), 0, self:GetPlyColor():ToColor(), true )
        end
    end

end

-- Prevent damage to friends
local function OnInjured( self, info )
    if self:IsFriendsWith( info:GetAttacker() ) then return true end
end

local function OnMove( self, pos, isonnavmesh )
    if ( self:GetState() != "Idle" and self:GetState() != "FindTarget" ) or random( 0, 100 ) < 30 then return end
    local friend = self:GetRandomFriend()
    
    if IsValid( friend ) then
        local navarea = navmesh.GetNavArea( friend:WorldSpaceCenter(), 500 )
        local pos = IsValid( navarea ) and navarea:GetClosestPointOnArea( friend:GetPos() + VectorRand( -500, 500 ) ) or friend:GetPos() + VectorRand( -500, 500 )
        self:RecomputePath( pos ) 
    end
end

-- Defend our friends if we see the attacker
local function OnOtherInjured( self, victim, info, took )
    if !took or info:GetAttacker() == self then return end

    if self:IsFriendsWith( victim ) and !LambdaIsValid( self:GetEnemy() ) and self:CanTarget( info:GetAttacker() ) and self:CanSee( info:GetAttacker() ) then 
        self:AttackTarget( info:GetAttacker() ) 
    elseif self:IsFriendsWith( info:GetAttacker() ) and !LambdaIsValid( self:GetEnemy() ) and self:CanTarget( victim ) and self:CanSee( victim ) then 
        self:AttackTarget( victim ) 
    end
end

local function ProfilePanelLoad()
    LambdaCreateProfileSetting( "DTextEntry", "l_permafriends", "Friend System", function( pnl, parent )
        pnl:SetZPos( 100 )

        local lbl = LAMBDAPANELS:CreateLabel( "[ Permanent Friend ]\nInput a Lambda Name or a Real Player's name to make them this profile's permanent friend. You can seperate names with commas , Example: Eve,Blizz", parent, TOP )
        lbl:SetSize( 100, 100 )
        lbl:Dock( TOP )
        lbl:SetWrap( true )
        lbl:SetZPos( 99 )
    end )
end

local function GetPlayerByName( name )
    for k, v in ipairs( player.GetAll() ) do
        if string_lower( v:Nick() ) == string_lower( name ) then return v end
    end
end

local function HandleProfiles( self, info )
    local permafriendsstring = self.l_permafriends
    if !permafriendsstring then return end
    local names = string_find( permafriendsstring, "," ) and string_Explode( ",", permafriendsstring ) or { permafriendsstring }

    for k, name in ipairs( names ) do
        local ply = GetPlayerByName( name )

        if IsValid( ply ) then 
            self:AddFriend( ply, true )
        else
            ply = GetLambdaPlayerByName( name )
            if IsValid( ply ) then self:AddFriend( ply, true ) end
        end
    end
end


hook.Add( "LambdaOnProfileApplied", "lambdafriendsystemhandleprofiles", HandleProfiles )
hook.Add( "LambdaOnProfilePanelLoaded", "lambdafriendsystemprofilepanel", ProfilePanelLoad )
hook.Add( "LambdaOnBeginMove", "lambdafriendsystemonbeginmove", OnMove )
hook.Add( "LambdaOnOtherInjured", "lambdafriendsystemonotherinjured", OnOtherInjured )
hook.Add( "LambdaOnInjured", "lambdafriendsystemoninjured", OnInjured )
hook.Add( "LambdaOnThink", "lambdafriendsystemthink", Think )
hook.Add( "LambdaOnInitialize", "lambdafriendsysteminit", Initialize )

if SERVER then

    util.AddNetworkString( "lambdaplayerfriendsystem_addfriend" )
    util.AddNetworkString( "lambdaplayerfriendsystem_removefriend" )

    -- Remove our friends
    local function OnRemove( self )
        for ID, friend in pairs( self.l_friends ) do
            self:RemoveFriend( friend )
        end
    end

    local function CanTarget( self, target ) -- Do not attack friends
        if self:IsFriendsWith( target ) then return true end
    end

    local function EntityTakeDamage( ent, info )
        local attacker = info:GetAttacker()
        if ent:IsPlayer() and attacker.IsLambdaPlayer then
            if attacker:IsFriendsWith( ent ) then return true end
        end
    end

    hook.Add("EntityTakeDamage", "lambdafriendsystemtakedamage", EntityTakeDamage )
    hook.Add( "LambdaOnRemove", "lambdafriendsystemOnRemove", OnRemove )
    hook.Add( "LambdaCanTarget", "lambdafriendsystemtarget",  CanTarget )

elseif CLIENT then
    local AddHalo = halo.Add
    local clientcolor = Color( 255, 145, 0 )
    local tracetable = {}
    local Trace = util.TraceLine
    local DrawText = draw.DrawText
    local uiscale = GetConVar( "lambdaplayers_uiscale" )

    local function UpdateFont()
        surface.CreateFont( "lambdaplayers_friendfont", {
            font = "ChatFont",
            size = LambdaScreenScale( 7 + uiscale:GetFloat() ),
            weight = 0,
            shadow = true
        })
    end
    UpdateFont()
    cvars.AddChangeCallback( "lambdaplayers_uiscale", UpdateFont, "lambdafriendsystemfonts" )

    -- Draw the outlines
    hook.Add( "PreDrawHalos", "lambdafriendsystemhalos", function()
        if !GetConVar( "lambdaplayers_friend_drawhalo" ):GetBool() then return end
        local friends = LocalPlayer().l_friends
        if friends then
            for k, v in pairs( friends ) do
                if !LambdaIsValid( v ) or !v:IsBeingDrawn() then continue end
                AddHalo( { v }, v:GetDisplayColor(), 3, 3, 1, true, false )
            end
        end
    end )

    -- Display Friend tag and who the Lambda is friends with
    hook.Add( "HUDPaint", "lambdafriendsystemhud", function()
        local friends = LocalPlayer().l_friends

        if friends then
            
            for k, v in pairs( friends ) do
                if !LambdaIsValid( v ) or !v:IsBeingDrawn() then continue end

                tracetable.start = LocalPlayer():EyePos()
                tracetable.endpos = v:WorldSpaceCenter()
                tracetable.filter = LocalPlayer()
                local result = Trace( tracetable )

                if result.Entity != v then continue end
                local vectoscreen = ( v:GetPos() + v:OBBCenter() * 2.5 ):ToScreen()
                if !vectoscreen.visible then continue end

                DrawText( "Friend", "lambdaplayers_friendfont", vectoscreen.x, vectoscreen.y, v:GetDisplayColor(), TEXT_ALIGN_CENTER )
            end

        end


        local sw, sh = ScrW(), ScrH()
        local traceent = LocalPlayer():GetEyeTrace().Entity

        if LambdaIsValid( traceent ) and traceent.IsLambdaPlayer then
            local name = traceent:GetLambdaName()
            local buildstring = "Friends With: "
            local friends = traceent.l_friends

            if friends and !table_IsEmpty( friends ) then
                local count = 0
                local others = 0
                for k, v in pairs( friends ) do
                    if !IsValid( v ) then friends[ k ] = nil continue end 
                    count = count + 1

                    if count > 3 then others = others + 1 continue end

                    buildstring = buildstring .. v:Nick() .. ( table_Count( friends ) > count and ", " or "" )
                end
                buildstring = others > 0 and buildstring .. " and " .. ( others ) .. ( others > 1 and " others" or " other") or buildstring
                DrawText( buildstring, "lambdaplayers_displayname", ( sw / 2 ), ( sh / 1.77 ) + LambdaScreenScale( 1 + uiscale:GetFloat() ), traceent:GetDisplayColor(), TEXT_ALIGN_CENTER)
            end
        end

    end )

    net.Receive( "lambdaplayerfriendsystem_addfriend", function() 
        local id = net.ReadUInt( 32 )
        local lambda = net.ReadEntity()
        local receiver = net.ReadEntity()
        receiver.l_friends = receiver.l_friends or {}

        if !receiver.l_friends then return end
        receiver.l_friends[ id ] = lambda
    end )

    net.Receive( "lambdaplayerfriendsystem_removefriend", function() 
        local id = net.ReadUInt( 32 )
        local receiver = net.ReadEntity()

        if !receiver.l_friends then return end
        receiver.l_friends[ id ] = nil
    end )

    
end