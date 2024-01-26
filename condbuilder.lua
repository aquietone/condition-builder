-- Macro Condition Builder v0.2 - aquietone
-- Uses some basic pattern matching to provide autocompletion with filtering under specific patterns.
-- 1. When input ends "${" then it will provide short list of hardcoded TLOs commonly used in conditions.
-- 2. When input ends in "${TLONAME." then it will provide all available members of the datatype returned by ${TLONAME}.
-- 3. When input ends in "${TLONAME[params]." then it will provide all available members of the datatype returned by ${TLONAME[params]}.
-- 4. When input ends in "${TLONAME.MEMBER[params]." then it will return all available members of the datatype returned by ${TLONAME.MEMBER[params]}.
-- 5. When input ends in "${TLONAME.MEMBER." then it will return all available members of the datatype returned by ${TLONAME.MEMBER}.
-- Anything further nested will not populate available options.

local mq = require('mq')
local imgui = require('ImGui')

local isOpen = true

-- Random sampling of TLOs that seem more likely to be used in conditions
local TLOOptions = {
    'Me', 'Target', 'Spawn', 'SpawnCount', 'Spell', 'Math',
    'Cursor', 'Defined', 'FindItem', 'FindItemCount', 'Group', 'Raid',
    'If', 'Select', 'Range', 'String', 'Int', 'Bool',
}

local buttons = {
    '${', '}', '[', ']', '(', ')', '.', '!', '&&', '||', '==', '!=', 'Equal', 'NotEqual', 'NULL'
}

local examples = {
    '${Target.Named}',
    '${Me.PctHPs} > 70 && ${Me.PctMana} < 60',
    '${SpawnCount[pc radius 60]} > 3',
    '${Target.CleanName.Equal[Fippy Darkpaw]}',
    '${Select[${Target.Class.ShortName},CLR,DRU,SHM]}',
    '(${Me.XTarget} > 2 || ${Target.Named}) && ${BurnAllNamed}',
    '!${Me.Buff[Illusion Benefit Greater Jann].ID}',
    '${SpawnCount[${Me.Name}`s pet]} > 0',
    '${Me.XTarget} > 0',
}

local function drawReferenceLink()
    if imgui.Button('\xee\x89\x90 TLO Reference') then
        os.execute('start https://docs.macroquest.org/reference/top-level-objects/')
    end
end

local COMBO_POPUP_FLAGS = bit32.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize, ImGuiWindowFlags.ChildWindow)
---Draw a combo box with filterable options
---@param label string #The label for the combo
---@param current_value string #The current selected value or filter text for the combo
---@param options table #The selectable options for the combo
---@return string,boolean #Return the selected value or partial filter text as well as whether the value changed
local function ComboFiltered(label, current_value, options)
    local avail = imgui.GetContentRegionAvailVec()
    imgui.SetNextItemWidth(avail.x - ImGui.CalcTextSize(label))
    local result, changed = imgui.InputText(label, current_value, ImGuiInputTextFlags.EnterReturnsTrue)
    local active = imgui.IsItemActive()
    local activated = imgui.IsItemActivated()
    if activated then imgui.OpenPopup('##combopopup'..label) end
    if #options > 0 then
        local itemRectMinX, _ = imgui.GetItemRectMin()
        local _, itemRectMaxY = imgui.GetItemRectMax()
        imgui.SetNextWindowPos(itemRectMinX, itemRectMaxY)
        imgui.SetNextWindowSize(avail.x - ImGui.CalcTextSize(label), #options > 20 and imgui.GetTextLineHeight()*20 or -1)
        if imgui.BeginPopup('##combopopup'..label, COMBO_POPUP_FLAGS) then
            for _,value in ipairs(options) do
                if imgui.Selectable(value) then
                    if options.filterType == 'tlo' then
                        local prefix = current_value:match('(.*%${)%w*$')
                        result = prefix .. value
                    elseif options.filterType == 'member' then
                        local prefix = current_value:match('(.*%${%w*%.)%w*$')
                        result = prefix .. value
                    elseif options.filterType == 'memberafterarg' then
                        local prefix = current_value:match('(.*%${%w*%[[%w%d%s=]*%]%.)%w*$')
                        result = prefix .. value
                    elseif options.filterType == 'memberaftermember' then
                        local prefix = current_value:match('(.*%${%w*%.%w*%.)%w*$')
                        result = prefix .. value
                    elseif options.filterType == 'memberaftermemberwithparam' then
                        local prefix = current_value:match('(.*%${%w*%.%w*%[[%w%d%s=]*%]%.)%w*$')
                        result = prefix .. value
                    end
                end
            end
            if changed or (not active and not imgui.IsWindowFocused()) then
                imgui.CloseCurrentPopup()
            end
            imgui.EndPopup()
        end
    end
    return result, current_value ~= result
end

local function addMembersForDataType(dataTypeName, input, options)
    -- Get DataType definition for the type name
    local dataType = mq.TLO.Type(dataTypeName)
    for i=0,300 do
        local tloMember = dataType.Member(i)()
        -- Iterate over the members and populate the dropdown with entries matching the input following the ${\w*.
        if tloMember and tloMember:find(input) then
            table.insert(options, tloMember)
            options[tloMember] = true
        end
    end
    -- Repeat for inherited DataType
    if dataType.InheritedType() then
        local parentDataTypeName = mq.TLO.Type(dataType.InheritedType)
        for i=0,300 do
            local tloMember = parentDataTypeName.Member(i)()
            if tloMember and not options[tloMember] and tloMember:find(input) then
                table.insert(options, tloMember)
            end
        end
    end
end

local function populateFilter(expression)
    local options = {}
    -- Match value ending with pattern ${\w* as possible TLO name
    local tloInput = expression:match('.*%${(%w*)$')
    if tloInput then
        -- Populate dropdown with hardcoded list of TLOs to select from
        for _,tlo in ipairs(TLOOptions) do
            -- Filter the list based on the input following the ${
            if tlo:find(tloInput) then
                table.insert(options, tlo)
            end
        end
        options.filterType = 'tlo'
        return options
    end
    -- Match value ending with pattern ${\w*.\w* as possible TLO Member naem
    local tloName, memberInput = expression:match('.*%${(%w*)%.(%w*)$')
    if memberInput and tloName then
        -- Get string name of the TLO data type
        local dataTypeName = mq.gettype(mq.TLO[tloName])
        if dataTypeName then
            addMembersForDataType(dataTypeName, memberInput, options)
            options.filterType = 'member'
            table.sort(options)
            return options
        end
    end
    -- Match values ending with pattern ${\w*[\w\d*].\w* as possible TLO Member name after TLO parameters
    local tloName, param, memberInput = expression:match('.*%${(%w*)%[([%w%d%s=]*)%]%.(%w*)$')
    if tloName and param and memberInput then
        local dataTypeName = mq.gettype(mq.TLO[tloName](param))
        if dataTypeName then
            addMembersForDataType(dataTypeName, memberInput, options)
            options.filterType = 'memberafterarg'
            table.sort(options)
            return options
        end
    end
    -- Match values ending with pattern ${\w*.\w*.\w* as possible TLO Member name after TLO member
    local tloName, firstTloMember, memberInput = expression:match('.*%${(%w*)%.(%w*)%.(%w*)$')
    if tloName and firstTloMember and memberInput then
        local dataTypeName = mq.gettype(mq.TLO[tloName][firstTloMember])
        if dataTypeName then
            addMembersForDataType(dataTypeName, memberInput, options)
            options.filterType = 'memberaftermember'
            table.sort(options)
            return options
        end
    end
    -- Match values ending with pattern ${\w*.\w*[\w\d*].\w* as possible TLO Member name after TLO member
    local tloName, firstTloMember, param, memberInput = expression:match('.*%${(%w*)%.(%w*)%[([%w%d%s=]*)%]%.(%w*)$')
    if tloName and firstTloMember and param and memberInput then
        local dataTypeName = mq.gettype(mq.TLO[tloName][firstTloMember](param))
        if dataTypeName then
            addMembersForDataType(dataTypeName, memberInput, options)
            options.filterType = 'memberaftermemberwithparam'
            table.sort(options)
            return options
        end
    end
    return options
end

local function drawButtons(expression)
    local result = expression
    imgui.Separator()
    for i,button in ipairs(buttons) do
        if imgui.Button(button) then
            result = expression .. button
        end
        if i % 9 ~= 0 then
            imgui.SameLine()
        end
    end
    return result
end

local function drawExamples(expression)
    local result = expression
    imgui.Separator()
    if imgui.BeginCombo('Examples', '') then
        for i,example in ipairs(examples) do
            if imgui.Selectable(example) then
                result = example
            end
        end
        imgui.EndCombo()
    end
    return result
end

local function drawOutput(expression)
    imgui.Separator()
    imgui.Text('Output')
    if imgui.BeginChild('outputchild', -1, -1, ImGuiChildFlags.Border, 0) then
        imgui.Text(mq.parse(expression))
    end
    imgui.EndChild()
end

local function expressionBuilder(expression, filteredOptions)
    local isDraw = true
    isOpen, isDraw = imgui.Begin("Macro Condition Builder", isOpen)
    if isDraw then
        drawReferenceLink()
        local result, changed = ComboFiltered('Condition', expression, filteredOptions)
        if changed then
            expression = result
            filteredOptions = populateFilter(expression)
        end
        expression = drawButtons(expression)
        expression = drawExamples(expression)
        drawOutput(expression)
    end
    imgui.End()
    return expression, filteredOptions
end

local function main()
    local filteredOptions = {filterType = 'tlo'}
    local expression = ''
    mq.imgui.init('condbuilder', function() expression, filteredOptions = expressionBuilder(expression, filteredOptions) end)

    while isOpen do
        mq.delay(1000)
    end
end

main()