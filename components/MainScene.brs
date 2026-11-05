sub init()
    m.menu = m.top.findNode("menu")
    m.categories = m.top.findNode("categories")
    m.channelsList = m.top.findNode("channels")
    m.liveCategoryTitle = m.top.findNode("liveCategoryTitle")
    m.grid = m.top.findNode("grid")
    m.episodes = m.top.findNode("episodes")
    m.status = m.top.findNode("status")
    m.video = m.top.findNode("video")

    m.sections = [
        { title: "Películas", kind: "home", root: "movies" },
        { title: "Series", kind: "home", root: "series" },
        { title: "Destacado", kind: "home", root: "featured" },
        { title: "Canales en vivo", kind: "live" },
        { title: "Buscar", kind: "search" },
        { title: "Servidor", kind: "server" }
    ]
    root = CreateObject("roSGNode", "ContentNode")
    for each s in m.sections
        n = root.CreateChild("ContentNode")
        n.title = s.title
    end for
    m.menu.content = root

    m.menu.observeField("itemSelected", "onMenuSelected")
    m.categories.observeField("itemSelected", "onCategorySelected")
    m.channelsList.observeField("itemSelected", "onChannelSelected")
    m.grid.observeField("itemSelected", "onGridSelected")
    m.episodes.observeField("itemSelected", "onEpisodeSelected")
    m.video.observeField("state", "onVideoState")

    m.items = []
    m.liveCategories = []
    m.liveBrowsing = false
    m.livePaginationSequence = 0
    m.livePaginationTag = ""
    m.livePageNum = 0
    m.livePageSize = 60
    m.livePageLimit = 5
    m.liveCategoryId = invalid
    m.liveCategoryName = ""
    m.liveChannels = []
    m.currentChannelIndex = -1
    m.liveResolveSequence = 0
    m.liveResolveTag = ""
    m.episodeItems = []
    m.currentSeries = ""
    m.server = RegRead("server")
    m.menu.setFocus(true)

    if m.server = "" then
        showKeyboard("server", "Dirección del servidor", "Ejemplo: http://192.168.1.95:8910", "http://")
    else
        loadSection(0)
    end if
end sub

' ---------- almacenamiento ----------
function RegRead(key as string) as string
    sec = CreateObject("roRegistrySection", "xuper")
    if sec.Exists(key) then return sec.Read(key)
    return ""
end function

sub RegWrite(key as string, value as string)
    sec = CreateObject("roRegistrySection", "xuper")
    sec.Write(key, value)
    sec.Flush()
end sub

' ---------- peticiones ----------
sub api(method as string, query as object, tag as string)
    t = CreateObject("roSGNode", "ApiTask")
    t.baseUrl = m.server
    t.method = method
    t.query = query
    t.tag = tag
    t.observeField("result", "onApiResult")
    if m.tasks = invalid then m.tasks = []
    m.tasks.push(t)
    t.control = "RUN"
    m.status.text = "Cargando…"
end sub

sub onApiResult(event as object)
    r = event.getData()
    if r = invalid then return
    tag = r.tag

    liveResolve = isLiveResolveTag(tag)
    livePagination = isLivePaginationTag(tag)

    if liveResolve and tag <> m.liveResolveTag then return
    if livePagination and tag <> m.livePaginationTag then return
    
    m.status.text = ""

    if r.returnValue = false
        if livePagination and m.liveChannels.count() > 0 then showChannels(m.liveChannels)
        m.status.text = "Error: " + r.errorText.toStr()
        return
    end if

    if tag = "home" or tag = "search" then
        showItems(r.items)
    else if tag = "liveCategories" then
        showLiveCategories(r.categories)
    else if livePagination then
        appendLiveChannelsPage(r.channels)
    else if tag = "detail" then
        showEpisodes(r)
    else if liveResolve then
        playResolved(r)
    else if tag = "resolve" then
        playResolved(r)
    end if
end sub

function isLiveResolveTag(tag as dynamic) as boolean
    return Instr(1, tag, "liveResolve_") = 1
end function

function isLivePaginationTag(tag as dynamic) as boolean
    return Instr(1, tag, "liveChannels_") = 1
end function

' ---------- menú ----------
sub onMenuSelected()
    loadSection(m.menu.itemSelected)
end sub

sub loadSection(index as integer)
    s = m.sections[index]
    m.liveResolveTag = ""
    m.livePaginationTag = ""
    m.episodes.visible = false
    m.categories.visible = false
    m.channelsList.visible = false
    m.liveCategoryTitle.visible = false
    m.grid.visible = true
    m.liveBrowsing = false
    if s.kind = "home" then
        api("home", { root: s.root }, "home")
    else if s.kind = "live" then
        m.liveBrowsing = true
        m.categories.visible = true
        m.grid.visible = false
        m.channelsList.visible = false
        m.categories.setFocus(true)
        api("liveCategories", {}, "liveCategories")
    else if s.kind = "search" then
        showKeyboard("search", "Buscar", "Título de película o serie", "")
    else if s.kind = "server" then
        showKeyboard("server", "Dirección del servidor", "Ejemplo: http://192.168.1.95:8910", m.server)
    end if
end sub

' ---------- contenido ----------
sub showItems(items as object)
    m.categories.visible = false
    m.channelsList.visible = false
    m.liveCategoryTitle.visible = false
    m.grid.visible = true
    m.items = items
    root = CreateObject("roSGNode", "ContentNode")
    if items <> invalid
        for each it in items
            n = root.CreateChild("ContentNode")
            n.title = it.title
            n.shortDescriptionLine1 = it.title
            posterUrl = rewritePosterHost(it.poster)
            n.HDPosterUrl = posterUrl
            n.SDPosterUrl = posterUrl
            n.description = it.synopsis
        end for
    end if
    m.grid.content = root
    m.grid.setFocus(true)
end sub

function rewritePosterHost(poster as dynamic) as string
    if poster = invalid then return ""
    posterUrl = poster.toStr()

    schemeEnd = Instr(1, posterUrl, "://")
    if schemeEnd > 0
        authorityStart = schemeEnd + 3
    else if Left(posterUrl, 2) = "//"
        authorityStart = 3
    else
        return posterUrl
    end if

    if authorityStart > Len(posterUrl) then return posterUrl

    suffixStart = Len(posterUrl) + 1
    for each delimiter in ["/", "?", "#"]
        delimiterPosition = Instr(authorityStart, posterUrl, delimiter)
        if delimiterPosition > 0 and delimiterPosition < suffixStart
            suffixStart = delimiterPosition
        end if
    end for

    if suffixStart = authorityStart then return posterUrl
    return "https://cftpbe.39114gi1.com" + Mid(posterUrl, suffixStart)
end function

sub showLiveCategories(categories as object)
    m.liveCategories = categories
    root = CreateObject("roSGNode", "ContentNode")
    if categories <> invalid
        for each category in categories
            n = root.CreateChild("ContentNode")
            n.title = category.name
        end for
    end if
    m.categories.content = root
    m.categories.visible = true
    m.channelsList.visible = false
    m.liveCategoryTitle.visible = false
    m.grid.visible = false
    m.categories.setFocus(true)
end sub

sub onCategorySelected()
    idx = m.categories.itemSelected
    if idx < 0 or idx >= m.liveCategories.count() then return
    category = m.liveCategories[idx]
    m.liveCategoryName = category.name
    m.livePaginationSequence = m.livePaginationSequence + 1
    m.livePaginationTag = "liveChannels_" + m.livePaginationSequence.toStr()
    m.liveCategoryId = category.id
    m.livePageNum = 1
    m.liveChannels = []
    api("liveChannels", { columnId: m.liveCategoryId, pageNum: m.livePageNum, pageSize: m.livePageSize }, m.livePaginationTag)
end sub

sub appendLiveChannelsPage(channels as object)
    if channels <> invalid
        for each channel in channels
            m.liveChannels.push(channel)
        end for
    end if

    if m.livePageNum < m.livePageLimit
        m.livePageNum = m.livePageNum + 1
        api("liveChannels", { columnId: m.liveCategoryId, pageNum: m.livePageNum, pageSize: m.livePageSize }, m.livePaginationTag)
    else
        showChannels(m.liveChannels)
    end if
end sub

sub showChannels(channels as object)
    m.items = []
    m.currentChannelIndex = -1
    root = CreateObject("roSGNode", "ContentNode")
    if channels <> invalid
        channelNumber = 1
        for each ch in channels
            m.items.push({ kind: "canal", channelCode: ch.channelCode, title: ch.name })
            n = root.CreateChild("ContentNode")
            n.title = channelNumber.toStr() + ". " + ch.name
            channelNumber = channelNumber + 1
        end for
    end if
    m.channelsList.content = root
    m.categories.visible = false
    m.grid.visible = false
    m.liveCategoryTitle.text = m.liveCategoryName
    m.liveCategoryTitle.visible = true
    m.channelsList.visible = true
    m.channelsList.setFocus(true)
end sub

sub onChannelSelected()
    idx = m.channelsList.itemSelected
    if idx < 0 or idx >= m.items.count() then return
    playLiveChannel(idx)
end sub

sub onGridSelected()
    idx = m.grid.itemSelected
    if idx < 0 or idx >= m.items.count() then return
    it = m.items[idx]
    if it.kind = "canal" then
        playLiveChannel(idx)
    else if it.type = "teleplay" or it.kind = "serie" then
        m.currentSeries = it.id
        m.seriesTitle = it.title
        api("detail", { contentId: it.id }, "detail")
    else
        m.playTitle = it.title
        m.playLive = false
        api("resolveDash", { contentId: it.id }, "resolve")
    end if
end sub

sub playLiveChannel(index as integer)
    if index < 0 or index >= m.items.count() then return
    channel = m.items[index]
    if channel.kind <> "canal" then return

    m.currentChannelIndex = index
    m.playTitle = channel.title
    m.playLive = true
    m.liveResolveSequence = m.liveResolveSequence + 1
    m.liveResolveTag = "liveResolve_" + m.liveResolveSequence.toStr()
    api("resolveLive", { channelCode: channel.channelCode }, m.liveResolveTag)
end sub

sub showEpisodes(r as object)
    m.episodeItems = r.episodes
    root = CreateObject("roSGNode", "ContentNode")
    if m.episodeItems <> invalid
        for each ep in m.episodeItems
            n = root.CreateChild("ContentNode")
            n.title = ep.title
        end for
    end if
    m.episodes.content = root
    m.grid.visible = false
    m.channelsList.visible = false
    m.liveCategoryTitle.visible = false
    m.episodes.visible = true
    m.episodes.setFocus(true)
end sub

sub onEpisodeSelected()
    idx = m.episodes.itemSelected
    if idx < 0 or idx >= m.episodeItems.count() then return
    ep = m.episodeItems[idx]
    m.playTitle = ep.title
    m.playLive = false
    api("resolveDash", { contentId: ep.id, seriesContentId: m.currentSeries }, "resolve")
end sub

' ---------- reproducción ----------
sub playResolved(r as object)
    url = r.proxyPath
    if url = invalid or url = "" then url = r.url
    if url = invalid or url = "" then
        m.status.text = "Señal no disponible"
        return
    end if

    fmt = "mp4"
    if r.isDash = true or Instr(1, url, ".mpd") > 0 then
        fmt = "dash"
        sleep(5000)
    else if r.isHls = true or Instr(1, url, ".m3u8") > 0 then
        fmt = "hls"
    else if r.mime = "video/mp4" or Instr(1, url, ".mp4") > 0 then
        fmt = "mp4"
    else if Instr(1, url, "stream.ts") > 0 then
        ' Roku no reproduce .ts suelto: el servidor lo ofrece como HLS virtual.
        url = Left(url, Instr(1, url, "stream.ts") - 1) + "stream.m3u8"
        fmt = "hls"
    end if
    
    c = CreateObject("roSGNode", "ContentNode")
    c.url = url
    c.title = m.playTitle
    c.streamFormat = fmt
    c.live = m.playLive
    m.video.content = c
    m.video.visible = true
    m.video.setFocus(true)
    m.video.control = "play"
end sub

sub onVideoState()
    st = m.video.state
    if st = "error" then
        m.status.text = "No se pudo reproducir: " + m.video.errorMsg.toStr()
        stopVideo()
    else if st = "finished" then
        stopVideo()
    end if
end sub

sub stopVideo()
    m.video.control = "stop"
    m.video.visible = false
    m.liveResolveTag = ""
    api("abortMedia", {}, "abort")
    if m.episodes.visible then
        m.episodes.setFocus(true)
    else if m.channelsList.visible then
        m.channelsList.setFocus(true)
    else
        m.grid.setFocus(true)
    end if
end sub

' ---------- teclado ----------
sub showKeyboard(purpose as string, title as string, message as string, initial as string)
    m.kbPurpose = purpose
    d = CreateObject("roSGNode", "StandardKeyboardDialog")
    d.title = title
    d.message = [message]
    d.text = initial
    d.buttons = ["Aceptar", "Cancelar"]
    d.observeField("buttonSelected", "onKeyboardButton")
    m.kb = d
    m.top.dialog = d
end sub

sub onKeyboardButton()
    idx = m.kb.buttonSelected
    text = m.kb.text
    m.top.dialog.close = true
    if idx <> 0 then return
    if m.kbPurpose = "server" then
        m.server = text
        while Right(m.server, 1) = "/"
            m.server = Left(m.server, Len(m.server) - 1)
        end while
        RegWrite("server", m.server)
        loadSection(0)
    else if m.kbPurpose = "search" and text <> "" then
        api("search", { value: text }, "search")
    end if
end sub

' ---------- mando ----------
function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false
    if m.video.visible and m.playLive and (key = "up" or key = "down") then
        nextChannelIndex = m.currentChannelIndex
        if key = "up" then
            nextChannelIndex = nextChannelIndex - 1
        else
            nextChannelIndex = nextChannelIndex + 1
        end if
        if nextChannelIndex < 0 or nextChannelIndex >= m.items.count() then
            m.status.text = "No hay más canales"
        else
            playLiveChannel(nextChannelIndex)
        end if
        return true
    end if
    if key = "back" then
        if m.video.visible then
            stopVideo()
            return true
        else if m.episodes.visible then
            m.episodes.visible = false
            m.grid.visible = true
            m.grid.setFocus(true)
            return true
        else if m.categories.hasFocus() then
            m.categories.visible = false
            m.grid.visible = true
            m.liveBrowsing = false
            m.menu.setFocus(true)
            return true
        else if m.channelsList.hasFocus() then
            m.channelsList.visible = false
            m.liveCategoryTitle.visible = false
            m.grid.visible = false
            m.categories.visible = true
            m.categories.setFocus(true)
            return true
        else if m.grid.hasFocus() and m.liveBrowsing then
            m.grid.visible = false
            m.categories.visible = true
            m.categories.setFocus(true)
            return true
        else if m.grid.hasFocus() then
            m.menu.setFocus(true)
            return true
        end if
    else if key = "left" and (m.grid.hasFocus() or m.channelsList.hasFocus() or m.categories.hasFocus()) then
        m.menu.setFocus(true)
        return true
    else if key = "right" and m.menu.hasFocus() then
        if m.categories.visible then
            m.categories.setFocus(true)
        else if m.channelsList.visible then
            m.channelsList.setFocus(true)
        else
            m.grid.setFocus(true)
        end if
        return true
    end if
    return false
end function
