local DataGrid = {}
DataGrid.__index = DataGrid

--[[ 
    OLD WE CREATED TABLES INTO PRETTYUI ALL MY OLD CODE SHOULD USE THAT NOW INSTEAD OF THIS.


    This does things. Honestly if anyone is reading this we need sizeable grids as part of default UI. So I can scrape this rubbish.
    Thought seriously It just allows the adding of sizable grids.
]]

--[[ 

    Lazy loading

    The scroll content is still sized for every row (so the scrollbar is right)
    but only the rows inside the viewport (+ a few either side, "overscan") are
    actually built. As you scroll rows that leave the window are destroyed and
    rows that enter it are built. Component IDs get reused after Destroy, so the
    grid's component count stays roughly constant no matter how many rows it has.
]]

local DEFAULT_COLOURS = {
    header = 0x2A231BFF,     -- header row background
    headerText = 0xF2C66DFF, -- header text (gold)
    rowOdd = 0x13110EFF,     -- odd row background (zebra striping)
    rowEven = 0x181510FF,    -- even row background
    text = 0xE7D7B0FF,       -- normal cell text
    empty = 0xC9BEA4FF,      -- "empty" message text
}

-- Helpers

function DataGrid.rect(parent, x, y, width, height, colour)
    local rect = ui.Rectangle.new(parent)

    rect:SetPos(x, y)
    rect:SetSize(width, height)
    rect.fill = true
    rect.rgba = colour
    --rect.clickthrough = true

    return rect
end

function DataGrid.text(parent, value, x, y, width, height, font, colour)
    local text = prettyui.Text.new(parent)

    text:SetPos(x, y)
    text:SetSize(width, height)
    text.content = tostring(value == nil and "" or value)
    text.font = font or id.Font.MUSEO_SANS_13PT_REGULAR
    text.rgba = colour or DEFAULT_COLOURS.text
    text.maxLines = 1
    text.alignVertical = ui.AlignMode.CENTRE
    --text.clickthrough = true

    return text
end

local function safeDestroy(thing)
    if thing == nil then return end
    pcall(function() thing:Destroy() end)
end

-- Debug logging. Turn on per grid with options.debug = true, or for every grid with DataGrid.debug = true
DataGrid.debug = false

function DataGrid:debugLog(message, ...)
    if not (self.debug or DataGrid.debug) then return end

    local text = string.format(message, ...)

    if type(log) == "function" then
        log("[" .. self.name .. "] " .. text)
    else
        print("[" .. self.name .. "] " .. text)
    end
end

-- Count rows currently built, and the components they use (render() cells count as 1, see buildRow)
function DataGrid:renderedStats()
    local rowCount, componentCount = 0, 0

    for _, rendered in pairs(self.renderedRows) do
        rowCount = rowCount + 1
        componentCount = componentCount + (rendered.components or 0)
    end

    return rowCount, componentCount
end


--[[ Main Constructor
    parent - Window/Component we want to attach to.
    options - So we Can customise the details of the Grid
        overscan - extra rows built above/below the visible area (default 2)
        debug    - true logs what the lazy loader builds/destroys (or set DataGrid.debug = true for every grid)
        name     - label used in the debug logs handy when you have more than one grid
        emptyText - what to show when there are no rows (default "Nothing to show.")

]]
function DataGrid.new(parent, options)
    options = options or {}
    assert(options.columns and #options.columns > 0, "DataGrid needs at least one column")

    local grid = setmetatable({}, DataGrid)

    grid.parent = parent
    grid.columns = options.columns
    grid.rows = options.rows or {}

    grid.x = options.x or 0
    grid.y = options.y or 0
    grid.width = options.width or 600
    grid.height = options.height or 400
    grid.rowHeight = options.rowHeight or 36
    grid.headerHeight = options.headerHeight or 28
    grid.scrollbarWidth = options.scrollbarWidth or 16
    grid.padding = options.padding or 8
    grid.emptyText = options.emptyText or "Nothing to show."
    grid.overscan = options.overscan or 2
    grid.debug = options.debug or true
    grid.name = options.name or "DataGrid"

    grid.colours = DEFAULT_COLOURS

    -- Lazy loading state
    grid.renderedRows = {}   -- [rowIndex] = { layer = rowLayer, handles = {...} }
    grid.firstRendered = nil
    grid.lastRendered = nil
    grid.rendering = false
    grid.suspendRender = false

    grid:buildFrame()
    grid:buildBody()

    return grid
end

--[[
    keepScroll - true keeps the current scroll position (e.g. a row's data changed)
    otherwise we jump back to the top (e.g. a new filter was picked).
]]
function DataGrid:setRows(rows, keepScroll)
    self.rows = rows or {}
    self:buildBody(keepScroll)
end

function DataGrid:setSize(width, height)
    self.width = width or self.width
    self.height = height or self.height
end

function DataGrid:setPos(x, y)
    self.x = x or self.x
    self.y = y or self.y

    if self.root ~= nil then self.root:SetPos(self.x, self.y) end
end

function DataGrid:setRowHeight(rowHeight, headerHeight)
    self.rowHeight = rowHeight or self.rowHeight
    self.headerHeight = headerHeight or self.headerHeight
    self:rebuild()
end

function DataGrid:rebuild()
    self:teardown()
    self:buildFrame()
    self:buildBody()
end

function DataGrid:Destroy()
    self:teardown()
end

-- Building Functions

--[[ Returns rowLayer, handles, componentCount
    handles - anything a column's render() returned that has a Destroy (or is a
    function). These get cleaned up when the row scrolls out of view, so prettyui
    components / PofEvent subscriptions made inside render() don't leak.
    componentCount - components this function created (debug only). Whatever a
    render() makes inside its cell isn't visible to us, so each cell counts as 1.
]]
function DataGrid.buildRow(parent, rowData, columns, rowHeight, padding, bgColour, textColour)
    local totalWidth = 0
    local handles = {}
    local componentCount = 2 -- row layer + background rect

    for _, col in ipairs(columns) do
        totalWidth = totalWidth + (col.width or 100)
    end

    --Main Row container
    local rowLayer = ui.Layer.new(parent)

    rowLayer:SetSize(totalWidth, rowHeight)
    --This draws a rectangle the full size of the layer
    DataGrid.rect(rowLayer, 0, 0, totalWidth, rowHeight, bgColour)

    local currentX = 0

    for _, col in ipairs(columns) do
        local colWidth = col.width or 100

        --Check if the column has a custom render (Normally a button Ect)
        if col.render ~= nil then
            local cell = ui.Layer.new(rowLayer)

            cell:SetPos(currentX, 0)
            cell:SetSize(colWidth, rowHeight)

            local handle = col.render(cell, rowData, colWidth, rowHeight)

            if handle ~= nil then table.insert(handles, handle) end

            componentCount = componentCount + 1
        else
            local value = rowData[col.key]

            if col.format ~= nil then value = col.format(value, rowData) end

            DataGrid.text(
                rowLayer,
                value,
                currentX + padding,
                0,
                colWidth - (padding * 2),
                rowHeight,
                nil,
                textColour
            )

            componentCount = componentCount + 1
        end

        currentX = currentX + colWidth
    end

    return rowLayer, handles, componentCount
end

function DataGrid:buildFrame()
    self.gridWidth = self.width - self.scrollbarWidth

    --Root layer, everything lives inside this, so destorying it destorys everything
    self.root = ui.Layer.new(self.parent)

    self.root:SetPos(self.x, self.y)
    self.root:SetSize(self.width, self.height)
    self.root.clickthrough = true

    --Header Bar that stays at the top
    self.headerArea = ui.Layer.new(self.root)

    self.headerArea:SetPos(0, 0)
    self.headerArea:SetSize(self.width, self.headerHeight)
    self.headerArea.clickthrough = true

    self.bodyArea = ui.Layer.new(self.root)

    self.bodyArea:SetPos(0, self.headerHeight)
    self.bodyArea:SetSize(self.width, self.height - self.headerHeight)
    self.bodyArea.clickthrough = true

    DataGrid.rect(self.headerArea, 0, 0, self.gridWidth, self.headerHeight, self.colours.header)

    local currentX = 0

    for _, col in ipairs(self.columns) do
        local colWidth = col.width or 100

        DataGrid.text(
            self.headerArea,
            col.label or "",
            currentX + self.padding,
            0,
            colWidth - (self.padding * 2),
            self.headerHeight,
            id.Font.MUSEO_SANS_13PT_BOLD,
            self.colours.headerText
        )

        currentX = currentX + colWidth
    end
end

-- Creates the scroll view once and hooks its scroll updates.
function DataGrid:ensureScrollView()
    if self.scrollView ~= nil then return self.scrollView end

    local viewHeight = self.height - self.headerHeight

    self.scrollView = prettyui.SimpleView.new(self.bodyArea, {
        width = self.width,
        height = viewHeight,
        contentHeight = viewHeight,
        scrollable = true,
        scrollStep = self.rowHeight
    })

    --[[ prettyui's Scroll calls self.onLayout(self) at the end of every
        SetScrollPosition - wheel, arrows, track click, thumb drag and resizes all
        go through it. SimpleView doesn't expose it as an option, so we set it on
        the instance (chaining anything already there).
    ]]
    local previousOnLayout = self.scrollView.onLayout

    self.scrollView.onLayout = function(view)
        if previousOnLayout ~= nil then previousOnLayout(view) end

        self:renderVisibleRows()
    end

    return self.scrollView
end

function DataGrid:buildBody(keepScroll)
    self:clearRenderedRows()

    safeDestroy(self.emptyLabel)
    self.emptyLabel = nil

    local view = self:ensureScrollView()
    local viewHeight = self.height - self.headerHeight

    self:debugLog(
        "setRows: %d rows, ~%d fit on screen, overscan %d, keepScroll=%s",
        #self.rows, math.ceil(viewHeight / self.rowHeight), self.overscan, tostring(keepScroll == true)
    )

    -- Size the content for ALL rows (scrollbar stays honest) without building any yet
    self.suspendRender = true
    view:SetContentHeight(math.max(viewHeight, #self.rows * self.rowHeight))
    if not keepScroll then view:SetScrollPosition(0) end
    self.suspendRender = false

    if #self.rows == 0 then
        self.emptyLabel = DataGrid.text(view.content, self.emptyText, 12, 0, self.gridWidth - 24, self.rowHeight, id.Font.MUSEO_SANS_13PT_BOLD, self.colours.empty)
        return
    end

    self:renderVisibleRows()
end

-- Works out which rows should exist right now, builds the new ones, destroys the old ones.
function DataGrid:renderVisibleRows()
    local view = self.scrollView

    if view == nil or self.rendering or self.suspendRender then return end

    local total = #self.rows

    if total == 0 then return end

    local scrollY = view.scrollY or 0
    local viewHeight = view.height or (self.height - self.headerHeight)

    local first = math.max(1, math.floor(scrollY / self.rowHeight) + 1 - self.overscan)
    local last = math.min(total, math.ceil((scrollY + viewHeight) / self.rowHeight) + self.overscan)

    -- Scrolled less than a row - nothing to do
    if first == self.firstRendered and last == self.lastRendered then return end

    self.rendering = true

    local destroyedCount, builtCount = 0, 0

    local ok, err = pcall(function()

        for rowIndex in pairs(self.renderedRows) do
            if rowIndex < first or rowIndex > last then
                self:destroyRenderedRow(rowIndex)
                destroyedCount = destroyedCount + 1
            end
        end

        for rowIndex = first, last do
            if self.renderedRows[rowIndex] == nil then
                self:buildRowAt(rowIndex)
                builtCount = builtCount + 1
            end
        end
    end)

    self.firstRendered = first
    self.lastRendered = last
    self.rendering = false

    if not ok then error(err, 0) end

    if self.debug or DataGrid.debug then self:debugCheck(scrollY, first, last, builtCount, destroyedCount) end
end

-- Logs what changed and checks nothing exists outside the window
function DataGrid:debugCheck(scrollY, first, last, builtCount, destroyedCount)
    local total = #self.rows
    local rowCount, componentCount = self:renderedStats()
    local expectedRows = last - first + 1

    -- Rough cost if every row was built the old way (uses the average of the rows we have)
    local perRow = rowCount > 0 and (componentCount / rowCount) or 0
    local fullCost = math.floor(perRow * total + 0.5)

    self:debugLog(
        "scrollY=%d | rows %d-%d of %d | +%d built, -%d destroyed | alive: %d rows, ~%d components (all rows would be ~%d)",
        scrollY, first, last, total, builtCount, destroyedCount, rowCount, componentCount, fullCost
    )

    -- Sanity checks - these should never print
    if rowCount ~= expectedRows then
        self:debugLog("WARNING: expected %d rows alive but found %d", expectedRows, rowCount)
    end

    for rowIndex in pairs(self.renderedRows) do
        if rowIndex < first or rowIndex > last then
            self:debugLog("WARNING: row %d is still built but outside the window %d-%d", rowIndex, first, last)
        end
    end
end

function DataGrid:buildRowAt(rowIndex)
    local colour = (rowIndex % 2 == 1) and self.colours.rowOdd or self.colours.rowEven

    local rowLayer, handles, componentCount = DataGrid.buildRow(
        self.scrollView.content,
        self.rows[rowIndex],
        self.columns,
        self.rowHeight,
        self.padding,
        colour,
        self.colours.text
    )

    -- Absolute position in the full height content so it lines up with the scrollbar
    rowLayer:SetPos(0, (rowIndex - 1) * self.rowHeight)

    self.renderedRows[rowIndex] = { layer = rowLayer, handles = handles, components = componentCount }
end

function DataGrid:destroyRenderedRow(rowIndex)
    local rendered = self.renderedRows[rowIndex]

    if rendered == nil then return end

    for _, handle in ipairs(rendered.handles) do
        if type(handle) == "function" then
            pcall(handle)
        elseif type(handle) == "table" and handle.Destroy ~= nil then
            safeDestroy(handle)
        end
    end

    safeDestroy(rendered.layer)

    self.renderedRows[rowIndex] = nil
end

function DataGrid:clearRenderedRows()
    for rowIndex in pairs(self.renderedRows) do
        self:destroyRenderedRow(rowIndex)
    end

    self.renderedRows = {}
    self.firstRendered = nil
    self.lastRendered = nil
end

function DataGrid:refreshVisibleRows()
    self:clearRenderedRows()
    self:renderVisibleRows()
end

function DataGrid:teardown()
    local rowCount = self:renderedStats()

    self:debugLog("teardown: destroying %d built rows", rowCount)

    self:clearRenderedRows()

    safeDestroy(self.emptyLabel)
    self.emptyLabel = nil

    if self.scrollView ~= nil then
        self.scrollView.onLayout = nil
        safeDestroy(self.scrollView)

        self.scrollView = nil
    end

    safeDestroy(self.root)
    self.root = nil

    self.headerArea = nil
    self.bodyArea = nil
end

return DataGrid