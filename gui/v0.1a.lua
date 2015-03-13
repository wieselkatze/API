local function validColor( clr, default )
    clr = tonumber( clr )
    return clr and clr > 0 and clr < 32769 and clr or default
end

function setLen( str, len )
    if #str:gsub( "[&$][%xzlr]", "" ) <= len then
        return str
    else
        local pos = 1
        local sub = 1

        while pos < #str do
            if str:sub( pos ):match( "^[&$][%xzlr]" ) then
                pos = pos + 2
            else
                pos = pos + 1
                sub = sub + 1
            end

            if sub == len-1 then
                return str:sub( 1, pos ) .. "."
            end
        end

        return ""
    end
end

local function tryWrite( text, pattern )
    local match = text:match( pattern )

    if match then
        if match:match( "[&$]%x" ) then
            term[ match:sub( 1, 1 ) == "&" and "setTextColor" or "setBackgroundColor" ]( math.pow( 2, 15-tonumber( match:sub( 2 ), 16 ) ) )
        else
            term.write( match )
        end

        return text:sub( #match+1 )
    end
end

function advPrint( text, y1, x1, x2 )
    y1 = y1 or 1
    x1 = x1 or 1
    x2 = x2 or term.getSize()
    local x3 = x1

    local ort = text:match( "^[&$]([zlr])" )

    if ort then
        if ort == "z" then
            x3 = math.floor( ( ( x2-x1+1 )-#text:gsub( "[&$][%xzlr]", "" )+1 )/2+0.5 )+x1-1
        elseif ort == "l" then
            x3 = x1
        elseif ort == "r" then
            x3 = x2-#text:gsub( "[&$][%xzlr]", "" )+1
        end

        text = text:sub( 3 )
    end

    term.setCursorPos( x3, y1 )

    while #text > 0 do
        text = tryWrite( text, "^[&$]%x" ) or
            tryWrite( text, "^%w+" ) or
            tryWrite( text, "^." )
    end
end

function area( arg )
    assert( arg.x1 and arg.x2 and arg.y1 and arg.y2 )

    local new = {
        draw = function( self )
            term.setBackgroundColor( self.bg )
            for i = self.y1, self.y2 do
                term.setCursorPos( self.x1, i )
                term.write( ( self.char ):rep( self.x2-self.x1+1 ) )
            end
        end;

        evHandle = function()
        end;

        bg = validColor( arg.bg, 256 );
        char = arg.char and #arg.char == 1 and arg.char or " ";

        x1 = math.min( arg.x1, arg.x2 );
        x2 = math.max( arg.x1, arg.x2 );
        y1 = math.min( arg.y1, arg.y2 );
        y2 = math.max( arg.y1, arg.y2 );
    }

    return new
end

function read( arg )

    assert( arg.x1 and arg.x2 and arg.y1, "Too few arguments" )

    local new = {
        draw = function( self )
            local txt = self.txt:sub( self.xScroll+1, self.xScroll+self.x2-self.x1+1 )
            term.setCursorPos( self.x1, self.y1 )
            term.setBackgroundColor( self.bg )
            term.setTextColor( self.fg )

            term.write( txt )
            term.write( ( " " ):rep( self.x2-self.x1-#txt+1 ) )
            term.setCursorPos( self.x1+self.xPos-1, self.y1 )
        end;

        setCursor = function( self, x1, forceUpdate )
            if x1 ~= self.xScroll+self.xPos then
                local update = false
                if x1 < self.xScroll+1 then
                    self.xPos = 1
                    self.xScroll = math.max( 0, x1-1 )
                    update = true
                elseif x1 > self.xScroll+self.x2-self.x1+1 then
                    self.xPos = self.x2-self.x1+1
                    self.xScroll = math.min( #self.txt+1, x1 ) - self.xPos
                    update = true
                else
                    self.xPos = math.min( #self.txt+1, x1-self.xScroll )
                end

                if update or forceUpdate then
                    self:draw()
                else
                    term.setCursorPos( self.x1+self.xPos-1, self.y1 )
                end
            end
        end;

        insert = function( self, txt )
            self.txt = self.txt:sub( 1, self.xScroll+self.xPos-1 ) .. txt .. self.txt:sub( self.xScroll+self.xPos )
        end;

        evHandle = function( self, ... )
            local e = { ... }

            if e[1] == "char" or e[1] == "paste" then
                if self.filter then
                    e[2] = self.filter( e[2] )
                end

                self:insert( e[2] or "" )
                self:setCursor( self.xScroll+self.xPos+#( e[2] or "" ), true )
            elseif e[1] == "key" then
                if e[2] == 14 then
                    self.txt = self.txt:sub( 1, self.xScroll+self.xPos-2 ) .. self.txt:sub( self.xScroll+self.xPos )
                    self:setCursor( self.xScroll+self.xPos-1, true )
                elseif e[2] == 28 or e[2] == 15 then
                    os.queueEvent( "advread_complete", self.txt )
                elseif e[2] == 199 then
                    self:setCursor( 1 )
                elseif e[2] == 203 then
                    self:setCursor( self.xPos+self.xScroll-1 )
                elseif e[2] == 205 then
                    self:setCursor( self.xPos+self.xScroll+1 )
                elseif e[2] == 207 then
                    self:setCursor( #self.txt+1 )
                elseif e[2] == 211 then
                    self.txt = self.txt:sub( self.xScroll+self.xPos ) .. self.txt:sub( self.xScroll+self.xPos+2 )
                    self:draw()
                end
            elseif e[1] == "mouse_click" then
                self.lastX = nil

                if e[3] >= self.x1 and e[3] <= self.x2 and e[4] == self.y1 then
                    self.lastX = e[3]
                    self:setCursor( self.xScroll+e[3]-self.x1+1 )
                end
            elseif e[1] == "mouse_drag" then
                if self.lastX then
                    local dir = self.lastX - e[3]
                    self.lastX = e[3]
                    if self.xScroll+dir > -1 and self.xScroll+self.x2-self.x1+dir < #self.txt+1 then
                        self.xScroll = self.xScroll + dir
                        self:draw()
                    end
                end
            end
        end;

        focus = function( self, cursorBlink )
            term.setCursorPos( self.x1+self.xPos-1, self.y1 )

            if cursorBlink == true then
                term.setCursorBlink( true )
            end
        end;

        x1 = arg.x1;
        x2 = arg.x2;
        y1 = arg.y1;
        filter = type( arg.filter ) == "function" and arg.filter;
        txt = arg.txt or "";
        xScroll = arg.txt and math.max( 0, #arg.txt-arg.x2+arg.x1-1 ) or 0;
        xPos = arg.txt and math.min( arg.x2-arg.x1+1, #arg.txt+1 ) or 1;
        bg = validColor( arg.bg, 256 );
        fg = validColor( arg.fg, 32768 );

        isElement = true;
    }

    return new
end

function list( arg )
    assert( arg.x1 and arg.x2 and arg.y1 and arg.y2, "Too few arguments" )

    for k, v in pairs( arg.txt ) do
        if type( v ) == "string" then
            arg.txt[ k ] = {
                txt = v;
                fg = validColor( arg.unselfg, 32768 );
                bg = validColor( arg.unselbg, 256 );
                selfg = validColor( arg.selfg, 32768 );
                selbg = validColor( arg.selbg, 8 );
            }
        elseif type( v ) == "table" then
            arg.txt[ k ] = {
                txt = v.txt or "";
                fg = validColor( v.fg, 32768 );
                bg = validColor( v.bg, 256 );
                selfg = validColor( v.selfg, 32768 );
                selbg = validColor( v.selbg, 8 );
            }

            for k1, v1 in pairs( v ) do
                if not arg.txt[ k ][ k1 ] then
                    arg.txt[ k ][ k1 ] = v1
                end
            end
        end
    end

    local new = {
        drawBar = function( self )
            if not self.barType then
                local maxlen, overhang, pos, len = self.y2-self.y1-self.margin*2+1, #self.txt-self.y2+self.y1+self.margin*2

                if #self.txt < maxlen then
                    len = maxlen
                else
                    len = math.ceil( maxlen/overhang )
                end

                if self.spos == overhang then
                    pos = maxlen-len+1
                elseif self.spos == 1 then
                    pos = 1
                elseif #self.txt > maxlen and self.spos > 1 then
                    pos = math.ceil( ( self.spos-1 )*( 1/( overhang-1 ) )*( self.y2-self.y1-self.margin*2-len ) )+1
                end

                for i = 1, maxlen do
                    term.setCursorPos( self.x2-self.margin, self.y1+self.margin+i-1 )

                    if i >= pos and i < pos+len then
                        term.setBackgroundColor( self.scrollfg )
                    else
                        term.setBackgroundColor( self.scrollbg )
                    end

                    term.write( " " )
                end
            else
                term.setCursorPos( self.x2-self.margin, self.y1+self.margin )
                term.setTextColor( self.spos > 1 and self.scrollfg or self.scrollbg )
                term.write( "^" )
                term.setCursorPos( self.x2-self.margin, self.y2-self.margin )
                term.setTextColor( self.spos < #self.txt-self.y2+self.y1+self.margin*2 and self.scrollfg or self.scrollbg )
                term.write( "v" )
            end
        end;

        drawOptions = function( self )
            for i = 1, math.min( self.y2-self.y1-self.margin*2+1, #self.txt ) do
                term.setCursorPos( self.x1+self.margin, self.y1+self.margin+i-1 )
                term.setBackgroundColor( self.sel == i+self.spos-1 and self.txt[ i+self.spos-1 ].selbg or self.txt[ i+self.spos-1 ].bg )
                term.setTextColor( self.sel == i+self.spos-1 and self.txt[ i+self.spos-1 ].selfg or self.txt[ i+self.spos-1 ].fg )
                term.setCursorPos( self.x1+self.margin, self.y1+self.margin+i-1 )

                term.write( ( " " ):rep( self.x2-self.x1-self.margin*2-1 ) )

                local txt = self.setLen( self.txt[ i+self.spos-1 ].txt, self.x2-self.x1-self.margin*2-1 )

                self.advPrint( txt, self.y1+self.margin+i-1, self.x1+self.margin, self.x2-self.margin )
            end
        end;

        draw = function( self )
            term.setBackgroundColor( self.bg )

            for i = self.y1, self.y2 do
                term.setCursorPos( self.x1, i )
                term.write( ( " " ):rep( self.x2-self.x1+1 ) )
            end

            self:drawBar()
            self:drawOptions()
        end;

        evHandle = function( self, ... )
            local e = { ... }

            if e[1] == "mouse_click" then
                self.lastY = nil

                if e[3] >= self.x1+self.margin and e[3] < self.x2-self.margin-1 and e[4] >= self.y1+self.margin and e[4] <= self.y2-self.margin then
                    local clicked = e[4]+self.spos-self.y1-self.margin
                    self.lastY = e[4]

                    if self.txt[ clicked ] and e[2] == 1 then
                        self.sel = clicked
                        self:drawOptions()
                    end
                end
            elseif e[1] == "mouse_scroll" then
                if e[3] >= self.x1 and e[3] <= self.x2 and e[4] >= self.y1 and e[4] <= self.y2 then
                    if self.spos+e[2] > 0 and self.spos+e[2] < #self.txt-self.y2+self.y1+self.margin*2+1 then
                        self.spos = self.spos + e[2]
                        self:drawOptions()
                        self:drawBar()
                    end
                end
            elseif e[1] == "mouse_drag" then
                if self.lastY then
                    local diff = self.lastY-e[4]
                    self.lastY = e[4]

                    if self.spos+diff > 0 and self.spos+diff < #self.txt-self.y2+self.y1+self.margin*2+1 then
                        self.spos = self.spos + diff
                        self:drawOptions()
                        self:drawBar()
                    end
                end
            elseif e[1] == "key" then
                if e[2] == 200 then
                    if self.sel+self.spos > 2 then
                        self.spos = self.spos - ( self.sel-self.spos == 0 and 1 or 0 )
                        self.sel = self.sel - 1
                        self:drawBar()
                        self:drawOptions()
                    end
                elseif e[2] == 208 then
                    if self.sel < #self.txt then
                        self.spos = self.spos + ( self.sel-self.spos == self.y2-self.y1-self.margin*2 and 1 or 0 )
                        self.sel = self.sel + 1
                        self:drawBar()
                        self:drawOptions()
                    end
                end
            end
        end;

        getAttr = function( self, attr )
            if self.sel then
                return self.txt[ self.sel ][ attr ]
            end
        end;

        updateTxt = function( self, arg )
            for k, v in pairs( arg ) do
                if type( v ) == "string" then
                    arg[ k ] = {
                        txt = v;
                        fg = validColor( arg.unselfg, 32768 );
                        bg = validColor( arg.unselbg, 256 );
                        selfg = validColor( arg.selfg, 32768 );
                        selbg = validColor( arg.selbg, 8 );
                    }
                elseif type( v ) == "table" then
                    arg[ k ] = {
                        txt = v.txt or "";
                        fg = validColor( v.fg, 32768 );
                        bg = validColor( v.bg, 256 );
                        selfg = validColor( v.selfg, 32768 );
                        selbg = validColor( v.selbg, 8 );
                    }

                    for k1, v1 in pairs( v ) do
                        if not arg[ k ][ k1 ] then
                            arg[ k ][ k1 ] = v1
                        end
                    end
                end
            end

            self.txt = arg;
        end;

        advPrint = advPrint;
        setLen = setLen;
        scrollbg = validColor( arg.scrollbg, 128 );
        scrollfg = validColor( arg.scrollfg, 8 );
        bg = validColor( arg.bg, 256 );
        margin = tonumber( arg.margin ) and tonumber( arg.margin ) or 1;
        spos = 1;
        sel = 0;
        txt = arg.txt;
        barType = arg.altBar;

        x1 = math.min( arg.x1, arg.x2 );
        x2 = math.max( arg.x1, arg.x2 );
        y1 = math.min( arg.y1, arg.y2 );
        y2 = math.max( arg.y1, arg.y2 );

        isElement = true;
    }

    return new
end

function button( arg )
    assert( arg.x1 and arg.x2 and arg.y1 and arg.y2 )

    for k, v in pairs( arg.txt ) do
        if type( v ) == "string" then
            arg.txt[ k ] = {
                txt = v;
            }
        elseif type( v ) == "table" then
            arg.txt[ k ] = {
                txt = v.txt or "";
            }

            for k1, v1 in pairs( v ) do
                if not arg.txt[ k ][ k1 ] then
                    arg.txt[ k ][ k1 ] = v1
                end
            end
        end
    end

    local new = {
        draw = function( self )
            term.setBackgroundColor( self.bg )

            for i = self.y1, self.y2 do
                term.setCursorPos( self.x1, i )
                term.write( ( " " ):rep( self.x2-self.x1+1 ) )
            end

            local pos = math.floor( ( ( self.y2-self.y1+1 )-#self.txt )/2+0.5 ) + self.y1

            for i = 1, #self.txt do
                self.advPrint( setLen( self.txt[i].txt, self.x2-self.x1+1 ), pos+i-1, self.x1, self.x2 )
            end
        end;

        evHandle = function( self, ... )
            local e = { ... }

            if e[1] == "mouse_click" then
                if e[3] >= self.x1 and e[3] <= self.x2 and e[4] >= self.y1 and e[4] <= self.y2 then
                    return true
                end
            end
        end;

        advPrint = advPrint;
        setLen = setLen;
        bg = validColor( arg.bg, 256 );
        x1 = math.min( arg.x1, arg.x2 );
        x2 = math.max( arg.x1, arg.x2 );
        y1 = math.min( arg.y1, arg.y2 );
        y2 = math.max( arg.y1, arg.y2 );
        txt = arg.txt;

        isElement = true;
    }

    return new
end

function checkHitmap( arg )
    assert( type( arg ) == "table" and arg.x1 and arg.y1 and type( arg.hitmap ) == "table", "Too few or invalid arguments" )

    arg.hits = arg.hits or {}

    for k, v in pairs( arg.hitmap ) do
        if type ( v ) == "table" and not v.isElement then
            arg.hits[k] = checkHitmap( { x1 = arg.x1; y1 = arg.y1; hitmap = v } )
        elseif type( v ) == "table" and arg.x1 >= v.x1 and arg.x1 <= v.x2 and arg.y1 >= v.y1 and arg.y1 <= v.y2 then
            arg.hits[k] = v
        end
    end

    return arg.hits
end